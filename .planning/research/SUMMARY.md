# ZigBoy — Research Summary

**Project:** ZigBoy — hyper-fast, super-lightweight Game Boy (DMG) emulator in Zig
**Domain:** Console emulator (DMG-01, 8-bit Sharp LR35902 @ 4.194 MHz)
**Researched:** 2026-06-18
**Overall confidence:** **HIGH** (Pan Docs, SameBoy, Mooneye, Blargg, mattneel/zgbc, castholm/SDL all verified)

> **Notation note (SDL2 → SDL3).** PROJECT.md, ARCHITECTURE.md, and PITFALLS.md
> were written before STACK.md research was completed and use "SDL2" throughout.
> STACK.md (the most recent, most authoritative research) recommends **SDL3 via
> `castholm/SDL`** (the modern Zig 0.16 idiom; static + strip + LTO; first-class
> `zig fetch` support). This summary standardizes on **SDL3**. ARCHITECTURE.md's
> `src/sdl.zig` / `@cImport` patterns still apply but use `addTranslateC` and
> the `castholm/SDL` package. See "Open Questions" — confirm before locking
> requirements.

---

## Executive Summary

ZigBoy is a **DMG-only, cycle-accurate, statically-linked, < 5 MB Game Boy emulator** in Zig 0.16. The product category is mature: 25+ years of reference implementations (SameBoy, BGB, Gambatte, Mooneye, mattneel/zgbc) and a stable correctness test surface (Blargg, Mooneye, dmg-acid2) define what "complete" means. The recommended path is a **vertical MVP slice** that ships a playable Tetris/Mario window in 4 coarse phases, anchored on `mattneel/zgbc`'s architecture and the canonical CPU-bus-peripheral dispatch model.

