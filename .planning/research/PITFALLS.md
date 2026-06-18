# Pitfalls Research: Game Boy (DMG) Emulator in Zig

**Domain:** Emulator development — Sharp LR35902 / SM83 CPU, Game Boy DMG-01 hardware, plus Zig 0.14+ language/runtime specifics.
**Researched:** 2026-06-18
**Confidence:** HIGH for the GB-hardware pitfalls (primary sources: Pan Docs, SameBoy/SameSuite, Mooneye test suite README, Gekkio blog posts). MEDIUM for the Zig-specific items (verified against Zig 0.14.0 language reference; some items are community wisdom that may shift between Zig versions — flagged below).

---

## Executive Summary

ZigBoy's pitfalls divide into two clean groups: **Game Boy hardware-correctness** (game-breaking if missed) and **Zig implementation** (mostly performance / determinism / build issues). The hardware pitfalls are well-documented in the gbdev ecosystem; the trap is treating them as edge cases when they are in fact load-bearing for many commercial games (Tetris, Pokémon, Zelda, Super Mario Land). The Zig pitfalls are subtler — a 4 MHz emulator doing 256 opcodes × 59.7 fps × 50,000+ instructions/frame on the hot path will trip every Zig footgun if the build isn't tuned.

**Top 3 risks to defuse in the roadmap:**

1. **Timer / interrupt / HALT-bug interactions** — the LR35902's quirks (falling-edge detector, `ei` delay, halt bug) are non-obvious and untested by naive Blargg `cpu_instrs` passes. Without Mooneye `timer` and `interrupt/` tests, games will silently misbehave in subtle ways.
2. **PPU mode-based bus blocking + STAT writes** — VRAM/OAM are *physically inaccessible* during mode 3, and writing to STAT during mode 2 fires a spurious IRQ on DMG. Either mistake produces graphical glitches that only some games notice.
3. **MBC1 00→01 bank translation + mode 1 wiring** — the trap of treating "writing 0 = bank 0" the same as MBC5, or assuming the secondary register applies uniformly to both ROM and RAM in 1 MiB+ carts. This bricks larger MBC1 games and most MBC1M multicarts.

---

## Critical Pitfalls

### Pitfall 1: Treating the Timer as a Naive Counter

**What goes wrong:** TIMA doesn't increment on a tick — it increments on the *falling edge* of a selected bit of a 16-bit system counter that is incremented every M-cycle. This produces several real-world behaviors: writing to DIV (`$FF04`) can fire an extra TIMA tick or APU event (because writing 0 to DIV resets the system counter, which can flip a selected bit from 1→0), and changing TAC to select a *different* bit (currently set vs unset) can also fire a tick. Naive emulators that increment TIMA on a fixed schedule produce wrong music in tracks that use DIV as a random seed, wrong APU sweep behavior, and miss the "tim00 div trigger" / "tim01 div trigger" / "rapid toggle" Mooneye tests.

**Why it happens:** Pan Docs § "Timer Obscure Behaviour" describes a circuit involving a falling-edge detector connected to a multiplexer. A developer reading only the "TIMA is incremented at frequency X" register description will not see the obscure path.

**How to avoid:** Model the system counter as a 16-bit value that increments on every M-cycle. On writes to DIV, set the low 8 bits of the system counter to 0 (which can fire falling edges on the bit selected by TAC, including the special DMG case where *disabling* the timer with the bit still set also fires one tick). On writes to TAC, recompute the falling-edge detector. Use `@addWithOverflow` or explicit `& 0xFF` rather than `+= 1` to model the 8-bit TIMA overflow; on overflow, schedule the TIMA→TMA copy and the IF flag set *one M-cycle later* (Pan Docs § "Timer overflow behavior"), not synchronously.

**Warning signs:**
- `rapid toggle` Mooneye test fails
- `tima reload` / `tima write reloading` / `tma write reloading` Mooneye tests fail
- Audio (when added) sounds subtly wrong
- `div write` Mooneye test fails

**Phase to address:** Phase 2 (Timer + Interrupts). The CPU and bus phase (1) must be cycle-accurate enough that 1 M-cycle = 4 dots; the timer phase then owns the system counter.

**Verification:** Run the full Mooneye `acceptance/timer` suite (tim00/01/10/11, div trigger variants, tima reload, tma write reloading) plus Blargg's `instr_timing` and `mem_timing-2` (which exercise the timer indirectly).

---

### Pitfall 2: HALT Bug + `ei` Delay + Interrupt Servicing Order

**What goes wrong:** Three tightly-coupled quirks that the SM83 deviates from "obvious" Z80 behavior on:

1. **`ei` delay:** IME is set *one instruction after* `ei`. `ei; di` therefore does *not* enable interrupts between the two.
2. **HALT bug:** If IME=0 and `(IE & IF) != 0` when `halt` is executed, the CPU exits HALT but does *not* advance PC. The byte after `halt` is re-executed. This is the documented "halt bug."
3. **Interrupt priority:** When multiple `IF` bits are set, VBlank (bit 0) is serviced first, descending. The handler address is `$40, $48, $50, $58, $60`.

Missing any of these causes boot loops, broken `ei; halt` VBlank waiters (the *most common* frame-locking pattern in DMG games), or wrong order in handlers that rely on the natural priority.

**Why it happens:** It's tempting to "just set IME=1 on EI" and "increment PC on HALT" because those match the Z80 mental model. The SM83 is *not* a Z80; Pan Docs § "Interrupts" and § "`halt`" are explicit.

**How to avoid:** Model IME as a delayed-flag: a 1-cycle scheduler. After `ei` (which takes 1 M-cycle), the *next* instruction ends before IME=1 takes effect. HALT exits when `(IE & IF) != 0`; if IME was 0 at the moment of the HALT instruction, leave a "halt bug" pending flag that suppresses the PC increment for the instruction after HALT. SameSuite's `ei_delay_halt.asm` and Mooneye's `halt_ime0_ei` cover this.

**Warning signs:**
- `ei sequence`, `halt ime0 ei`, `halt ime1 timing`, `ei timing` Mooneye tests fail
- SameSuite `interrupt/ei_delay_halt` fails
- Game gets stuck in boot animation, then halts (classic halt-bug + missing IME)

**Phase to address:** Phase 1 (CPU) for the basic HALT/IME/interrupt-flag handling; Phase 2 for the timer/STAT interrupt source wiring. The bug is partially CPU-flag-handling and partially interrupt-acknowledgment, so it straddles both phases.

**Verification:** SameSuite `interrupt/` directory + Mooneye `interrupt/if_ie_registers`, `interrupt/ie_push`, plus boot ROM tests that exercise the VBlank handler from the boot ROM.

---

### Pitfall 3: PPU Mode-Based Bus Blocking (Mode 3)

**What goes wrong:** During PPU mode 3 (drawing scanline pixels), the CPU cannot read or write VRAM (`$8000-$9FFF`) or OAM (`$FE00-$FE9F`). Reads return garbage (typically `$FF`); writes are silently dropped. The window is variable-length (172–289 dots) because of SCX-modulo-8, window-setup, and OBJ penalties. Naive emulators that let the CPU access VRAM/OAM any time will pass simple `dmg-acid` but fail in games that update tiles mid-frame (most action games do).

**Why it happens:** The PPU and CPU share a 16-bit bus; during mode 3 the PPU has it. Pan Docs § "Accessing VRAM and OAM" is the spec.

**How to avoid:** Track the current PPU mode and current dot within the scanline. Compute mode 3 length from SCX%8 + window-penalty + OBJ-penalties. During mode 3, redirect any CPU access to VRAM/OAM to a "blocked" handler (reads return `$FF`, writes no-op). Switch to "open bus" semantics carefully: Pan Docs notes the read is "typically $FF but not guaranteed," so do *not* treat it as a strong constant — `dmg-acid` will not catch a wrong constant but some homebrew will.