The **recommended approach** is: (1) **Zig 0.16.0 + SDL3 via `castholm/SDL` + `b.addTranslateC`** (replaces deprecated `@cImport`), built `ReleaseFast` + `strip` + `lto=.full` for `x86_64-linux-musl` to produce a single static binary; (2) **bus-centered cycle accounting** — every `read8`/`write8` advances a single T-cycle counter fanned out to all peripherals (Ryp's pattern); (3) **MVC-folded component layout** (`cpu/`, `ppu/`, `cartridge/`, plus flat `bus.zig`/`timer.zig`/`joypad.zig`/`mmio.zig`); (4) **`packed struct` register file + 256-byte MMIO** with `comptime` offset asserts, plus **`comptime` 256-entry opcode decode table**; (5) **no allocator in the hot path**; everything pre-allocated in `Emulator.init`.

**Key risks** (in priority order): (a) the **LR35902's non-obvious quirks** — HALT-bug, `ei` delay, interrupt priority, timer falling-edge detector, MBC1 00→01 bank translation, PPU mode-3 VRAM/OAM bus blocking — are *load-bearing* for many commercial games and only caught by Mooneye/`dmg-acid`, not by naive `cpu_instrs`; (b) **Zig `undefined` in ReleaseFast** breaks the PROJECT.md determinism guarantee if any subsystem state is left uninitialized; (c) **per-instruction allocations** in a 4.19 MHz hot path will crater perf and inflate binary size; (d) `@cImport` is deprecated and SDL2 Zig bindings are a mess — use SDL3 via the official `castholm/SDL` + `b.addTranslateC`; (e) **frame period is 59.7275 Hz, not 60 Hz** — locking to 60 Hz drifts `dmg-acid` colors and Pokémon RNG.

---

## Key Findings

### Recommended Stack *(see STACK.md for full detail)*

The concrete picks — short, opinionated, ready to lock:

- **Zig 0.16.0 (stable)** — latest stable; bundles LLVM 21, musl 1.2.5, glibc 2.43; `std.Io` refactor; `b.addTranslateC`; lock-free `ArenaAllocator`. Do not chase 0.17-dev.
- **SDL3 via `castholm/SDL` v0.5.1 (SDL 3.4.10)** — first-class `zig fetch` package, `preferred_linkage=.static` + `strip` + `lto=.full`, cross-platform (Linux/macOS/Windows). Replaces SDL2-era stack.
- **`b.addTranslateC` via the official `ziglang/translate-c` package** — replaces deprecated `@cImport`; generates a Zig module from SDL3 C headers, static and type-checked.
- **Build: `ReleaseFast` + `strip` + `lto=.full` for `x86_64-linux-musl`** — single static binary, zero runtime deps, well under 5 MB. `Debug` for dev iteration, `ReleaseSafe` for CI test runs.
- **Zig stdlib only** — `std.fs.File`, `std.Io.File`, `std.heap.GeneralPurposeAllocator` (debug) / `std.heap.page_allocator` (release), `std.mem.asBytes`, `std.ArrayList` unmanaged. No third-party deps beyond SDL3.
- **Reference: `mattneel/zgbc`** — pure-Zig core, ~3,500 LOC, full Blargg pass; mirror its flat `src/` layout and `comptime` opcode tables.

Explicitly **NOT** used: `@cImport` (deprecated in 0.16, removed in 0.17), Raylib (cross-platform pain), miniaudio (redundant with SDL3 audio), dynamic-linked SDL, C++ deps, Make/CMake, `git submodule` for vendoring (use `zig fetch`).

### Table-Stakes Features (v1 must-haves) *(see FEATURES.md)*

These are the P1 set from FEATURES.md — every one is required for the emulator to be called "a Game Boy emulator" in 2026:

1. **ROM header parser** (`$0100–$014F`) → mapper type + ROM/RAM size dispatch
2. **Sharp LR35902 CPU core** with **M-cycle accurate timing** + 1-byte prefetch
3. **Memory bus** with full address map (ROM/VRAM/WRAM/HRAM/OAM/MMIO/Echo RAM)
4. **PPU**: BG + Window + Sprites + OAM DMA + **mode-based STAT timing** (modes 0–3)
5. **Timer/divider** (DIV/TIMA/TMA/TAC) with **falling-edge detection** (not naive counter)
6. **Joypad input** (P1 register + 8 buttons via SDL3 keyboard mapping)
7. **MBC1 / MBC2 / MBC3 / MBC5 + ROM-ONLY** mappers (covers ~99% of DMG library)
8. **Battery-backed `.sav` persistence** (load on init, save on exit)
9. **Desktop window via SDL3** with `~59.7275 Hz` frame pacing, integer nearest-neighbor scaling
10. **Keyboard → joypad mapping** (sane defaults: arrows = D-pad, Z/X/A/Enter/Space = A/B/Start/Select)
11. **Pass Blargg `cpu_instrs` + `dmg-acid2`** — hard accuracy gate per PROJECT.md
12. **Single static binary, < 5 MB, no runtime deps** — PROJECT.md hard constraint
13. **Deterministic per-frame output** — same ROM + input → bit-identical frame N

### Differentiators (v1.x — after v1 is stable)

BESS 1.0 save states, MGB/DMG-0 model selection, boot ROM support (legal status TBD), DMG palette selection, runtime stats overlay (FPS), Mooneye test suite pass, macOS ARM64 + Windows builds, CLI flags (`--info`, `--headless`, `--palette=`). See FEATURES.md "Add After Validation" list.

### Deferred (v2+) — do not build

CGB, SGB, APU (defer to v1.x per PROJECT.md), Link Cable / Printer / Camera / Infrared, debugger UI (separate tool), TAS/movie recording, rewind, WASM/mobile, cheat UI, frame blending, networking, MBC6/7/HuC1/3/Camera/TAMA5. See FEATURES.md "Anti-Features" for rationale.

### Architecture Approach *(see ARCHITECTURE.md)*

A DMG emulator is a **deterministic, cycle-stepped state machine**. The **bus is the central abstraction**, not the CPU — every `read8`/`write8` is an M-cycle event that ticks timer, PPU, DMA, and joypad in lockstep. Reference: SameBoy's `GB_cpu_run`, Mooneye's `CpuContext::read_cycle`, Ryp's `consume_pending_cycles`.

**Major components** (mirror `mattneel/zgbc` layout; see ARCHITECTURE.md §3):

1. **`emulator.zig`** — top-level `Emulator` struct owns all state; public API: `init`, `deinit`, `step`, `run_frame`, `framebuffer`, `key_down`, `key_up`
2. **`cpu/`** — `Cpu` + `Registers` (`packed struct`, 12 bytes) + `FlagRegister` (`packed struct`, 1 byte) + `Instruction` tagged union + `comptime` 256-entry main + 256-entry CB-prefixed decode tables
3. **`bus.zig`** — `read8`/`write8` dispatch by `addr >> 12`; **the single chokepoint for cycle counting**; tick timer/ppu/dma/joypad on every access
4. **`mmio.zig`** — `packed struct MMIO` of the 256 bytes at `$FF00–$FFFF`, with `comptime assert(@offsetOf(MMIO, ...) == 0xNN)` for every named register
5. **`ppu/`** — mode 0/1/2/3 state machine on 456 dots/scanline × 154 scanlines/frame; owns VRAM (8 KiB) + OAM (160 B) + 160×144 framebuffer
6. **`timer.zig`** — 16-bit internal `div` counter incremented every M-cycle; `tima` increments on **falling edge** of TAC-selected bit of `div`; `tima` overflow fires IRQ one M-cycle later
7. **`cartridge/`** — tagged union over `RomOnly`, `Mbc1`, `Mbc3`, `Mbc5`; header parser; `.sav` load/save
8. **`main.zig` + `frontend.zig`** — arg parsing, ROM load, SDL3 init (window + renderer + texture + events), 59.7275 Hz frame loop

**Memory map dispatch** is a `switch (addr >> 12)` (monomorphized to a jump table, faster than SameBoy's `read_map[16]`). **All buffers are `*[N]u8` pre-allocated in `Emulator.init` — no allocator in the hot path.**

### Critical Pitfalls (the 5 to defuse in the roadmap) *(see PITFALLS.md)*

These are game-breaking if missed, not nitpicks. Each is tied to a specific phase.

1. **Timer is a falling-edge detector, not a naive counter** *(PITFALLS §1, Phase: Timer)* — TIMA fires on the *falling edge* of a TAC-selected bit of a 16-bit system counter. Writing to DIV can fire an extra tick; the overflow `tima = tma` happens **one M-cycle later**, not synchronously. Without Mooneye `timer/` tests, audio (when added) and DIV-as-RNG games will misbehave.
2. **HALT-bug + `ei` delay + interrupt priority** *(PITFALLS §2, Phase: CPU + Interrupts)* — `ei` takes effect one instruction later (`ei; di` ≠ enable); IME=0 + `(IE & IF) != 0` + HALT = re-execute the byte after HALT; VBlank (bit 0) is serviced first, descending. Missing any causes boot loops and broken `ei; halt` VBlank waiters.
3. **PPU mode-3 VRAM/OAM bus blocking** *(PITFALLS §3, Phase: PPU)* — during mode 3 the CPU cannot read/write VRAM/OAM; reads return open-bus (typically `$FF`, *not guaranteed*); window length is 172–289 dots depending on SCX%8 + window penalty + OBJ penalties. Most action games update tiles mid-frame.
4. **MBC1 00→01 bank translation + mode 1 wiring** *(PITFALLS §6, Phase: MBC)* — writing `$00` to `$2000–$3FFF` maps bank 1, not bank 0; on 1 MiB+ ROM, the 2-bit secondary register wires to upper ROM bank bits in mode 1, not RAM. Without Mooneye `mbc1/rom_*` and `mbc1/multicart_rom_8Mb`, larger MBC1 games brick.
5. **Zig-specific: `undefined` in ReleaseFast breaks determinism** *(PITFALLS Z2 + Z3, Phase: CPU+state init)* — Debug zeros `undefined` to `0xAA`, ReleaseFast returns stack garbage. Any subsystem state left uninitialized leaks through to later ticks and **breaks the bit-identical-determinism requirement**. All state arrays must be `[_]u8{0} ** N` or explicitly filled. Also: **no allocator in the hot path** — a 4.19 MHz CPU doing 50K+ instr/frame × 60 fps will trip every Zig stdlib container if ported naively.

Other pitfalls worth noting but lower priority: OAM DMA bus conflicts on DMG (PITFALLS §4, Phase PPU), invalid opcodes lock CPU forever — never `unreachable` them (PITFALLS §10, Phase CPU), open-bus reads (PITFALLS §9, Phase CPU+bus), 59.7275 Hz cadence (PITFALLS M6, Phase frontend), MBC3 RTC latch sequence (deferred, PITFALLS §7).

---

## Implications for Roadmap

The system is deeply interconnected (CPU ↔ bus ↔ peripherals); a **vertical MVP slice** is the only sensible order. A pure horizontal phase (CPU-only, then PPU-only) cannot be tested until the bus is wired. The recommended 4-phase structure matches ARCHITECTURE.md §6 and is consistent with PITFALLS.md's per-pitfall "Phase to address" tags.

### Recommended Phase Order (vertical slices)

> **Each phase ships a demonstrable artifact** (test ROM passing, or a window displaying something).

#### **Phase 1 — Build skeleton + CPU + Bus + ROM-only cart (vertical slice)**

- **Rationale:** The maximum-feedback loop. You cannot test any subsystem without a working CPU+bus; this is the canonical "Hello ROM" slice (Blargg's `cpu_instrs.gb` is ROM-only).
- **Delivers:** `build.zig` skeleton with `castholm/SDL` + `b.addTranslateC`; `Emulator` struct; LR35902 CPU core with M-cycle timing + 1-byte prefetch; full `Bus.read8/write8` dispatch; ROM-only cart loader; SDL3 window opening.
- **Addresses:** ROM header parser, CPU core, Memory bus, SDL3 desktop window, Keyboard mapping, Static binary (initial), Blargg `cpu_instrs` pass.
- **Stack used:** Zig 0.16, SDL3, `std.fs` for ROM load, `packed struct` register file + MMIO, `comptime` opcode tables.
- **Defuses:** Pitfall Z1 (use `+%` wrapping throughout), Z2 (zero all state at `init`), Z3 (no allocator in hot path), Z6 (comptr-known array sizes), §10 (invalid opcodes = spin, not `unreachable`), §9 (open-bus reads, F register low nibble), M2 (`stop` = no-op + 2-byte PC advance), M3 (set post-boot state), m3 (Echo RAM as alias), m1 (no-MBC cart with RAM), Z8 (big-endian header reads).
- **Research flag:** ✅ Standard patterns (mattneel/zgbc, Ryp, Mooneye) — skip `--research-phase`.

#### **Phase 2 — Timer + Interrupts + Joypad + MBCs + battery save**

- **Rationale:** Without timer + interrupts, almost every game hangs. Adding MBCs in the same phase keeps "play most of the library" as a single demonstrable milestone (e.g., play Super Mario Land end-to-end with a working save).
- **Delivers:** `Timer` with falling-edge detection; `IF`/`IE`/`IME`; interrupt dispatch (5 M-cycles, VBlank-priority); HALT-bug; `Joypad` + `P1`; MBC1 (with 00→01 + mode 1), MBC2, MBC3 (no RTC), MBC5; `.sav` load/save.
- **Addresses:** Timer/divider, Joypad input, MBC1/MBC2/MBC3/MBC5, Battery save, Blargg `instr_timing` + Mooneye `timer/` + Mooneye `interrupt/` passes.
- **Architecture:** wire bus tick to call `timer.tick(4)` and `joypad.tick(4)` on every `read8`/`write8`.
- **Defuses:** Pitfall §1 (timer falling edge — most important in this phase), §2 (HALT-bug + `ei` delay), §6 (MBC1 00→01 + mode 1), §7 (MBC3 — skip RTC), M1 (ISR = 5 M-cycles), m1 (no-MBC cart with RAM).
- **Research flag:** ⚠️ MBC1 mode 1 + MBC5 9-bit bank register + MBC3 RTC latch (deferred) are subtle — recommend **light research-phase** to confirm register-write edge cases against Pan Docs + SameBoy.

#### **Phase 3 — PPU (modes + BG + Window + Sprites + OAM DMA) + SDL3 rendering + frame pacing**

- **Rationale:** Visuals are the user-visible payoff. Splitting PPU from CPU/bus is impossible (PPU reads VRAM via the bus on every cycle), so the bus model from Phase 1/2 must be cycle-accurate enough. The mode-3 bus blocking + STAT interrupts are the trickiest correctness work.
- **Delivers:** PPU mode 0/1/2/3 state machine on 456 dots × 154 scanlines; VBlank IRQ; LY/LYC; BG tile fetch + SCX/SCY scrolling; Window rendering; Sprite fetch (8×8/8×16, priority, X/Y flip, OBP0/OBP1); OAM DMA (160-M-cycle, with DMG HRAM-only bus lock); SDL3 texture streaming; 59.7275 Hz frame pacing.
- **Addresses:** PPU, OAM DMA, Frame pacing, Render to window, **`dmg-acid2` pass**, Mooneye `ppu/*` + `oam_dma/*` passes.
- **Defuses:** Pitfall §3 (PPU mode-3 bus blocking — the headline PPU pitfall), §4 (OAM DMA HRAM-only bus lock on DMG), §8 (spurious STAT IRQ — mark as deferred, document as known divergence), M4 (SCX mid-scanline — defer, document), M6 + m4 (59.7275 Hz cadence, not 60 Hz).
- **Research flag:** ⚠️ PPU mode-3 dot accounting + SCX%8 + window penalty math is the densest hardware-correction work in the project — **research-phase strongly recommended** with focus on SameBoy `display.c` + mattcurrie/dmg-acid2 reference image. Also reconfirm Open Questions §3 (frame period pacing).

#### **Phase 4 — Polish, accuracy gates, BESS save states, model selection, cross-platform**

- **Rationale:** v1 is feature-complete after Phase 3. This phase ships the v1 quality bar: full Blargg + Mooneye pass, BESS 1.0 save state compatibility (free interop with SameBoy/BGB), MGB model selection, headless test runner for CI, macOS ARM64 + Windows builds, README + CONTRIBUTING, CI.
- **Delivers:** BESS 1.0 save state footer; `zigboy-core` library + `zigboy-cli` binary split (headless mode); MGB/DMG-0 model option; boot ROM support (conditional on Open Question §1); CLI flags (`--info`, `--headless`, `--palette=`, `--model=`); runtime stats overlay; `zig build test` fetches Blargg/Mooneye; macOS ARM64 + Windows cross-compile via `castholm/SDL`; GitHub Actions CI.
- **Addresses:** Static binary < 5 MB (final size budget check), Determinism (frame-hash test in CI), BESS save state, Model selection, Boot ROM, CLI flags, Cross-platform.
- **Defuses:** §5 (OAM corruption bug — defer or mark expected-fail), §8 (spurious STAT IRQ — defer), Pitfall M5 (header checksum validation), security mistakes (ROM size validation, .sav length check, versioned save format).
- **Research flag:** ⚠️ BESS 1.0 footer format (LIJI32/SameBoy `BESS.md`) and cross-compile toolchain for macOS from Linux (Apple SLA forbids; needs Mac builder) — **light research-phase** for both.

### Phase Ordering Rationale

- **Why vertical slices, not horizontal layers:** the bus is the central abstraction; you can't test the CPU without a bus, and you can't test the PPU without a bus, and the bus needs *something* to dispatch to. ARCHITECTURE.md §6 and PITFALLS.md per-pitfall "Phase to address" tags both confirm this order.
- **Why MBCs in Phase 2, not Phase 1:** Phase 1 needs a working CPU to load *any* test ROM; Blargg's `cpu_instrs.gb` is ROM-only. Pushing MBCs to Phase 2 means Phase 1 stays small and testable; commercial games start playing in Phase 2.
- **Why PPU in Phase 3, not earlier:** the PPU is the most timing-sensitive subsystem and the riskiest to get wrong. Locking the bus model in Phases 1–2 means the PPU can be tested with the Mooneye `ppu/*` and `oam_dma/*` suites without fighting other subsystems.
- **Why APU is not in v1:** PROJECT.md explicitly defers; APU is a strict superset of CPU/PPU work and well-isolated. Fits cleanly in v1.x after Phase 4.

### Research Flags Summary

| Phase | Research needed? | Why |
|-------|------------------|-----|
| **Phase 1** (CPU + bus + SDL3 skeleton) | ✅ Skip research | mattneel/zgbc + Ryp + castholm/SDL breakout example are canonical references |
| **Phase 2** (Timer + Interrupts + MBCs) | ⚠️ Light research-phase | MBC1 mode 1 + MBC5 9-bit bank + MBC3 RTC latch are subtle; verify Pan Docs §MBCs against SameBoy `mbc.c` |
| **Phase 3** (PPU + rendering) | ⚠️ **Research-phase strongly recommended** | Mode-3 dot accounting + SCX%8 + window penalty + STAT IRQ; SameBoy `display.c` + dmg-acid2 reference image are dense |
| **Phase 4** (Polish + cross-platform) | ⚠️ Light research-phase | BESS 1.0 footer format (LIJI32/SameBoy); macOS cross-compile constraints (Apple SDK on a Mac builder) |

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| **Stack** | **HIGH** | Verified against ziglang.org 0.16 release notes, `castholm/SDL` v0.5.1 (Jun 2026), castholm/zig-examples breakout, mattneel/zgbc, SDL3 wiki |
| **Features** | **HIGH** for DMG landscape (Pan Docs, SameBoy, Blargg, Mooneye are the de-facto checklist); **MEDIUM** for prioritization (judgement-based; competitive moat is the static-binary + cycle-accurate + DMG-only triad) |
| **Architecture** | **HIGH** for component layout + data flow (consensus across SameBoy, Mooneye, Gambatte, BGB, Ryp, mattneel/zgbc); **MEDIUM-HIGH** for build order (matches Ryp's commit history and the standard "ROM-only → timer → PPU BG → sprites → MBC" order) |
| **Pitfalls** | **HIGH** for hardware-correctness items (Pan Docs, Mooneye, SameSuite, Gekkio blog posts); **MEDIUM** for Zig-specific items (verified against Zig 0.16 language ref, but some "community wisdom" may shift) |

**Overall confidence: HIGH.** The product category is mature; reference implementations exist in every language; the test surface is well-defined. The risk is not "can this be built" but "will the per-subsystem timing be correct on first attempt" — which the phase ordering and Mooneye/`dmg-acid2` gates defuse.

### Gaps to Address (need resolution before / during planning)

- **Open Question 1 — Boot ROM strategy:** SameBoy ships an open-source reimplementation under `BootROMs/dmg_boot.asm`. Legal status of bundling/distributing is murky. **Options:** (a) skip boot ROM, hardcode post-boot state (standard v1 approach, document), (b) bundle an open-source dump with a `LICENSE.bootrom` file, (c) prompt the user to provide a dump at first run. PROJECT.md doesn't address this. **Decision needed before Phase 4.**
- **Open Question 2 — MBC3 RTC scope:** Pan Docs MBC3 includes a 9-byte RTC register for cart types `$0F`/`$10`. No popular DMG-only commercial title uses it (Pokémon Gold/Silver/Crystal are CGB). **Recommended for v1:** skip RTC entirely; document. Add a "MBC3 RTC" issue for v1.x. **Confirm with user.**
- **Open Question 3 — APU deferral confirmation:** PROJECT.md §"Out of Scope" defers APU to after v1. FEATURES.md defers to v1.x. STACK.md covers SDL3 audio API for the deferred work. **Recommended: keep APU out of v1; add to Phase 4 polish only if trivial, otherwise v1.x.** **Confirm with user.**
- **Open Question 4 — Test ROM acquisition:** Blargg, Mooneye, dmg-acid2 are hosted on GitHub but not vendored (copyright). **Options:** (a) ship a `tests/fetch.sh` + `zig build test` step that downloads at test time, (b) document in README. **Recommended: (a) — CI-friendly.** **Confirm with user.**
- **Open Question 5 — Boot register state source-of-truth:** PITFALLS §M3 says "set the documented post-boot state when skipping boot ROM" (Pan Docs § "Power_Up_Sequence" § "Console state after boot ROM hand-off"). Exact values for DMG, MGB, SGB, CGB differ. **Recommend:** support MGB as the default model (what dmg-acid2 targets) with the documented register values. **Confirm with user.**
- **Gap — exact frame period pacing:** "59.7275 Hz" implies a per-frame sleep of `~16.7424 ms`; the host's `SDL_Delay` granularity is ~1 ms on most systems. **Confirm during Phase 3 research-phase:** how to budget the 0.74 ms of slack (drop frame? accumulate microseconds? track absolute wall-clock and only sleep when ahead?).
- **Gap — mattneel/zgbc and BESS save states:** mattneel/zgbc does *not* ship BESS save state format. SameBoy does. Phase 4 research-phase should pull BESS 1.0 spec directly from `LIJI32/SameBoy/blob/master/BESS.md` rather than relying on FEATURES.md's summary.

---

## Sources (aggregated — see each research file for full URLs)

### Primary (HIGH confidence)

- **STACK.md** § "Recommended Stack" (Zig 0.16.0, SDL3 via castholm/SDL v0.5.1, `b.addTranslateC`, `x86_64-linux-musl`, ReleaseFast+strip+lto=full); § "Build Configuration" (build.zig skeleton, cross-compile); § "What NOT to Use" (@cImport, SDL2 direct, dynamic-link, C++ deps, Make/CMake, Electron, WebGPU)
- **FEATURES.md** § "Table Stakes" (15 P1 features); § "MVP Definition" (12 ship-with items); § "Anti-Features" (CGB, SGB, APU, peripherals, debugger, TAS, shaders); § "Competitor Feature Analysis" (SameBoy as benchmark)
- **ARCHITECTURE.md** § "Standard Architecture" (CPU-bus-peripheral model); § "Reference Emulators" (SameBoy, Mooneye, Ryp/gb-emu-zig, mattneel/zgbc, fengb/fundude); § "Recommended Project Structure" (flat src/ + per-component subfolders); § "Zig-Specific Patterns" (`packed struct` register file + MMIO, `comptime` opcode tables, single `Emulator` struct, allocator discipline, C-ABI for SDL3); § "Build Order" (12-phase roadmap, 4-week v1 estimate)
- **PITFALLS.md** § "Critical Pitfalls" (10 items: timer falling-edge, HALT-bug + ei delay, PPU mode-3 bus blocking, OAM DMA bus conflicts, OAM corruption, MBC1 00→01, MBC3 RTC latch, spurious STAT IRQ, open-bus reads, invalid opcodes); § "Zig-Specific Pitfalls" (8 items: integer overflow, `undefined` in ReleaseFast, allocator discipline, C-ABI for SDL2, build API churn, slice bounds checks, `comptime` recursion, big-endian header); § "Looks Done But Isn't" checklist (15 verification items)
- **External — gbdev Pan Docs** (gbdev.io/pandocs) — memory map, I/O registers, PPU modes, MBC specs, power-up sequence (HIGH)
- **External — SameBoy** (LIJI32/SameBoy) — gold-standard accuracy reference; BESS 1.0 spec; open-source DMG boot ROM (HIGH)
- **External — mattneel/zgbc** (Ryp) — closest Zig reference; ~3,500 LOC; full Blargg pass; `zig-0.16-llm-context.md` ships with repo (HIGH)
- **External — castholm/SDL** — Zig SDL3 package; v0.5.1 (Jun 7, 2026); requires Zig 0.16/0.17 (HIGH)
- **External — Blargg / Mooneye / dmg-acid2 test ROMs** — `cpu_instrs`, `instr_timing`, `dmg-acid2`, Mooneye `timer/`, `ppu/`, `oam_dma/`, `interrupt/`, `mbc1/`, `bits/` (HIGH)
- **PROJECT.md** — confirmed requirements + out-of-scope items; SDL2 listed (will standardize to SDL3 in this synthesis — confirm)

### Secondary (MEDIUM confidence)

- **Humpheh/goboy README** — recent from-scratch emulator's TODO list; 2020, may be stale (FEATURES.md)
- **fengb/fundude** (Zig 0.6, unmaintained 2019) — historical Zig pattern (ARCHITECTURE.md)
- **agentultra/zig8** (Zig 0.15 Chip-8) — modern `comptime` opcode table idiom (ARCHITECTURE.md)
- **anyzig** (marler8997) — DX improvement; wrapper that auto-fetches Zig version per `build.zig.zon` (STACK.md)

### Tertiary (LOW confidence — needs validation during implementation)

- Exact 59.7275 Hz pacing strategy on real hardware (PITFALLS M6, m4) — needs Phase 3 research-phase benchmarking
- MBC1 mode 1 wiring on 1 MiB+ multicarts (PITFALLS §6) — needs Phase 2 research-phase cross-check against SameBoy `mbc.c`
- dmg-acid2 expected output pixel map — needs Phase 3 research-phase capture from mattcurrie repo

---

*Research completed: 2026-06-18*
*Ready for roadmap: **yes** (4-phase vertical-slice structure proposed; APU deferred to v1.x per PROJECT.md; all four research files are written and committed together by this synthesis)*