**Warning signs:**
- `vblank_stat_intr` Mooneye test fails
- `intr_2_mode3_timing` Mooneye test fails (Mode 2 → Mode 3 transition with VRAM write at the boundary)
- Visual glitches that "look fine" on the title screen but glitch in-game during horizontal scrolling
- Tetris piece flicker / overdraw during line clears

**Phase to address:** Phase 3 (PPU). The bus-blocking is part of the cycle-accurate PPU implementation. The CPU must be tickable one M-cycle at a time for the bus-blocking check to be testable.

**Verification:** Mooneye `ppu/vblank_stat_intr`, `ppu/intr_2_mode3_timing`, plus SameSuite `ppu/vram_read` if it exists. Game test: Zelda: Link's Awakening has visible mid-frame tile updates; Tetris has mid-frame line clears.

---

### Pitfall 4: OAM DMA Bus Conflicts on DMG

**What goes wrong:** When the CPU writes `$XX` to `$FF46` to start an OAM DMA, the DMA copies `$XX00-$XX9F` → `$FE00-$FE9F` in 160 M-cycles. **On DMG, during the transfer, the CPU can only access HRAM (`$FF80-$FFFE`)** — accessing any other bus region returns open-bus or triggers bus conflicts. The standard idiom is to copy a short routine into HRAM and `call` it from there.

**Why it happens:** On DMG, OAM DMA and the CPU share the external bus. CGB has split buses and is less restrictive, but DMG does not. Pan Docs § "OAM DMA Transfer" describes this in detail; many emulator authors only read the CGB-friendly wording.

**How to avoid:** When emulating OAM DMA, lock the bus for 160 M-cycles. During the lock, any CPU read/write to non-HRAM returns open-bus (typically `$FF` for reads, no-op for writes). Track remaining DMA cycles inside the cycle-accurate loop and decrement each M-cycle. Tests: Mooneye `oam_dma/` suite (`basic`, `reg_read`, `sources`, `restart`, `start`, `timing`).

**Warning signs:**
- Mooneye `oam_dma/sources`, `oam_dma/timing` fail
- Sprite tearing in games that update OAM mid-scanline (e.g., racing games with many sprites)
- Graphical glitches only on DMG (would also be wrong on a CGB in DMG mode, but only DMG-style emulators show this)

**Phase to address:** Phase 3 (PPU/OAM DMA). Cannot be tested without the cycle-accurate bus model from Phases 1-2.

**Verification:** Mooneye `oam_dma` acceptance tests + a game with heavy sprite movement (e.g., Pokémon Red battle scenes).

---

### Pitfall 5: OAM Corruption Bug (DMG-only, real-hardware quirk)

**What goes wrong:** On DMG, performing `inc rr`, `dec rr`, `ld [hli],a`, `ld [hld],a`, `ld a,[hli]`, `ld a,[hld]`, `pop rr`, `ret` family, `push rr`, `call` family, `rst`, or interrupt handling while a 16-bit register is in `$FE00-$FEFF` and the PPU is in mode 2 (OAM scan) will **corrupt OAM with a deterministic bitwise pattern**. The pattern depends on which OAM row is being read, the previous row, and the operation. CGB and later are not affected.

**Why it happens:** The SM83's 16-bit increment/decrement unit is tied to the address bus; it outputs the value as an address even when not asserting a read/write, causing a "ghost" OAM access. Pan Docs § "OAM Corruption Bug" gives the exact corruption formulae.

**How to avoid:** Either (a) detect when a 16-bit operation with a value in `$FE00-$FEFF` executes during mode 2, and apply the corruption formula to the currently-accessed OAM row; or (b) only emulate this if you intend to run games that *exploit* the bug (most don't). The Mooneye test `oam_bug-2` (Blargg) verifies the behavior. Realistically, this is "implement later, after DMG core is stable" — but document it as a known gap. **For v1, plan to mark the test as "expected fail" with a clear note.**

**Warning signs:**
- Blargg `oam_bug-2` test fails (this is the explicit test for it)
- Random sprite corruption in games that incidentally trip the bug (Tetris, some Game & Watch titles)

**Phase to address:** Phase 3 (PPU/OAM) but explicitly **deferred** — implement only if a target game requires it. Add a "deferred quirk" entry in the PPU phase, not a blocker.

**Verification:** Blargg `oam_bug-2` (negative test — DMG core without quirk emulation is the realistic baseline).

---

### Pitfall 6: MBC1 00→01 Bank Translation and Mode 1 Wiring

**What goes wrong:** Two MBC1-specific traps:

1. **Bank 0 redirection:** Writing `$00` to `$2000-$3FFF` does *not* map bank 0 to `$4000-$7FFF`; it maps bank 1. The only way to access bank 0 in `$4000-$7FFF` on a 256 KiB-or-smaller cart is to set the unused 5th bit (write `$10`, `$20`, etc.) to bypass the translation.
2. **1 MiB+ carts with secondary register:** On 1 MiB+ ROM, the 2-bit register at `$4000-$5FFF` is wired as *upper bits of the ROM bank number*, not as a RAM bank. In mode 0 (default), the 2-bit register is forced to 0 for accesses to `$0000-$3FFF` (and to `$A000-$BFFF`), locking bank 0 of ROM/RAM there. In mode 1, the 2-bit register applies to both `$0000-$3FFF` and `$A000-$BFFF`.
3. **MBC1M multicarts** (1 MiB MBC1 multicompilations) have a different formula: the 2-bit register applies to bits 4-5 of the bank number, not bits 5-6.

**Why it happens:** The MBC1 datasheet (reverse-engineered) and Pan Docs § "MBC1" describe this with caveats that are easy to skim.

**How to avoid:** Implement MBC1 as a tagged union or interface with three modes: small ROM (≤256 KiB, 32 KiB RAM, 2-bit register = RAM bank), large ROM (≥512 KiB, 8 KiB RAM, 2-bit register = ROM upper bits), MBC1M (1 MiB multi-cart with different formula). Apply the 00→01 translation by *storing* the 5-bit value but *mapping* 0 to 1 on read. For mode 1, route the secondary register to both the upper ROM bank and the RAM bank. Run Mooneye `emulator-only/mbc1` tests (`bits_bank1`, `bits_bank2`, `bits_mode`, `bits_ramg`, `rom_512kb` ... `rom_16Mb`, `ram_64kb`, `ram_256kb`, `multicart_rom_8Mb`).

**Warning signs:**
- Mooneye `mbc1/rom_512kb` through `rom_16Mb` fail
- `mbc1/multicart_rom_8Mb` fails (specific to MBC1M wiring)
- Games fail to load at title screen, hang in initial banking setup, or "see" the wrong code path
- Crashes specifically on the second page of code (i.e., `$4000-$7FFF` after `$2000` write)

**Phase to address:** Phase 4 (MBC & persistence). MBC1 must be a separate subtype from "no-MBC" (ROM-only) and from MBC3/MBC5.

**Verification:** Mooneye `emulator-only/mbc1` full suite. Cross-check with commercial games: Pokémon Red (1 MiB MBC3+RAM+BATTERY, not MBC1, but tests the larger-cart path), Tetris (no MBC, doesn't exercise it), Legend of Zelda: Link's Awakening (1 MiB MBC3, again not MBC1 but the path).

---

### Pitfall 7: MBC3 RTC Latch is a Two-Write Sequence

**What goes wrong:** On MBC3 with the RTC (cartridge type `$0F` or `$10`), reading the RTC registers at `$A000-$BFFF` returns the *currently latched* time, not the live counter. Latching happens when `$00` is written to `$6000-$7FFF` followed by `$01` on the next write. A naive implementation that lets you read the live counter produces wildly different values between calls and breaks Pokémon Gold/Silver/Crystal's clock-based events.

**Why it happens:** Pan Docs § "MBC3" specifies the latch sequence explicitly; emulator authors often read the RTC register select first and miss the latch.

**How to avoid:** Track an "RTC latched" state. On write to `$6000-$7FFF`, if the value is `$00`, set a `pending_latch = true` flag. On the *next* write to `$6000-$7FFF`, if pending and the value is `$01`, copy the live RTC into latched registers and clear the flag. Any other value resets pending_latch. Reads of `$08-$0C` of the bank select always return the latched values. **For v1, RTC is out of scope** (no Pokémon Gold/Silver/Crystal as a target), but the latch must be implemented correctly to avoid breaking MBC3 RTC carts' behavior. Skip if not targeting RTC carts.

**Warning signs:**
- Pokémon Gold/Silver clock shows nonsense
- Time-based events (daily berries, day/night cycle) trigger at the wrong time

**Phase to address:** Phase 4 (MBC) — but flag as **deferred** if v1 scope excludes RTC carts. The non-RTC MBC3 path (type `$11`, `$12`, `$13`) doesn't need the latch logic.

**Verification:** Skipped in v1. Add an issue/marker if scope is later expanded.

---

### Pitfall 8: Spurious STAT Interrupt on STAT Writes (DMG-only)

**What goes wrong:** On DMG (and SGB/SGB2, but *not* CGB in DMG mode), writing to the STAT register (`$FF41`) during OAM scan (mode 2), HBlank (mode 0), VBlank (mode 1), or when `LY == LYC` can fire a spurious STAT interrupt. The hardware behaves "as if `$FF` were written for one M-cycle, then the written value were written the next M-cycle." Two games depend on this quirk: Ocean's *Road Rash* and Vic Tokai's *Xerd no Densetsu*. GBC in DMG mode does not have the bug.

**Why it happens:** Pan Docs § "STAT" describes this as a "spurious STAT interrupt" hardware quirk. CGB revisions fixed it, which is why GBC-mode emulators don't need to emulate it.

**How to avoid:** On writes to `$FF41` during the listed PPU states, set IF bit 1 (LCD) for one M-cycle *unless* IME=0 and the corresponding STAT source is already masked — actually, the simplest is to always fire the spurious IRQ for one M-cycle if the current state matches. For v1, mark *Road Rash* and *Xerd no Densetsu* as "out of scope" or "known failure" rather than implementing the quirk. Test: same-suite doesn't have a public ROM for this, so the practical signal is "those two specific games misbehave on every emulator except BGB and SameBoy."

**Warning signs:**
- Those two specific games glitch on the first screen after boot
- IF register briefly gets bit 1 set after a STAT write

**Phase to address:** Phase 3 (PPU) but **deferred** — practically a v2+ concern. Document as a "known divergence" in the PPU phase.

**Verification:** No public test ROM. Manual testing with the two specific games, or skip.

---

### Pitfall 9: Open-Bus Reads and Unimplemented/Unused Memory Regions

**What goes wrong:** Reads from "unmapped" or "no cartridge" addresses don't return a fixed value — they return whatever was last on the data bus ("open bus"). The convention is `$FF` *most* of the time, but the docs are explicit: "not guaranteed." The `$FEA0-$FEFF` range has *revision-specific* behavior (returns `$00` on DMG/MGB/SGB/SGB2, returns the high nibble twice on CGB-E/AGB/AGS, etc.). The unused high bits of register F (Z80-style) are always 0. The unused high bits of LY-compare or other registers return 1. Mis-handling any of these produces failing tests on Mooneye's `bits/unused_hwio` and `bits/mem_oam`.

**Why it happens:** It's tempting to fill unmapped regions with `$FF` in a `switch` statement, which works for most reads but fails on tests that probe the exact value.

**How to avoid:** Track the last data bus value as a CPU-level `data_bus` u8 variable. Any open-bus read returns the last `data_bus`. Reset to `$FF` on any bus-driving event. For `$FEA0-$FEFF`, model DMG's `$00` read explicitly. For the F register, mask to the low 4 bits. For unused register bits, set them to 1 on read (and ignore on write).

**Warning signs:**
- Mooneye `bits/unused_hwio`, `bits/mem_oam`, `bits/reg_f` fail
- `cpu_instrs` Blargg test fails on the "unused opcode" section
- Cartridge-less boot DMG scrolls a "Nintendo" logo that has subtle wrong pixels (because the logo bytes are read as open bus)

**Phase to address:** Phase 1 (CPU + bus) for the data-bus tracking; Phase 3 (PPU) for the OAM-access window where the bus is driven by the PPU.

**Verification:** Mooneye `bits/` suite + boot without a cart (should show the boot ROM's `$FF`-filled logo).

---

### Pitfall 10: Invalid Opcodes Lock the CPU Forever

**What goes wrong:** Eleven opcodes are documented as "hard-locking" the CPU until power-off: `$D3, $DB, $DD, $E3, $E4, $EB, $EC, $ED, $F4, $FC, $FD`. These are removed Z80 instructions (OUT, IN, IX/IY prefixes, etc.). A common emulator error is to `unreachable` them, which will pass `cpu_instrs` (which never executes them) but produce a "fine" emulator that then diverges from real hardware if a corrupted cartridge ever lands on one. The *correct* behavior is to spin the CPU forever (an infinite loop on the same PC).

**Why it happens:** Rust's `unreachable_unchecked`, C++ `__builtin_unreachable`, Zig's `unreachable` all produce a single trap. Pan Docs § "CPU Instruction Set" is explicit that these lock the CPU — meaning real hardware just stops.

**How to avoid:** Implement them as `while (true) {}` on the dispatch loop, with a flag to break out (for tests). Better, increment an "infinite loop" counter and bail after N cycles (e.g., 100,000) so a test ROM that intentionally hits one of them doesn't hang the test runner. Document the behavior in the CPU core.

**Warning signs:**
- Tests that intentionally execute invalid opcodes hang the test runner
- A corrupted save file that "executes" `$D3` causes a hang rather than a controlled bail

**Phase to address:** Phase 1 (CPU). The opcode table is part of the core decode table.

**Verification:** SameSuite doesn't test this directly. Add a custom test ROM (or unit test) that hits `$D3` and verifies the emulator either spins or bails cleanly.

---

## Moderate Pitfalls

### Pitfall M1: Interrupt-Service-Routine Timing (5 M-cycles, not 4)

**What goes wrong:** Interrupt dispatch takes **5 M-cycles**, not the 3 the obvious Z80 mental model gives. Pan Docs § "Interrupts" lists: 2 wait M-cycles + 2 M-cycles for pushing PC + 1 M-cycle to set PC. Missing any of these skews the bus timing enough to break Blargg `instr_timing` and `mem_timing-2`.

**How to avoid:** Count M-cycles in the CPU step. Add 5 M-cycles when servicing an interrupt, before resuming the main loop.

**Phase:** Phase 1 (CPU) for the cycle counting; Phase 2 (interrupts) for the wiring.

**Verification:** Mooneye `intr_timing`, `reti_intr_timing`, SameSuite timing tests.

---

### Pitfall M2: `stop` Instruction Has a Cursed Decision Tree

**What goes wrong:** On DMG, `stop` is documented as "intended for very-low-power standby, terminated by joypad line going low." But its actual behavior is wildly state-dependent: it can enter STOP, enter HALT instead, NOP, behave as a 1-byte opcode, or "glitch the CPU in a non-deterministic fashion" depending on what `KEY1` says, the LCD state, and the second byte. No licensed DMG game uses `stop` outside of CGB speed switching. Pan Docs provides a "stop decision chart" but it's literally a flowchart.

**How to avoid:** For v1 DMG-only: implement `stop` as a no-op followed by a PC advance of 2 (the standard 2-byte form). Document that this is "good enough" — no licensed DMG game relies on the more exotic paths. **Do not** model the P10-P13 termination; that requires a joypad state hookup. If a homebrew ROM uses `stop`, it'll misbehave — but that is acceptable scope.

**Phase:** Phase 1 (CPU). One-line decision in the decode table.

**Verification:** No public test ROM. Verify `stop` is at least a no-op and doesn't trap.

---

### Pitfall M3: Boot Register / Hardware Register Initial State

**What goes wrong:** The DMG boot ROM leaves registers and I/O in a specific state (`A=$01, B=$00, C=$13, D=$00, E=$D8, H=$01, L=$4D, F=Z=1 N=0 H=? C=?, PC=$0100, SP=$FFFE`; `LCDC=$91, STAT=$85, DIV=$AB, IF=$E1, IE=$00, ...`). The Mooneye `boot_regs-dmgABC` and `boot_hwio-dmgABCmgb` tests check these exactly. A naive emulator that zeroes all state will fail both. With *no* boot ROM (most emulators skip the boot ROM), the *cartridge's* `$0100` jumps directly to the entry point, but the *test ROMs expect boot-ROM state* anyway because they encode the values they read from registers and compare.

**How to avoid:** When implementing "skip boot ROM" mode, *manually* set the documented post-boot state (DMG variant). For DMG, the values are in Pan Docs § "Power_Up_Sequence" § "Console state after boot ROM hand-off." Setting them as a one-time init at the start of emulation makes the test ROMs pass. **However**, you must also handle the case where a *real* boot ROM is provided — then the boot ROM runs and writes its own state, including `$FF50` to unmap itself. The two paths are mutually exclusive; pick one and stick to it.

**Phase:** Phase 1 (ROM load) — set initial state at boot.

**Verification:** Mooneye `acceptance/boot_regs-dmgABC`, `acceptance/boot_hwio-dmgABCmgb`, `acceptance/boot_div-dmgABCmgb`. (Note: these pass in *no-boot-ROM* mode only because we set the documented state; they pass in *with-boot-ROM* mode only because the boot ROM writes it.)

---

### Pitfall M4: SCX Mid-Scanline Behavior (Y Coordinate Re-Read)

**What goes wrong:** The PPU re-reads SCY once per bitplane during a tile fetch on pre-CGB-D models; mid-scanline writes to SCY can desync the two bitplanes (causing a single-line "wavy" effect). On CGB-D and later, both bitplanes use the same Y coordinate. DMG (which is pre-CGB-D) has the desync. A naive PPU that reads SCY once at the start of the scanline will not produce this effect, which is used by some games for split-screen tricks.

**How to avoid:** Read SCY per bitplane (twice per tile). For DMG, accept that this is a non-default-behavior mode. Optional for v1 — the Pan Docs note is that "all models before the CGB-D" do this, which is a small set including DMG/MGB/SGB. Most games don't depend on it.

**Phase:** Phase 3 (PPU). Document as a known-divergence if not implemented.

**Verification:** Mooneye `ppu/lcdon_write_timing` covers related timing but not SCY desync directly. SameSuite may have a test.

---

### Pitfall M5: Cartridge Header Checksum and Logo Verification

**What goes wrong:** The boot ROM verifies (a) the Nintendo logo at `$0104-$0133` matches a known pattern, and (b) the header checksum at `$014D` equals the result of `checksum = 0; for (i=0x0134; i<=0x014C; i++) checksum = checksum - rom[i] - 1;` (Pan Docs § "The Cartridge Header"). **If either fails, the boot ROM locks up.** A test ROM that expects to run on a real boot ROM will misbehave if the header is corrupt; a test ROM that uses the documented "post-boot state" should be self-consistent, but the values in the header *itself* still need to be parsed correctly to map the MBC type and RAM size.

**How to avoid:** Always validate the header at load time. If checksum is wrong, log a warning but still parse (don't refuse to run — many test ROMs and homebrew have intentional non-matching headers). If logo bytes are wrong, the boot ROM path will hang; in *no-boot-ROM* mode, this doesn't matter. **Always parse the MBC type from `$0147` and ROM/RAM sizes from `$0148-$0149` correctly** — these directly drive memory map dispatch.

**Phase:** Phase 1 (ROM loader) and Phase 4 (MBC dispatch).

**Verification:** Pan Docs formula test: read header bytes, compute checksum, compare. Mooneye `acceptance/boot_div*` tests indirectly cover this.

---

### Pitfall M6: `dmg-acid` Requires Specific Frame Timing (59.7275 Hz, not 60)

**What goes wrong:** The Game Boy's frame rate is 59.7275 Hz (70,224 dots/frame, 4.194 MHz clock), not the round 60 Hz that monitors expect. If your PPU is cycle-accurate but your *host* loop is locked to 60 Hz, `dmg-acid` will show a single-pixel "rainbow drift" because the game logic (which uses VBlank counting for timing) sees fewer frames than the host displays. The reverse — running at exactly 60 Hz *in the emulator* without respecting the actual frame period — produces audio glitches and timing-based game logic errors.

**How to avoid:** Track host elapsed time per frame. If a frame's emulated time (16.7424 ms) is less than the host's frame budget, sleep. If it's more, drop a frame. For the *internal* emulator state, always advance 70,224 dots per frame — never "round to 60."

**Phase:** Phase 5 (Host integration / SDL2 loop).

**Verification:** Blargg `dmg-acid` (the test ROM requires cycle-accurate frame timing — wrong timing produces wrong colors, not just drift). Any timing-sensitive game (Zelda, Pokémon battle animations) will show jitter if the host loop is misaligned.

---

## Minor Pitfalls

### Pitfall m1: Cartridge Type `$00` (No MBC) Can Still Have RAM

**What goes wrong:** "ROM ONLY" cartridges (cart type `$00`, `$08`, `$09`) can have an 8 KiB RAM chip at `$A000-$BFFF` driven by a discrete-logic decoder, not an MBC. Pan Docs § "No MBC" describes this. The RAM size byte at `$0149` distinguishes: `$00` = no RAM, `$01` = "2 KiB" (unused in practice, but set by some PD homebrew), `$02` = 8 KiB, `$03` = 32 KiB, etc.

**How to avoid:** For v1, support `$00/$08/$09` cart types with optional 8 KiB/32 KiB RAM at `$A000-$BFFF`, gated by a single "RAM enable" flag at `$0000-$1FFF` (lower nibble `$A` to enable, anything else to disable — but for no-MBC, the discrete decoder doesn't gate, so allow always-on if MBC type is `$00`+RAM present).

**Phase:** Phase 4 (MBC).

**Verification:** A Tetris ROM with `$00` cart type and `$00` RAM size (no RAM). Skipped if out of scope.

---

### Pitfall m2: Joypad Read Has a Settling Delay (Multiple Reads)

**What goes wrong:** Pan Docs § "Joypad Input" notes that "most programs read from this port several times in a row (the first reads are used as a short delay, allowing the inputs to stabilize, and only the value from the last read is actually used)." The DMG's input matrix has a settling time; reading once may return bouncing contact. A naive emulator that returns the input value on the *first* read may produce wrong inputs for games that rely on the multiple-read pattern. Realistically, this is fine for almost all games because the multiple reads all return the same (correct) value in an emulator — the "settling" is a hardware artifact.

**How to avoid:** No code change needed in the emulator. Document the behavior so anyone reading the joypad code doesn't add a "read once" optimization that breaks input.

**Phase:** Phase 2 (joypad) or Phase 5 (host keyboard mapping). Mostly a documentation note.

**Verification:** None required. Game-side test: any game.

---

### Pitfall m3: Echo RAM Is an Alias, Not a Separate Buffer

**What goes wrong:** Writes to `$E000-$FDFF` are the *same* writes as to `$C000-$DDFF`. They share storage. A naive emulator that allocates separate buffers for Echo RAM will pass simple tests but fail on a "write to Echo, read from WRAM, verify same value" check. Conversely, omitting Echo RAM entirely (like some old emulators) will fail Mooneye tests that probe it.

**How to avoid:** In the bus read/write dispatch, mask the address: `(addr - 0xE000) + 0xC000` (or equivalently, `addr & 0x1FFF | 0xC000`) for the `$E000-$FDFF` range, dispatching to WRAM. No separate buffer.

**Phase:** Phase 1 (memory bus).

**Verification:** Custom unit test: write `$A5` to `$E100`, read `$C100` → must be `$A5`. Pan Docs § "Echo RAM" describes the exact mapping.

---

### Pitfall m4: Frame Timing Affects Game Logic More Than You Think

**What goes wrong:** Many DMG games count VBlanks to time animations, random number generation, and game logic. The exact 59.7275 Hz cadence matters. An emulator that runs at 60 Hz will produce slightly faster game time over a long session, and the effect compounds. Over a 30-minute session, a 60 Hz emulator runs 547 frames ahead of a 59.7275 Hz one — enough to affect RNG seeds in games like Pokémon.

**How to avoid:** Same as M6 — track elapsed host time, advance exactly 70,224 dots per emulated frame. Optionally, expose a "speed" multiplier for debugging, but default to 1× and exact frame period.

**Phase:** Phase 5 (host loop).

**Verification:** `dmg-acid` indirectly (the color cycle drifts). Pokémon speedrunners will notice in 5-minute runs.

---

## Zig-Specific Pitfalls

These are pitfalls that hit because the project is in Zig specifically. Many of them won't appear in a Rust or C++ port. They are organized by category: language semantics, memory management, C-ABI, build system, and performance.

### Zig Pitfall Z1: Integer Overflow on 8-Bit / 16-Bit CPU Operations

**What goes wrong:** Zig's default integer operators **trap on overflow in Debug and ReleaseSafe modes** and wrap in ReleaseFast/ReleaseSmall. The CPU core is *full* of operations that *should* wrap (8-bit `INC A`, 16-bit `ADD HL, BC`, etc.). A naive `var a: u8 = ...; a += 1;` will trap in Debug builds the moment a register hits `$FF`, halting the emulator under the test ROM.

**How to avoid:** Use wrapping operators throughout the CPU core: `+= %`, `-= %`, `*=%`. For explicit overflow check where needed (rare in an emulator), use `@addWithOverflow`. Or — and this is the cleaner pattern — declare a `Reg8` newtype wrapper with `usinginline` semantics that defaults to wrapping. The trade-off: you lose the safety check that the wrapping operator catches unintended wrap. For an emulator, the wrap is the *intended* behavior, so the safety is in the way.

**Phase:** Phase 1 (CPU) — establish the convention in the first commit.

**Verification:** Run all tests in Debug mode; they must not trap on intentional wraps.

**Specific gotcha:** The `Z`, `N`, `H`, `C` flags are computed via bit ops on u8, not via comparison. Use `(@as(u16, a) +% @as(u16, b)) > 0xFF` for carry, not `a + b > 0xFF` (which will trap in Debug on `a + b`).

---

### Zig Pitfall Z2: `undefined` in ReleaseFast / ReleaseSmall

**What goes wrong:** In Debug builds, Zig writes `0xAA` to `undefined` memory, which catches use-of-uninitialized-memory. In ReleaseFast/ReleaseSmall, **the safety is off**: `var x: u8 = undefined; x |= 0; return x;` returns whatever was on the stack. The emulator has a *lot* of state arrays (VRAM, OAM, WRAM, HRAM, cartridge RAM), and a struct field left as `undefined` in one path will leak through to the next emulation tick, producing **non-deterministic saves** and **non-bit-identical reproducibility** (which the PROJECT explicitly requires).

**How to avoid:**
- For all CPU state, registers, and memory arrays, use `[_]u8 = [_]u8{0} ** N` or `.initFill(0)` patterns.
- For arrays that are *intentionally* uninitialized for performance (e.g., the framebuffer in a "clear once" pattern), do the fill explicitly: `for (&framebuffer) |*p| p.* = 0;`.
- Enable the test runner's "detect memory leaks" by using `std.testing.allocator` in test paths; in the production path, the cycle-accurate state should be fully owned and zeroed at construction.
- Add a `debug_assert_eq` helper (or use `std.debug.assert`) at end-of-frame to verify state hasn't drifted.

**Phase:** Phase 1 (CPU + state). One-time decision: how is the emulator state zeroed? Document it.

**Verification:** Run a 1-minute headless test, hash the output frame, repeat. Hashes must match. Run in Debug and ReleaseFast — output must match.

---

### Zig Pitfall Z3: Allocator Discipline — Don't Allocate Per-Instruction

**What goes wrong:** Zig's idiomatic stdlib (`std.ArrayList`, `std.HashMap`, `std.json`) all take an allocator. A naive port of an emulator from a GC'd language might allocate an `ArrayList` per CPU instruction to model a stack trace, or a per-frame `StringMap` for diagnostics. At 4.19 MHz × 4 instructions/frame ≈ 17 million allocations/second, **no allocator can keep up** — including `std.heap.GeneralPurposeAllocator` (which is debug-only and serializes).

**How to avoid:**
- The Game Boy's state is *fixed-size*: 8 KiB VRAM, 8 KiB WRAM, 8 KiB external RAM, 160 B OAM, 127 B HRAM, 256 B zero-page, 32 KiB ROM bank 0, 16 KiB ROM bank N. **Use `*[N]u8` or `*[N]Reg8` (fixed-size arrays), not slices that may allocate.**
- For SDL2 host integration, allocate *once* at startup: a framebuffer `*[160 * 144]u32`, an SDL window, an SDL renderer, an SDL texture. Reuse them across frames.
- For error strings or log messages, use `std.fmt.allocPrint` *only* in error paths or once-per-N-frames logs, not per-instruction.
- Pass `std.heap.page_allocator` (or a `std.heap.GeneralPurposeAllocator` *only* in debug builds) at the top-level `main` boundary; in the core, no allocator at all.

**Phase:** Phase 1 (architectural decision). The allocator-free core is the *defining* feature of an emulator in Zig — it's how you stay under 30 MB RAM and 5 MB binary.

**Verification:** `valgrind --tool=massif` or `heaptrack` on a 60-second test. Heap should be effectively flat (no growth). Binary size: `release-fast` and `release-small` should both be < 5 MB per PROJECT.md.

---

### Zig Pitfall Z4: C-ABI for SDL2 Is Sharp-Edged

**What goes wrong:** SDL2's API is C. To call it from Zig, you need `extern "c" fn` declarations or `@cImport`. The common bugs:

- **Layout mismatch:** `SDL_Window` is an opaque type; passing a `*SDL_Window` from one call to another that expects `*SDL_Window` is fine. But a struct that *contains* an SDL struct must use `extern struct` to match C layout. Using `struct` (default Zig) will misalign.
- **Opaque types and vtables:** SDL_Renderer's function pointers require `extern fn (...) callconv(.c)` signatures; missing `callconv(.c)` produces a segfault on the first SDL call.
- **Version skew:** `SDL_video.h` and `SDL_events.h` change between SDL2 minor versions (2.0.10 vs 2.0.22 have different fields on `SDL_DisplayMode`). Pin the SDL2 version in `build.zig`.
- **Linking static vs dynamic:** For a "no runtime dependencies" target (PROJECT requirement), link SDL2 *statically*. This requires building SDL2 from source or using a static package (`libsdl2-dev` on Debian is usually dynamic-only). The `linkSystemLibrary("SDL2")` in `build.zig` will pull in the *system* lib, which is dynamic on most distros.
- **`@cImport` deprecation:** `@cImport` is deprecated in Zig 0.14+ in favor of `zig translate-c` + `@import("SDL2.zig")` generated bindings. The generated bindings are static, type-checked, and fast. Use them.

**How to avoid:**
- Use `zig translate-c` to generate `src/SDL2.zig` from the SDL2 headers once, commit the generated file, and `@import("SDL2.zig")` in your host code.
- Pin SDL2 to a specific minor version (e.g., 2.32.x as of late 2025) in `build.zig` and document it.
- For static linking, use `b.linkLibC()` and either (a) vendor SDL2 as a submodule and add as a static library in `build.zig` via `addStaticLibrary`, or (b) document the requirement for the user to provide a static SDL2 build (e.g., `-lSDL2` plus `-L/path/to/static`).
- Test the build on Linux x86_64 first; macOS ARM64 and Windows come later (per PROJECT.md).

**Phase:** Phase 5 (host integration). Establishing the C-ABI pattern once is enough; reuse it for any other C deps.

**Verification:** Strip the binary with `strip`; run on a system without SDL2 installed. If it segfaults on SDL2 symbols, the linking is wrong.

---

### Zig Pitfall Z5: `zig build` API Churn Across Versions (0.12 → 0.13 → 0.14)

**What goes wrong:** Zig's `build.zig` API and `std` library change every minor version. A `build.zig` written for Zig 0.12 will not compile with 0.13 (allocator argument renamed, `addExecutable` API changed, `installArtifactDirectory` removed). A codebase that follows "latest stable" without pinning will break on every release.

**How to avoid:**
- Pin Zig in `.zigversion` or `build.zig.zon` (Zig 0.14+ supports package metadata via `zon` files). Commit a `.tool-versions` (asdf) or `flake.nix` (Nix) for the build environment.
- When upgrading Zig, do it as a dedicated phase with its own test run, not mid-feature.
- Avoid `std.mem.*` functions that have been renamed/removed between versions; check the language reference for the current version. As of 0.14, `std.heap.GeneralPurposeAllocator` is in `std.heap`, `std.ArrayList` is in `std` (no longer `std.fifo` for `std.ArrayList`).
- Subscribe to `ziglang/zig` release notes and the `Release Notes` section in the language reference.

**Phase:** A "build bootstrap" task in Phase 1. Pin the Zig version in the very first commit.

**Verification:** Clone the repo on a clean machine, run `zig build`, get a working binary. Document the Zig version in the README.

---

### Zig Pitfall Z6: Slice Bounds Checks in the Hot Loop

**What goes wrong:** `array[i]` is bounds-checked in Debug and ReleaseSafe, even when the index is provably in range. The CPU step function is the hottest hot path — a `switch` over 256 opcodes, each with a 1-2-cycle dispatch. Bounds checks add a few % overhead.

**How to avoid:** Three options, in order of preference:
1. **Use `*[N]u8` (pointer-to-array) and index with `ptr[i]`** — Zig's optimizer elide the bounds check when the array length is comptime-known.
2. **`@ptrCast([*]u8, array.ptr) + i` and use `.*` indexing** — manual bounds-check elision. **Only safe when you've externally verified `i < N`.**
3. **Compile with `-Doptimize=ReleaseFast`** — Zig elides most bounds checks in ReleaseFast automatically, but only for the trivial cases.

**Phase:** Phase 1 (CPU). Decide the indexing convention; document it.

**Verification:** Benchmark with `zig build -Doptimize=ReleaseFast` vs Debug — the release version should be ≥ 100× faster. If the ratio is much smaller, bounds checks are not being elided; investigate with `zig build -Doptimize=ReleaseFast && objdump -d`.

---

### Zig Pitfall Z7: `comptime` for Lookup Tables Is Powerful but Can Recurse Indefinitely

**What goes wrong:** `comptime` is a powerful Zig feature that lets you build tables (opcode dispatch tables, flag calculation tables, etc.) at compile time. It also lets you write infinite loops that the compiler will catch — or *not* catch, if the termination condition is wrong. A common bug: `inline while (true) { ... }` with no `break`, which is a compile error. A subtler bug: recursive `comptime` calls that hit `@setEvalBranchQuota(N)`.

**How to avoid:**
- Use `comptime` for **stateless** tables: opcode tables, instruction timing tables, flag bit masks.
- Use runtime for **stateful** data: registers, memory, PPU state.
- If a `comptime` call recurses beyond 1,000 branches, add `@setEvalBranchQuota(N)` *with a comment explaining why*. Don't blindly set it to 1,000,000.
- Test the build with `zig build-exe` (no `zig build`) to see only compile errors, not link errors.

**Phase:** Phase 1 (CPU decode table) and Phase 3 (PPU mode table). One-time decisions.

**Verification:** Compile times. If `zig build` takes > 30 seconds, look for a runaway `comptime` loop.

---

### Zig Pitfall Z8: Big-Endian Cartridge Header in a Little-Endian World

**What goes wrong:** The Game Boy cartridge header has some 16-bit values stored big-endian (notably the global checksum at `$014E-$014F` and the new licensee code at `$0144-$0145`). The CPU core is little-endian. A naive `@intCast(u16, header[0x14F]) | (@intCast(u16, header[0x14E]) << 8)` may swap, depending on how the byte is read.

**How to avoid:** Use `std.mem.readInt(u16, header[0x14E..][0..2], .big)` for big-endian reads. Document the two big-endian fields in the header parser.

**Phase:** Phase 1 (ROM loader).

**Verification:** Manual inspection of a few headers (use a tool like `xxd`) to confirm.

---

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| **Skip the boot ROM, hardcode post-boot state.** | Avoids needing a copyrighted boot ROM dump; faster test runs. | Game expects real boot ROM state → must match exactly. Blargg's `dmg-acid` boot section may misbehave. | **Always for v1** — this is the standard approach. Document the choice. |
| **Implement MBC3 without RTC latch.** | Simpler code. | MBC3 with RTC carts (Pokémon G/S/C) misbehave. | Acceptable for v1 if no RTC carts are targets. Add a "MBC3 RTC" milestone. |
| **Single-step the CPU at one M-cycle = one host cycle.** | Simple loop. | Performance: 4.19 MHz ≈ ~5 million M-cycles/sec, achievable but not free. | Fine for v1. Optimize with batching in a later phase. |
| **Use `std.heap.GeneralPurposeAllocator` everywhere.** | Safety. | Slow (serialized, debug-only). | **Only in test builds.** Production uses `std.heap.page_allocator` or no allocator. |
| **Implement PPU as "render to a 160×144 buffer at VBlank."** | Easy, passes `dmg-acid` eventually. | Mid-frame tile updates, mid-frame STAT IRQ, mode 3 bus blocking — all break. | **Never.** Always implement the scanline model. |
| **OAM DMA = 160-cycle busy-wait without HRAM check.** | One-line implementation. | DMG OAM DMA bus conflicts go unmodeled; `oam_dma/sources` test fails. | **Only if you explicitly mark it as a known divergence.** |
| **Treat all invalid opcodes as `unreachable`.** | Clean decode table. | A corrupted save file that hits `$D3` traps instead of locking. | **Only if you accept the trap. The hardware locks, so emulate that.** |
| **Implement `stop` as a no-op + 1-byte advance.** | Simple. | Real `stop` behavior is a state machine; homebrew using `stop` fails. | **Always for v1** — no licensed DMG game uses `stop` outside CGB speed-switch. |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| **Per-instruction dispatch via `switch (opcode)`.** | Slower than 100% speed on a Raspberry Pi 4. | Build a 256-entry jump table with `comptime`; use `inline for` over an `Opcode` enum. | Single-CPU host slower than 1 GHz. |
| **Naive frame-by-frame PPU at VBlank only.** | Passes `dmg-acid` but breaks mid-frame games. | Scanline-by-scanline, with mode 3 dot accounting. | Any game with mid-frame tile updates. |
| **Unbounded allocations in `std.fmt.allocPrint`.** | Memory grows; OOM on long sessions. | Use stack-allocated buffers (`std.fmt.bufPrint`) for fixed-size formatting. | Sessions longer than 1 hour. |
| **No `inline for` over 256 opcodes — manual `switch` chain.** | Compiles, but the compiler doesn't auto-vectorize the dispatch. | `comptime { var table: [256]OpFn = undefined; for (0..256) |i| table[i] = decode(i); }` and call `table[opcode]`. | Any host slower than 500 MHz. |
| **No frame pacing — emulator runs as fast as possible.** | Battery drain on laptops; audio (when added) glitches. | `std.time.sleep` to target 59.7275 Hz. | On battery-powered hosts. |
| **Reading from `*u8` pointers with no caching hint.** | Cold cache misses on each PPU access. | Pre-cache the framebuffer in a register-allocated local. | Hosts with slow RAM (Raspberry Pi, mobile). |
| **OAM read on every mode 2 M-cycle instead of once per line.** | Wasted memory bandwidth. | Read OAM once at the start of mode 2; only re-read on OAM DMA. | Hosts with low memory bandwidth. |

---

## Security Mistakes (Domain-Specific)

Game Boy emulators are not security-sensitive in the traditional sense, but there are domain-specific issues:

| Mistake | Risk | Prevention |
|---------|------|------------|
| **Parse untrusted ROMs without size or header validation.** | A malformed ROM could pass a 4 GB file to the loader and OOM, or cause an out-of-bounds read on the header. | Validate file size (32 KiB–8 MiB, depending on MBC type), validate header is at the expected offset, validate MBC type is a known code (`$00`-`$03`, `$05`-`$06`, `$08`-`$09`, `$0F`-`$13`, `$19`-`$1E`, others = warn or refuse). |
| **Load `.sav` files without length or version checks.** | A save file from a different game (or a malicious file) could read or write past the expected 8 KiB / 32 KiB. | Match `.sav` to ROM by header hash; clamp `.sav` size to the expected RAM size; never read past `expected_sav_size`. |
| **Execute user-provided boot ROM without validation.** | A boot ROM is 256 bytes; a wrong-size file could trigger buffer overflow. | Validate boot ROM size is exactly 256 bytes for DMG/MGB; 256 / 2048 for SGB/CGB. |
| **Tie save format to internal struct layout.** | A future code change breaks all user saves. | Use a versioned save format (1-byte magic + 1-byte version + payload) and migrate. |
| **Run `stop` or `halt` in a tight loop with no timeout.** | A corrupted ROM (or a real hardware lockup scenario) hangs the emulator forever. | Add a configurable M-cycle budget per tick; bail with an error after N M-cycles. |

---

## UX Pitfalls

For the *user-facing* part of the emulator (CLI, save states, ROM selection).

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| **No ROM drag-and-drop or simple CLI.** | User has to type `./zigboy path/to/rom.gb` — fine, but error messages are unclear if the file is wrong. | Clear error messages: "Not a valid Game Boy ROM: missing header at $0100" or "Unsupported mapper: MBC6 (use a different ROM)." |
| **No save state support in v1.** | Save state is the #1 feature request for emulators. | Defer to v2; document. |
| **Default window size is too small / too large.** | Window may not be resizable, or default to a tiny size that's hard to see. | Default 4× integer scale (640×576) and allow window resize; document any fullscreen toggle. |
| **Audio out of scope but no warning.** | User plugs in headphones, hears nothing, thinks the emulator is broken. | Show "Audio not yet supported" in the help text or a startup banner. |
| **Battery save location is hard to find.** | User can't find their `.sav` file to back it up. | Default to the same directory as the ROM (`<romname>.gb` → `<romname>.sav`); document. |

---

## "Looks Done But Isn't" Checklist

Things that pass `dmg-acid` and a quick smoke test but are missing critical pieces.

- [ ] **MBC1 (large ROM, mode 1):** Often missing — verify with Mooneye `mbc1/rom_1Mb` and `mbc1/rom_2Mb`.
- [ ] **MBC3 RTC latch:** Implemented but doesn't actually latch — verify by writing `$00, $01` and reading a register twice; values should be the same.
- [ ] **MBC5 rumble bit:** Often forgotten — bit 3 of the RAM bank register on cart type `$1C-$1E` controls rumble, not RAM. Verify by writing `$08` to `$4000-$5FFF`; the next read of `$A000-$BFFF` should not be from a different RAM bank.
- [ ] **MBC1 00→01 bank translation:** Verify by writing `$00` to `$2000-$3FFF` and reading `$4000-$7FFF` — should be bank 1, not bank 0.
- [ ] **Cartridge header checksum:** Verify by computing on a real ROM header (e.g., Tetris) — must equal `$XX` at `$014D`.
- [ ] **`dmg-acid` second-screen colors:** The 12 color squares test frame timing. Wrong cadence = wrong colors (not just drift).
- [ ] **Boot ROM state in "no boot ROM" mode:** Verify `A == $01, B == $00, C == $13, ...` at the start of execution. Use Mooneye `boot_regs-dmgABC`.
- [ ] **Echo RAM:** Write `$A5` to `$E100`, read `$C100` — must be `$A5`.
- [ ] **Echo RAM does NOT map to external RAM:** A common bug is to alias Echo to cart RAM. They are separate.
- [ ] **Joypad register reads $F when neither row is selected:** Writing `$30` to `$FF00` should yield `$3F` on read (P15:P14 = 11, low nibble = 1111).
- [ ] **Interrupt priorities:** If multiple IF bits are set, VBlank fires first. Test by setting all 5 bits, then executing `ei` — the handler called should be `$40`.
- [ ] **`ei` delay:** `ei; di` does *not* enable interrupts. Test by executing `ei; di` with VBlank pending; no interrupt should be taken.
- [ ] **HALT bug:** `ei; halt` with IME=0 and an interrupt pending — PC should re-execute the `halt`. Test with Mooneye `halt_ime0_ei`.
- [ ] **Open-bus on missing cart:** Boot with no cart — should show the boot ROM's `$FF`-filled logo (correct), not a black screen or crash.
- [ ] **SCX % 8 mid-scanline:** Writes to SCX at the start of a scanline take effect for that scanline; writes after the first 12 dots affect the rest of the scanline but not the current tile fetch. Often missed.
- [ ] **LY register value during VBlank:** LY reads 144, 145, ..., 153, then 0. Some games check the transition.

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| **Timer subtle bug discovered late** | MEDIUM | Refactor the timer state to a `SystemCounter` struct; add unit tests for each Mooneye `timer` case; the rest of the emulator is unaffected because only the timer reads the system counter. |
| **HALT bug missing** | LOW | Add a `halt_bug_pending: bool` flag in the CPU state; gate PC increment on it during the post-HALT instruction. Tests: Mooneye `halt_ime0_ei`. |
| **MBC1 mode 1 wiring wrong** | MEDIUM-HIGH | Refactor MBC1 to a tagged union of (small, large, MBC1M); re-test the Mooneye `mbc1/` suite. No other MBCs are affected. |
| **PPU bus blocking wrong** | HIGH | The PPU is the most timing-sensitive part. Add a `mode3_remaining: u16` counter that decrements per M-cycle; gate VRAM/OAM access on mode. Tests: Mooneye `ppu/` suite. |
| **Open-bus read returns `$FF` always** | LOW | Add a `data_bus: u8` field to the CPU; update on every bus-driving event; return on open-bus reads. Tests: Mooneye `bits/`. |
| **Allocator used in hot loop** | MEDIUM | Refactor to fixed-size arrays. Validate with `valgrind --tool=massif`. |
| **Integer overflow traps in Debug** | LOW | Add `+%`, `-%`, `*%` to CPU ops; or use a wrapper type. Re-run all tests in Debug. |
| **C-ABI mismatch with SDL2** | LOW | Regenerate bindings with `zig translate-c`; verify the SDL call sequence works. |
| **`.sav` format change breaks user saves** | MEDIUM | Add a version byte; write a migration for v1 → v2. Document. |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Invalid opcodes lock CPU forever (P10) | **Phase 1: CPU + memory** | Custom unit test + manual "hang bailout" timer |
| Integer overflow traps in Debug (Z1) | **Phase 1: CPU** | Run all tests in Debug mode |
| `undefined` leaks in release (Z2) | **Phase 1: CPU + state** | Bit-identical output across Debug and ReleaseFast |
| Allocator discipline (Z3) | **Phase 1: architecture** | `valgrind massif` flat heap, < 5 MB binary |
| Slice bounds checks in hot loop (Z6) | **Phase 1: CPU** | `zig build -Doptimize=ReleaseFast` benchmarks |
| `comptime` recursion (Z7) | **Phase 1: CPU decode table** | Clean compile, no quota warnings |
| Big-endian header fields (Z8) | **Phase 1: ROM loader** | Manual header inspection |
| `stop` as no-op (M2) | **Phase 1: CPU** | `stop` doesn't trap |
| Boot register state (M3) | **Phase 1: ROM loader** | Mooneye `boot_regs-dmgABC`, `boot_hwio-dmgABCmgb` |
| Cartridge header checksum (M5) | **Phase 1: ROM loader + Phase 4: MBC** | Compute on real ROM, compare |
| Echo RAM aliasing (m3) | **Phase 1: memory bus** | Write to `$E100`, read `$C100` |
| Open-bus / unused register bits (P9) | **Phase 1: CPU + bus, Phase 3: PPU bus** | Mooneye `bits/` suite |
| `ei` delay + HALT bug + ISR priority (P2) | **Phase 1: CPU, Phase 2: interrupts** | Mooneye `ei_*`, `halt_ime0_ei`, `intr_timing` |
| ISR timing = 5 M-cycles (M1) | **Phase 1: CPU cycle counting, Phase 2: interrupt wiring** | Mooneye `intr_timing`, Blargg `instr_timing` |
| Timer falling-edge detector (P1) | **Phase 2: timer** | Mooneye `timer/` full suite |
| Joypad multiple-read pattern (m2) | **Phase 2: joypad** | Document only |
| PPU mode-based bus blocking (P3) | **Phase 3: PPU** | Mooneye `ppu/vblank_stat_intr`, `ppu/intr_2_mode3_timing` |
| OAM DMA bus conflicts (P4) | **Phase 3: PPU / OAM DMA** | Mooneye `oam_dma/` full suite |
| OAM corruption bug (P5) | **Phase 3: PPU / OAM (deferred)** | Blargg `oam_bug-2` (negative) |
| Spurious STAT interrupt (P8) | **Phase 3: PPU (deferred)** | Manual: *Road Rash*, *Xerd no Densetsu* |
| SCX mid-scanline desync (M4) | **Phase 3: PPU (deferred)** | None — visual observation |
| MBC1 00→01 + mode 1 (P6) | **Phase 4: MBC** | Mooneye `emulator-only/mbc1/` full suite |
| MBC3 RTC latch (P7) | **Phase 4: MBC (deferred)** | Skipped in v1; flagged for v2 |
| No-MBC cart with RAM (m1) | **Phase 4: MBC** | Tetris ROM (cart type `$00`) |
| `zig build` API churn (Z5) | **Phase 1: build bootstrap** | Pin Zig in `.zigversion` / `build.zig.zon` |
| C-ABI for SDL2 (Z4) | **Phase 5: SDL2 host** | Strip binary, run on SDL2-less system |
| Frame pacing (M6, m4) | **Phase 5: SDL2 host loop** | Blargg `dmg-acid`; `dmg-acid` second-screen colors |
| `dmg-acid` frame timing (M6) | **Phase 5: SDL2 host loop** | Blargg `dmg-acid` passes |
| Battery save format versioning (Security) | **Phase 4: persistence, Phase 5: CLI** | Custom save-migration test |

---

## Sources

- **Pan Docs (gbdev):** https://gbdev.io/pandocs/ — primary reference for the SM83 CPU, PPU, timer, MBCs, and bus behavior. Multiple sections cited: *Timer Obscure Behaviour*, *Interrupts*, *HALT*, *MBC1/3/5*, *Memory Map*, *Accessing VRAM and OAM*, *OAM DMA Transfer*, *OAM Corruption Bug*, *STAT*, *Power_Up_Sequence*, *The Cartridge Header*, *Rendering*. Confidence: HIGH (primary source, version dated 2026-06-09).
- **Gekkio's Game Boy: Complete Technical Reference:** https://gekkio.fi/files/gb-docs/gbctr.pdf — cited by Pan Docs as the recommended emulator developer reference.
- **Mooneye GB test suite README (Gekkio):** https://github.com/Gekkio/mooneye-gb — explicit list of which tests pass on a reference DMG emulator, used to map each pitfall to a verification test. Confidence: HIGH.
- **Mooneye Test Suite (separate repo):** https://github.com/Gekkio/mooneye-test-suite — actual test ROMs.
- **SameSuite (LIJI32 / SameBoy author):** https://github.com/LIJI32/SameSuite — additional test ROMs, especially for interrupt and OAM DMA timing.
- **nitro2k01/little-things-gb:** https://github.com/nitro2k01/little-things-gb — research ROMs for the halt-cancel double-halt quirk and the window-glitch quirk (Star Trek 25th Anniversary).
- **Blargg's test ROMs:** referenced via the Mooneye README and the original gbdev test ROM collections. Specifically: `cpu_instrs`, `dmg-acid`, `instr_timing`, `mem_timing-2`, `oam_bug-2`.
- **Zig 0.14.0 Language Reference:** https://ziglang.org/documentation/0.14.0/ — cited for `comptime`, `undefined`, illegal behavior (overflow, bounds checks, alignment), allocator patterns, and the `extern struct` ABI. Confidence: HIGH for stable features; MEDIUM for "this is the idiomatic way" claims.
- **Zig issue tracker:** https://github.com/ziglang/zig/issues — checked 0.14 / allocator-related breaking changes; no specific issues cited here, but a recurring theme is the deprecation of `@cImport` in favor of `zig translate-c`.
- **Existing Zig GB emulators (inspiration, not direct comparison):** `MasterQ32/ZigBoy` (404 at search time but referenced in some community lists), `iczelia/gb-zig` (404 at search time), `rockytriton/ll` (404 at search time). Zig GB emulator space is sparse, which is *itself* a signal: getting it right is hard.

### Unverified / LOW confidence items (flagged in body)

- **Zig idiom claims** (e.g., "Zig elides bounds checks in ReleaseFast for trivial cases"): confirmed in the language reference but the exact optimizer behavior may shift between Zig versions. Re-verify on each Zig upgrade.
- **SDL2 static linking on Linux:** the practical reality is that most distros ship dynamic-only `libsdl2-dev`. The "static link SDL2" path may require building SDL2 from source via a build script in `build.zig`. The complexity is flagged but the exact build integration was not verified end-to-end.
- **OAM corruption and STAT spurious interrupt** emulation details: only SameBoy and BGB correctly emulate these. The reference behavior is documented but the exact bug-emulation code is not in Pan Docs; only BGB and SameBoy source could confirm, which was not consulted here.

### Gaps (could not resolve in this research)

- **A confirmed-working Zig GB emulator codebase** to reference for idioms. None was findable at the time of research; the closest is the Mooneye GB Rust emulator. Confidence in "this is the right Zig pattern" is therefore MEDIUM.
- **SDL2 minor version pinning for cross-platform support.** Zig 0.14 + SDL2 2.32 on macOS/Windows specific gotchas were not exhaustively tested.

---

*Pitfalls research for: ZigBoy — DMG Game Boy emulator in Zig*
*Researched: 2026-06-18*
