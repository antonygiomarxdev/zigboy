# Architecture Research: ZigBoy (DMG Emulator in Zig)

**Domain:** 8-bit console emulator (Game Boy DMG-01)
**Researched:** 2026-06-18
**Confidence:** HIGH

This document describes how a Game Boy DMG emulator is structured, what the major components are, how a single tick propagates through the system, and how Zig's compile-time / allocator / `comptime` features shape the design. It is intended to be the authoritative reference that the ZigBoy roadmap phases build against.

---

## Executive Summary

A DMG emulator is a deterministic, cycle-stepped state machine. The CPU is the *orchestrator*, not the boss: every memory access it performs is a 4-T-cycle (one **M-cycle**) event that is also observed by the timer, the PPU, the APU, the DMA controller, and the joypad. Emulating the LR35902 well means the *bus* is the central abstraction — not the CPU.

Across every reference emulator surveyed (SameBoy in C, Mooneye in Rust, Ryp's `gb-emu-zig` in Zig, Gambatte, fundude, etc.) the same five components always appear:

1. **CPU** (LR35902 / Sharp SM83) — registers, flag register, opcode fetch/decode/execute, interrupt dispatch, HALT/STOP.
2. **MMU / Bus** — a single function `read8(addr)` / `write8(addr, value)` that dispatches to the right memory region or peripheral. The bus is where the cycle-accurate peripheral ticking happens.
3. **PPU** — line-based (154 lines × 456 dots), 4-mode state machine (HBlank, VBlank, OAM scan, drawing) that owns VRAM, OAM, and the 160×144 framebuffer.
4. **Timer** — 16-bit internal `div` counter that is exposed to the ROM as `DIV`, plus `TIMA/TMA/TAC` driven by the falling edge of selected bits of `div`.
5. **Cartridge / MBC** — owns the ROM file, maps `0000–7FFF` and `A000–BFFF` reads/writes through an MBC1/3/5 state machine. Persists battery-backed RAM.

Plus two smaller, more peripheral concerns that hang off the bus:
- **Joypad** — `P1/JOYP` register + a row-select trick; trivial state machine.
- **APU** — 4 channels + wave RAM; explicitly out of scope for ZigBoy v1.

The natural **vertical MVP slice** (one phase, one playable ROM) is: ROM load → CPU + bus + WRAM + ROM-only cart → framebuffer array → SDL2 window. The rest of the components (timer, PPU modes, joypad, MBCs) are then layered onto the bus one at a time without changing the shape of the system.

Zig's affordances are unusually well-matched to this domain:
- `packed struct` for the register file and the 256-byte MMIO block replaces thousands of lines of bit math.
- `comptime` opcode tables turn the 256-entry main fetch table plus 256-entry CB-prefixed table into a single static jump target.
- `ArenaAllocator` (or a single `GeneralPurposeAllocator` for the whole emulator) replaces per-component heap churn.
- `@cImport` of SDL2 / miniaudio is enough for the entire frontend — no build-time codegen or wrapper.
- `zig build` is the canonical build system; SDL2 is a single build.zig dependency.
- `comptime` assertions (`@offsetOf`, `@sizeOf`) let us verify the hardware layout of MMIO at compile time.

---

## 1. Standard Architecture (DMG-Only)

### 1.1 System Overview

```
                           ZigBoy Process (release-fast static binary)
   ┌──────────────────────────────────────────────────────────────────┐
   │                            main.zig                               │
   │   parse args → load ROM → init SDL2 → run frame loop → cleanup   │
   └────┬───────────────────────────────────────────────────┬─────────┘
        │                                                   │
        ▼                                                   ▼
  ┌──────────────┐                                  ┌──────────────┐
  │   frontend   │                                  │  cartridge   │
  │  (sdl.zig)   │                                  │   (cart.zig) │
  │  ┌────────┐  │  key_down / key_up / vblank     │  ROM bytes   │
  │  │  SDL2  │  │  ───────────────────────────►   │  RAM bytes   │
  │  │  input │  │                                  │  MBC state   │
  │  │  +     │  │  ◄───────────────────────────   │  (MBC1/3/5)  │
  │  │  audio │  │  framebuffer (160×144×u8)        │              │
  │  └────┬───┘  │                                  └──────┬───────┘
   ┌──────┴─────────────────────────────────────────────────┴────────┐
   │                       Emulator Core                              │
   │                                                                   │
   │   ┌───────────────────────────────────────────────────────────┐   │
   │   │                          CPU                              │   │
   │   │  registers, flags, PC, SP, IME, halt, pending_cycles     │   │
   │   │  fetch → decode → execute (comptime opcode table)        │   │
   │   └──────────────────────────┬────────────────────────────────┘   │
   │                              │  read(addr) / write(addr, val)    │
   │                              ▼                                    │
   │   ┌───────────────────────────────────────────────────────────┐   │
   │   │                        Bus / MMU                          │   │
   │   │   switch on addr:                                         │   │
   │   │     0000-7FFF  → cartridge.read/write (ROM / MBC regs)   │   │
   │   │     8000-9FFF  → ppu.vram[addr-0x8000]                    │   │
   │   │     A000-BFFF  → cartridge.read/write (ext RAM)           │   │
   │   │     C000-DFFF  → wram[addr-0xC000]                        │   │
   │   │     E000-FDFF  → wram[addr-0xE000] (echo, mirror)         │   │
   │   │     FE00-FE9F  → ppu.oam                                  │   │
   │   │     FEA0-FEFF  → 0xFF (or implementation-defined)         │   │
   │   │     FF00-FFFF  → mmio[addr-0xFF00]   (packed struct)     │   │
   │   │                                                           │   │
   │   │   On every access: tick timer, tick ppu, tick dma,        │   │
   │   │                     tick joypad, raise interrupts         │   │
   │   └──────────────────────────┬────────────────────────────────┘   │
   │                              │                                    │
   │      ┌──────────────┬────────┴────────┬──────────────┐            │
   │      ▼              ▼                 ▼              ▼            │
   │  ┌────────┐   ┌──────────┐      ┌──────────┐   ┌──────────┐     │
   │  │ Timer  │   │   PPU    │      │   DMA    │   │ Joypad   │     │
   │  │ div,   │   │  mode    │      │  OAM     │   │  P1 reg  │     │
   │  │ TIMA,  │   │  LY,LYC  │      │  copy    │   │  dpad,   │     │
   │  │ TMA,   │   │  STAT    │      │  src→    │   │  buttons │     │
   │  │ TAC    │   │  160x144 │      │  OAM     │   │          │     │
   │  └────────┘   └────┬─────┘      └──────────┘   └──────────┘     │
   │                    │                                              │
   │                    ▼                                              │
   │              framebuffer: [23040]u8  (160×144, palette indices)  │
   │                                                                   │
   │   ┌───────────────────────────────────────────────────────────┐   │
   │   │                    APU (deferred, v1)                     │   │
   │   └───────────────────────────────────────────────────────────┘   │
   └───────────────────────────────────────────────────────────────────┘
```

### 1.2 Component Responsibilities

| Component | Responsibility | Typical Implementation | Notes |
|-----------|----------------|------------------------|-------|
| **CPU** (`cpu.zig`) | Fetch/decode/execute SM83 instructions; maintain registers, PC, SP, IME, HALT state | Tagged-union `Instruction` decoded once via 256-entry `comptime` table; `execute(instruction)` switch | The CPU does **not** own memory; it calls `bus.read8/write8` for every fetch and store. |
| **Bus / MMU** (`bus.zig` or inlined in `cpu.zig`) | Single chokepoint for all memory access; dispatches by address range; ticks peripherals on every M-cycle | `pub fn read8(self: *Bus, addr: u16) u8` and `pub fn write8(...)`; switch on `addr >> 12` for ROM/VRAM/RAM, switch on `addr & 0xFF` for MMIO | Most natural place to centralize the cycle-accurate "every memory access advances time" rule. |
| **Cartridge / MBC** (`cart.zig`) | Owns ROM and external RAM; implements the MBC1/3/5 state machine that maps `0000-7FFF` and `A000-BFFF` | A tagged union over `Romb0`, `Mbc1`, `Mbc3`, `Mbc5` selected by `header.cart_type`; battery RAM persisted to `<rom>.sav` | Parse the 80-byte header (0x0100-0x014F) on load: title, cart type, ROM size, RAM size. |
| **PPU** (`ppu.zig`) | Mode 0/1/2/3 state machine on a per-dot basis; fetches BG/window tiles and OAM sprites; writes 160×144 framebuffer | `step(ppu, m_cycles: u32)` ticks 4 dots at a time; `screen_output: [23040]u8` is a u8-per-pixel (palette index) framebuffer | Owns VRAM (8 KiB) and OAM (160 B, 40 sprites × 4 B). |
| **Timer** (`timer.zig`) | 16-bit `div` counter increments every T-cycle; `tima` increments on selected `div` falling edge; on overflow, `tima = tma` and `IF.timer = 1` | `tick(timer, t_cycles: u32)`; on every read/write, the bus calls `tick(4)` | DIV is the "free clock" — readable as the upper 8 bits of `div`, writable to reset. |
| **DMA** (`dma.zig`, often folded into bus) | 160-byte copy from `XX00–XX9F` to OAM in 160 M-cycles when `FF46` is written | Triggered by `write8(0xFF46, value)`; copies one byte per M-cycle from the source page | During DMA, OAM and source-region reads return 0xFF. |
| **Joypad** (`joypad.zig`) | Maintains two 4-bit "pressed" masks (dpad, buttons); `P1` register combines them with a 2-bit row select | `read8(0xFF00)` returns the appropriate nibble based on `JOYP.input_select`; writes to `P1` change the select | Row select (bit 4 = dpad, bit 5 = buttons) is the only "addressing" trick. |
| **MMIO** (`mmio.zig`, inlined as `packed struct` in `Emulator`) | The 256-byte register block `0xFF00–0xFFFF` | Single `packed struct MMIO` with `comptime` offset assertions | This is one of the most idiomatic Zig uses — let the language be the assembler. |
| **APU** (`apu.zig`, deferred) | 4 channel mixers; wave RAM at `FF30–FF3F`; 1/512 frame sequencer | — | Out of scope for v1 per PROJECT.md. Stub the APU region as a no-op so the MMIO map still works. |
| **Frontend** (`sdl.zig`) | Window, event loop, key→joypad mapping, framebuffer → texture, audio callback | `@cImport(@cInclude("SDL.h"))`; `pub fn run(emulator: *Emulator) !void` | The frontend owns the *real time* loop; the emulator owns the *emulated time* loop. |

### 1.3 Data Flow: One Tick

For each instruction the CPU executes:

1. **CPU fetch** (1 M-cycle, 4 T-cycles):
   - `pc = 0x0100` (or wherever) → `bus.read8(pc)` → bus dispatches to `cartridge.rom[pc]` for ROM-only, or ROM bank 0 / N for MBC.
   - The bus records `t_cycles_consumed += 4` and calls `timer.tick(4)`, `ppu.tick(4)`, `dma.tick(4)`, `joypad.tick(4)`.
2. **CPU decode**: lookup the opcode in a `comptime` table → produce a tagged-union `Instruction`.
3. **CPU execute**: switch on `instruction` tag. Each branch either:
   - Mutates CPU state (e.g. `INC A`) — no bus access needed.
   - Reads memory (e.g. `LD A, (HL)`) — calls `bus.read8(HL)`, which ticks peripherals 4 more T-cycles.
   - Writes memory (e.g. `LD (HL), A`) — calls `bus.write8(HL, A)`, which ticks peripherals 4 more T-cycles.
4. **CPU pre-fetch next** (1 M-cycle): `pc++` → `bus.read8(pc)`. This is the "free" cycle that makes LR35902 pipelined and is what makes total cycles per instruction always be a multiple of 4.
5. **Interrupts**: after each instruction, if `IME` and any of `IF & IE` are set, the CPU calls `interrupt_handler(bit)`: pushes PC to stack, jumps to `0x40 + bit*8`, clears the bit in IF, sets `IME = false`. Cost: 5 M-cycles.
6. **HALT**: if HALT is set, the CPU just spins calling `bus.read8(pc)` (4 T-cycles) until an interrupt fires.
7. **End of frame**: when PPU enters VBlank (line 144), it sets `IF.vblank = 1` and the frontend's frame loop ends. The frontend then pushes the framebuffer to the SDL2 texture, swaps the audio buffer, and polls input.

The **bus is the single chokepoint for cycle counting** — every `read8` and `write8` call advances the global cycle counter by 4 T-cycles, and that single counter is fanned out to all peripherals. This is how SameBoy, Mooneye, Ryp, and every other cycle-accurate emulator works.

### 1.4 Memory Map (DMG)

For bus dispatch, the canonical layout is:

| Range | Size | Owner | Notes |
|-------|------|-------|-------|
| `0x0000–0x00FF` | 256 B | Cart (boot ROM, if mapped) | Toggle via `FF50` |
| `0x0000–0x3FFF` | 16 KiB | Cart ROM bank 0 | Fixed (or boot ROM) |
| `0x4000–0x7FFF` | 16 KiB | Cart ROM bank N | MBC1: 2-bit, MBC3: 7-bit, MBC5: 9-bit |
| `0x8000–0x9FFF` | 8 KiB | PPU VRAM | Locked during PPU mode 3 (returns 0xFF) |
| `0xA000–0xBFFF` | 8 KiB | Cart external RAM | Battery-backed; can be disabled via MBC |
| `0xC000–0xCFFF` | 4 KiB | WRAM (fixed bank) | Always present |
| `0xD000–0xDFFF` | 4 KiB | WRAM (DMG: same as `C000`; CGB: banked 1–7) | DMG v1: just mirror `C000` |
| `0xE000–0xFDFF` | ~7 KiB | Echo RAM | Mirror of `C000–DDFF`; reads/writes same bytes |
| `0xFE00–0xFE9F` | 160 B | PPU OAM | 40 sprites × 4 B; locked during modes 2 & 3 |
| `0xFEA0–0xFEFF` | 96 B | Unusable | DMG: returns 0x00 (or triggers OAM bug on read) |
| `0xFF00–0xFF7F` | 128 B | MMIO | Packed struct |
| `0xFF80–0xFFFE` | 127 B | HRAM | Fast CPU-accessible RAM |
| `0xFFFF` | 1 B | IE | Interrupt enable register |

---

## 2. Reference Emulators (Patterns to Borrow)

These are the emulators to read before writing ZigBoy. The format is *what to steal* and *what to avoid*.

| Emulator | Lang | What to steal | What to avoid |
|----------|------|---------------|---------------|
| **[SameBoy](https://github.com/LIJI32/SameBoy)** (`Core/`) | C | Canonical component layout: `cpu.c`, `memory.c`, `ppu.c` (`Core/display.c`), `apu.c`, `mbc.c`, `joypad.c`. The `read_map[16]` function-pointer table in `memory.c` is the cleanest bus dispatch. T-cycle-accurate model via `GB_run()` loop calling `GB_cpu_run()`. | The full source is ~25 kLOC. The bitwise OAM-corruption code is fascinating but should be v2/v3 work. The C build (`Makefile`) is heavyweight; we use `zig build` instead. |
| **[Mooneye GB](https://github.com/Gekkio/mooneye-gb)** (`core/src/`) | Rust | Clean trait-based separation: `CpuContext::read_cycle/write_cycle/tick_cycle` is the trait the CPU calls into. `Hardware::generic_cycle` is the central tick that runs `ppu.emulate`, `timer.tick_cycle`, `apu.tick_cycle` once per M-cycle. The `OamDma` struct inlined into `Peripherals`. The `EmuEvents` / `EmuTime` separation (events vs. time) is a nice pattern for a debugger. | Trait dispatch in Zig is awkward; use a `*Bus` pointer instead. The Rust borrow checker makes some patterns verbose that Zig handles natively. |
| **[Ryp/gb-emu-zig](https://github.com/Ryp/gb-emu-zig)** (`src/gb/`) | Zig | **The closest reference for ZigBoy.** Uses `packed struct` for `Registers` with both little/big-endian variants (`@bitCast` between r8 and r16 views). Uses a `packed union { t_cycles: u64, bits: ... }` for the clock to get `div` "for free" as a bit field. Uses a single `MMIO` `packed struct` with `comptime assert(@offsetOf(MMIO, "ppu") == 0x40)` to verify hardware layout. Uses `comptime` `assert(@sizeOf(MMIO) == 256)`. `execution.zig` is the per-instruction cycle counter (`pending_t_cycles`) that's flushed at the end of each instruction via `consume_pending_cycles`. Excellent use of `std.mem.asBytes(&mmio)` for the FF00-FFFF raw-byte view, then per-register per-byte handlers for quirks. | Single-file-per-component is good, but they put APU in v1 — we should stub APU. |
| **[fengb/fundude](https://github.com/fengb/fundude)** | Zig | Wasm-targeted — proves Zig→wasm works for emulators. The "single main loop, single `step()`" pattern is portable. | Old Zig (0.6). Unmaintained since 2019. Mostly useful as historical context. |
| **[agentultra/zig8](https://github.com/agentultra/zig8)** | Zig (Chip-8) | Idiomatic Zig 0.15 `comptime` opcode table (`switch (opcode & 0xF000)`). Single file `zig8.zig` holds all CPU state as module-level `var` (works for Chip-8; for GB, prefer a struct). Uses `std.Random.uintAtMost` for the RND instruction. | Chip-8 is too simple to teach GB architecture. |
| **[Luukdegram/lion](https://github.com/Luukdegram/lion)** | Zig (Chip-8) | Clear `c.zig` for C-ABI bindings to GLFW/OpenAL/dr_wav; `emulator.zig` is the orchestrator that drives the CPU and feeds the frontend. | Uses GLFW instead of SDL2; we use SDL2 per PROJECT.md. |
| **[Gambatte](https://github.com/sinamas/gambatte)** | C++ | High accuracy; widely cited for cycle timing of PPU. | Source is private; only the README is on GitHub. |
| **BGB / binjgb / Wiser** | C | All share the same "bus dispatches to peripheral" pattern. BGB is Windows-only. binjgb is single-file and very readable (~5 kLOC). | Less relevant to Zig architecture. |

**Recommended reading order for a fresh implementation:**
1. Ryp/gb-emu-zig `cpu.zig` + `execution.zig` for the Zig-specific patterns.
2. Mooneye `hardware.rs` for the canonical peripheral-tick structure.
3. Pan Docs + `gbctr.pdf` for the *authoritative* hardware behavior.
4. SameBoy `memory.c` and `ppu.c` only when you need to debug a specific quirk.

---

## 3. Recommended Project Structure

```
zigboy/
├── build.zig                  # Build script: SDL2 dep, exe + test artifacts
├── build.zig.zon              # Package manifest
├── .gitignore
├── LICENSE                    # MIT
├── README.md
├── roms/                      # (gitignored) test ROMs from Blargg/Mooneye
├── .planning/                 # GSD planning docs
└── src/
    ├── main.zig               # arg parsing, ROM load, SDL init, frame loop
    ├── sdl.zig                # SDL2 C-ABI bindings + window/renderer/audio glue
    │
    ├── emulator.zig           # Top-level Emulator struct (owns all state)
    │
    ├── cpu/
    │   ├── mod.zig            # `pub const Cpu = @import("cpu.zig").Cpu;` etc.
    │   ├── cpu.zig            # Cpu struct, Registers, FlagRegister, step()
    │   ├── instructions.zig   # `Instruction` tagged union + `comptime` decode table
    │   └── decode.zig         # (optional) split out CB-prefixed table
    │
    ├── bus.zig                # read8/write8 dispatch, per-cycle peripheral tick
    │
    ├── mmio.zig               # `packed struct MMIO` with comptime offset asserts
    │
    ├── ppu/
    │   ├── mod.zig
    │   ├── ppu.zig            # Ppu struct, mode state machine, framebuffer
    │   ├── tile.zig           # BG / window / sprite tile fetch (pure)
    │   └── sprite.zig         # OAM scan, sprite sorting, sprite fetch
    │
    ├── timer.zig              # div/tima/tma/tac, tick()
    │
    ├── dma.zig                # OAM DMA, 160-byte copy state machine
    │
    ├── joypad.zig             # P1 register, dpad/button masks
    │
    ├── cartridge/
    │   ├── mod.zig            # `pub const Cart = @import("cart.zig").Cart;`
    │   ├── cart.zig           # Cart struct, header parsing, save/load
    │   ├── mbc1.zig           # MBC1 state machine
    │   ├── mbc3.zig           # MBC3 (with RTC placeholder)
    │   ├── mbc5.zig           # MBC5 state machine
    │   └── rom_only.zig       # No-MBC fallback
    │
    ├── interrupt.zig          # IF/IE, pending interrupt dispatch
    │
    ├── test_roms/             # Test ROM runners (headless)
    │   ├── blargg.zig         # cpu_instrs runner with serial output
    │   └── dmg_acid.zig       # PPU visual test runner
    │
    └── apu/                   # v2: stub for now
        └── mod.zig
```

### 3.1 Structure Rationale

- **Flat src/ + per-component subfolder only for components with > 1 file** (PPU, cartridge, CPU). This matches the Ryp and Mooneye convention and keeps the import graph small.
- **`mod.zig` per folder** lets us write `@import("ppu/mod.zig")` and re-export the public surface, so internal refactors don't break callers.
- **No `lib/` vs `bin/` split** — the emulator is one binary per PROJECT.md (`< 5 MB` target). If we ever ship a `libretro` core or a test harness, we'd extract a `lib.zig` at that point.
- **Test ROM runners in `src/test_roms/`** rather than `tests/` because they need full emulator state, not just unit tests. They'll be headless variants of `main.zig`.

### 3.2 Recommended `build.zig` Skeleton

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // SDL2 dependency
    const sdl_dep = b.dependency("sdl2", .{ .target = target, .optimize = optimize });
    const sdl_lib = sdl_dep.artifact("SDL2");

    // Executable
    const exe = b.addExecutable(.{
        .name = "zigboy",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.linkLibrary(sdl_lib);
    exe.linkLibC();  // SDL2 is C
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the emulator");
    run_step.dependOn(&run_cmd.step);

    // Tests (one per logical layer)
    const cpu_tests = b.addTest(.{ .root_source_file = b.path("src/cpu/cpu.zig"), .target = target, .optimize = optimize });
    const ppu_tests = b.addTest(.{ .root_source_file = b.path("src/ppu/mod.zig"), .target = target, .optimize = optimize });
    // ... one per module
    const test_step = b.step("test", "Run all unit tests");
    test_step.dependOn(&b.addRunArtifact(cpu_tests).step);
    test_step.dependOn(&b.addRunArtifact(ppu_tests).step);
}
```

---

## 4. Architectural Patterns (Zig-Specific)

### 4.1 Pattern: `packed struct` for the Register File

The LR35902 register file is 8 8-bit registers (A, F, B, C, D, E, H, L) that can also be read/written as 4 16-bit pairs (AF, BC, DE, HL). Naïve C/Rust emulators write 200 lines of bit-mask-and-shift. In Zig, the entire register file is a `packed struct` and 16-bit views are free via `@bitCast`:

```zig
const Registers = packed struct {
    c: u8,
    b: u8,
    e: u8,
    d: u8,
    l: u8,
    h: u8,
    flags: FlagRegister,
    a: u8,
    sp: u16,
    pc: u16,
};

const FlagRegister = packed struct {
    _unused: u4,    // Must stay 0 for PUSH AF / POP AF
    carry: u1,
    half_carry: u1,
    substract: bool, // (yes, spelled substract in Pan Docs)
    zero: bool,
};

comptime {
    std.debug.assert(@sizeOf(FlagRegister) == 1);
    std.debug.assert(@sizeOf(Registers) == 12);
}

// Reading BC as a u16:
const registers_r16: *Registers_R16 = @ptrCast(&self.regs);
const bc_value = registers_r16.bc;
```

This is Ryp's pattern verbatim, and it makes the ALU helpers trivial:
```zig
fn alu_add(self: *Cpu, value: u8) void {
    const sum, const carry = @addWithOverflow(self.regs.a, value);
    const _, const half_carry = @addWithOverflow(@as(u4, @truncate(self.regs.a)), @as(u4, @truncate(value)));
    self.regs.a = sum;
    self.regs.flags.carry = @intCast(carry);
    self.regs.flags.half_carry = @intCast(half_carry);
    self.regs.flags.substract = false;
    self.regs.flags.zero = self.regs.a == 0;
}
```

### 4.2 Pattern: `packed struct MMIO` with `comptime` Offset Assertions

The 256 bytes from `0xFF00–0xFFFF` are an MMIO block with per-register quirks. Encode the block as a single `packed struct` and let the language enforce the layout:

```zig
pub const MMIO = packed struct {
    JOYP: Reg_JOYP,    // 0x00
    SB: u8,           // 0x01
    SC: u8,           // 0x02
    _pad_03: u8,      // 0x03
    DIV: u8,          // 0x04 — actually returns upper 8 bits of internal 16-bit div
    TIMA: u8,         // 0x05
    TMA: u8,          // 0x06
    TAC: Reg_TAC,     // 0x07
    _pad_08_0E: [7]u8,
    IF: Reg_IF,       // 0x0F
    apu: APU_MMIO,    // 0x10–0x26 (or stub)
    wave_ram: [16]u8, // 0x30–0x3F
    ppu: PPU_MMIO,    // 0x40–0x4B
    _pad_4C_4F: [4]u8,
    BANK: u8,         // 0x50
    _pad_51_ff: [175]u8, // 0x51..0xFF (room for CGB + IE)
    IE: Reg_IE,       // 0xFF
};

comptime {
    std.debug.assert(@offsetOf(MMIO, "JOYP") == 0x00);
    std.debug.assert(@offsetOf(MMIO, "DIV") == 0x04);
    std.debug.assert(@offsetOf(MMIO, "IF") == 0x0F);
    std.debug.assert(@offsetOf(MMIO, "BANK") == 0x50);
    std.debug.assert(@offsetOf(MMIO, "IE") == 0xFF);
    std.debug.assert(@sizeOf(MMIO) == 256);
}
```

For per-byte quirks (e.g. `JOYP` only returns 4 bits, `IF`/`STAT`/`TAC` have unused high bits set to 1), wrap the raw read/write in a `bus.read8(0xFFxx)` that masks appropriately:
```zig
pub fn mmio_read(self: *Bus, offset: u8) u8 {
    const bytes = std.mem.asBytes(&self.mmio);
    return switch (offset) {
        0x00 => bytes[offset] & 0x0F,        // JOYP: only 4 valid bits
        0x04 => @truncate(self.timer.div >> 8), // DIV: read from internal counter
        0x0F => bytes[offset] | 0xE0,        // IF: high 3 bits read as 1
        0x41 => bytes[offset] | 0x80,        // STAT: high bit unused, reads 1
        else => bytes[offset],
    };
}
```

### 4.3 Pattern: `comptime` Opcode Decode Table

The 256-entry main fetch + 256-entry CB-prefixed table fits in two `comptime` arrays. This collapses the entire "is this a `LD A, n` or a `LD A, (BC)`" decision to a single array index at runtime:

```zig
pub const Instruction = union(enum) {
    nop,
    ld_r16_imm16: struct { r16: R16, imm16: u16 },
    ld_r8_imm8:   struct { r8: R8, imm8: u8 },
    ld_r8_r8:     struct { dst: R8, src: R8 },
    add_a_r8:     struct { r8: R8 },
    jp_imm16:     struct { imm16: u16 },
    // ... ~120 variants total, one per opcode class
    invalid: u8,
};

const main_decode: [256]DecodeEntry = blk: {
    var table: [256]DecodeEntry = undefined;
    // comptime-fill the table; each entry stores either a simple variant tag
    // or a struct of operands extracted from the byte stream.
    for (0..256) |i| table[i] = decode_main_opcode(@intCast(i));
    break :blk table;
};

pub fn fetch_decode(self: *Cpu) Instruction {
    const opcode = self.bus.read8(self.regs.pc);
    self.regs.pc +%= 1;
    return main_decode[opcode].decode_or_fetch_operands(self);
}
```

For `CB` prefix: identical 256-entry table, indexed by the *next* byte.

### 4.4 Pattern: Single `Emulator` Struct Owning Everything

Don't spread state across module-level globals. One struct, allocated by the caller:

```zig
pub const Emulator = struct {
    cpu: Cpu,
    bus: Bus,
    ppu: Ppu,
    timer: Timer,
    dma: Dma,
    joypad: Joypad,
    cart: Cart,
    apu_stub: ApuStub, // v1: writes are silently ignored
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, rom: []const u8) !Emulator {
        // ... allocate VRAM, WRAM, HRAM, framebuffer, cart RAM
        // ... parse header, init MBC
    }
    pub fn deinit(self: *Emulator) void { /* free all */ }
    pub fn step(self: *Emulator) void { /* one CPU step */ }
    pub fn run_frame(self: *Emulator) void {
        while (!self.ppu.frame_ready) self.step();
    }
    pub fn framebuffer(self: *Emulator) []const u8 {
        return &self.ppu.screen_output;
    }
    pub fn key_down(self: *Emulator, key: JoypadKey) void { ... }
    pub fn key_up(self: *Emulator, key: JoypadKey) void { ... }
};
```

The frontend (`main.zig`, `sdl.zig`) holds a `*Emulator` and calls `step()` / `framebuffer()` / `key_*()`. This is the same shape as SameBoy's `GB_gameboy_t` and Ryp's `GBState`, but with the convenience of Zig's `defer self.deinit()`.

### 4.5 Pattern: Allocator Discipline

The PROJECT.md constraint is "no garbage collection; manual or arena allocators only." The natural choice is:

- **`std.heap.GeneralPurposeAllocator(.{})`** at the top of `main()` for development (catches leaks).
- **`std.heap.ArenaAllocator`** wrapping the GPA in release builds if we want one-shot cleanup.
- Pass `allocator` explicitly to `Emulator.init`; every `Emulator` field is a slice owned by the Emulator, freed in `Emulator.deinit`.

```zig
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
defer _ = gpa.deinit();
const allocator = gpa.allocator();

var emu = try Emulator.init(allocator, rom_bytes);
defer emu.deinit();
```

What **not** to do: per-component allocators, ref-counted buffers, or per-frame allocations in the hot path. The hot path (`step()`) must not call `allocator` at all — everything is pre-allocated at `init`.

### 4.6 Pattern: C-ABI Interop for SDL2

Zig can `@cImport` SDL2 directly. For a small surface (window, renderer, texture, audio stream, events, keys), this is enough — no wrapper library needed:

```zig
const c = @cImport(@cInclude("SDL.h"));

pub fn run(emu: *Emulator) !void {
    if (!c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_AUDIO | c.SDL_INIT_EVENTS)) return error.SDLInitFailed;
    defer c.SDL_Quit();
    // ...
}
```

For audio in v1 (per PROJECT.md, audio is deferred) we can also stub it out and not even call `SDL_INIT_AUDIO`. For v2 audio, `miniaudio` is a single-header C library that Zig can `@cInclude` the same way.

### 4.7 Pattern: CGB-only Fields Are Skipped at Compile Time (Future)

When we add CGB support (out of scope for v1), the right pattern is `comptime` feature flags in `build.zig`:

```zig
const cgb_mode = b.option(bool, "cgb", "Enable Game Boy Color support") orelse false;
exe_options.addOption(bool, "cgb", cgb_mode);
```

Then in code:
```zig
const Emulator = switch (@hasDecl(build_options, "cgb") and build_options.cgb) {
    true => struct { ...CGB fields... },
    false => struct { ...DMG fields... },
};
```

This keeps the v1 binary small and forces v1 to be the simpler machine, which is the PROJECT.md goal.

---

## 5. Data Flow (Detailed)

### 5.1 One Frame

```
Frontend (60 Hz loop)                  Emulator
─────────────────────                  ────────
poll SDL events                        
  ├─ key down → emu.key_down(key)      
  └─ key up   → emu.key_up(key)        
                                        
while !emu.ppu.frame_ready:            
  emu.step()         ◄────────────────  Step 5.2 below
                                        
emu.ppu.frame_ready = false            
push framebuffer to SDL texture        
swap audio buffer (v2)                 
SDL_RenderPresent                      
SDL_Delay until next 16.6ms            
```

### 5.2 One CPU Step (inside `emu.step()`)

```
Cpu.step() {
    self.handle_interrupts();          // 5 M-cycles if interrupt fires
    if (self.halted) {
        self.bus.read8(self.regs.pc);  // 1 M-cycle, advances timer+PPU
        return;
    }
    const inst = self.fetch_decode();  // 1–4 M-cycles depending on operands
    self.execute(inst);                // 0–N M-cycles depending on instruction
    self.bus.consume_pending_cycles(); // tick timer, ppu, dma, joypad
}
```

### 5.3 One Bus Read

```
Bus.read8(addr) {
    self.timer.tick(4);
    self.ppu.tick(4);
    self.dma.tick(4);
    self.joypad.tick(4);
    self.cycles_since_last_sync += 4;
    return switch (addr >> 12) {
        0x0..=0x7 => self.cart.read_rom(addr),
        0x8..=0x9 => self.ppu.read_vram(addr),  // 0xFF if PPU mode 3
        0xA..=0xB => self.cart.read_ram(addr),  // 0xFF if RAM disabled
        0xC..=0xD => self.wram[addr - 0xC000], // DMG: 8 KiB flat
        0xE       => self.wram[addr - 0xE000], // echo, mirror
        0xF       => switch (addr) {
            0xFE00..0xFE9F => self.ppu.read_oam(addr),  // 0xFF if PPU mode 2/3
            0xFF00..0xFFFF => self.read_mmio(addr),
            0xFF80..0xFFFE => self.hram[addr - 0xFF80],
            else => 0xFF,
        },
    };
}
```

### 5.4 PPU Tick

The PPU is the most timing-sensitive component. One M-cycle = 4 dots. The PPU has 456 dots per scanline × 154 scanlines = 70 224 dots per frame. At 4.19 MHz, that's 59.7275 frames/sec.

```
Ppu.tick(m_cycles: u32) {
    for (0..m_cycles) |_| {
        switch (self.mode) {
            .HBlank  -> { /* 87–204 dots */ ... }
            .VBlank  -> { /* 4560 dots total */ ... }
            .ScanOAM -> { /* 80 dots: select 10 sprites for LY */ ... }
            .Drawing -> { /* 172–289 dots: render 160 pixels */ ... }
        }
        self.dot += 1;
        if (self.dot == 456) {
            self.dot = 0;
            self.ly = (self.ly + 1) % 154;
            if (self.ly == 144) {
                self.mmio.IF.vblank = 1;
                self.frame_ready = true;
            }
            if (self.ly == self.lyc) self.mmio.IF.lcd |= 1;
        }
    }
}
```

---

## 6. Build Order (Recommended Phases)

The phases below form a **vertical slice** — each phase ships a demonstrable artifact (test ROM passing, or a window displaying something). This is the *only* sensible order because the system is deeply interconnected; you can't test the CPU without a bus, and you can't test the PPU without a bus, and the bus needs *something* to dispatch to.

### Phase 0: Skeleton (1 day)
- `build.zig` + `zig build run` hello-world
- `Emulator.init/deinit` no-op
- SDL2 window opening, clear to green

### Phase 1: "Hello ROM" — CPU + bus + ROM-only cart (1 week)
- **Vertical slice:** A *no MBC* ROM (e.g. Tetris has MBC3+; use *Tetris*'s first 32 KiB only via a custom test ROM, or use Blargg's `cpu_instrs.gb` which is ROM-only).
- Implement: `Cpu.registers`, `Cpu.step()` (without interrupts yet), `Bus.read8/write8` with a *minimal* address map (ROM + WRAM only — VRAM/MMIO return 0xFF), `Cpu.fetch_decode` for a small subset of opcodes (LD, JP, JR, INC, DEC, NOP, HALT).
- Pass Blargg's `cpu_instrs.gb` (ROM-only test ROM).
- *Why this phase:* You can't debug anything else until you have a working CPU. This is the maximum-feedback loop.

### Phase 2: Timer + Interrupts (3–4 days)
- Add the timer (`DIV`, `TIMA`, `TMA`, `TAC`) and the interrupt machinery (`IF`, `IE`, IME, HALT wakeup).
- Wire the bus tick to call `timer.tick(4)` on every read/write.
- Add the missing bus regions: HRAM, MMIO (just the IF/IE/JOYP bytes).
- Pass Blargg's `instr_timing.gb` and Mooneye's `timer/*` tests.
- *Why this phase:* Without the timer, almost every game hangs.

### Phase 3: Joypad (1 day)
- Add `Joypad` state and the `P1/JOYP` register.
- Map SDL2 keys to joypad keys in the frontend.
- *Why this phase:* Tiny; needed to interact with the test ROMs.

### Phase 4: PPU (VBlank + LY) (3–4 days)
- Add the PPU *skeleton*: `LY` counter, mode state machine, VBlank interrupt, STAT register.
- **No rendering yet** — framebuffer is just zero-filled.
- Pass Mooneye's `ppu/vblank_stat_intr` and `ppu/stat_lyc_onoff` tests.
- *Why this phase:* Most games' main loops depend on the VBlank interrupt. Without it, nothing animates.

### Phase 5: PPU BG + Window (1 week)
- Implement BG tile fetch, SCX/SCY scrolling, window rendering, BGP/OBP0/OBP1 palettes.
- Write palette indices to the framebuffer (160×144 × 1 byte).
- Push framebuffer to SDL2 texture in the frontend.
- Pass Mooneye's `ppu/lcdon_*` and the visual portion of `dmg-acid2`.
- *Visual milestone:* The Nintendo logo scrolls. Tetris shows the title screen.

### Phase 6: PPU Sprites (3–4 days)
- OAM scan at mode 2, sprite sorting, 8×8 / 8×16 sprite fetch, OBP0/OBP1 + X/Y flip + priority.
- Pass Mooneye's `ppu/oam_dma_*` and `ppu/sprite_priority`.
- *Visual milestone:* Tetris pieces appear. Zelda enemies appear.

### Phase 7: OAM DMA + Echo RAM (1 day)
- Implement `write8(0xFF46, ...)` triggering a 160-M-cycle OAM DMA.
- Implement Echo RAM as a 1:1 mirror of WRAM (it really is that trivial).
- Pass Mooneye's `oam_dma/*` tests.

### Phase 8: MBC1 + Save/Load (3–4 days)
- Detect cart type from header, dispatch to MBC1 state machine.
- Battery RAM → `<rom>.sav` file (load on init, save on emulator exit + on every MBC RAM write flagged dirty).
- Test with a real MBC1 game (e.g. *Super Mario Land*).
- *Milestone:* Most Game Boy library is now playable.

### Phase 9: MBC3 + MBC5 (3–4 days)
- Same pattern as MBC1.
- MBC3 has an RTC (defer RTC for v2; just ignore the RTC register writes for v1).
- MBC5 has a 9-bit ROM bank number.
- *Milestone:* "Plays 95% of the library" (MBC2, MBC6, MBC7, HuC1/3, etc. are rare).

### Phase 10: APU (1 week, *after* visuals are stable)
- 4 channels, frame sequencer, wave RAM.
- Mix to SDL2 audio stream.
- *Why deferred:* Visuals prove the architecture; audio is a large amount of code with no architectural risk.

### Phase 11: Polish (ongoing)
- Boot ROM support (optional; load from file).
- Frame pacing (use `SDL_GetTicks` to cap at ~59.73 Hz; allow 2× speed).
- Save states.
- Headless test runner for CI (run a ROM for N frames, snapshot framebuffer, diff vs. expected).

### Total v1 estimate: ~6–8 weeks of focused work.

---

## 7. Anti-Patterns (What NOT to Do)

### 7.1 Don't put the CPU at the center; put the bus at the center
The most common rookie mistake is having `Cpu` call directly into `Ppu`, `Timer`, etc. The bus must mediate so that *every* memory access advances the cycle counter. Otherwise the timer drifts, the PPU's mode transitions are wrong, and games glitch.

### 7.2 Don't use function pointers for the bus dispatch
SameBoy's `read_map[16]` of function pointers is fine in C, but in Zig, a `switch` on `addr >> 12` (or `addr & 0xF000`) is monomorphized and inlined to a jump table automatically. Faster and simpler.

### 7.3 Don't allocate in the hot path
`step()` runs ~4.2 million times per second. *Any* allocator call in the hot path will dominate. All buffers must be allocated in `init()` and owned by the `Emulator`.

### 7.4 Don't use a `pub var` global for the CPU state
A Chip-8 emulator can get away with module-level state because it's so simple. A GB emulator cannot: you need save states, multi-instance (for tests), and clean shutdown. One `Emulator` struct owned by the caller.

### 7.5 Don't try to be CGB-compatible from day 1
The PROJECT.md says DMG-only. Don't put CGB mode behind `comptime` flags, don't add CGB-only registers, don't second-guess the design. Add CGB as a v2 milestone by forking the struct layout, not by sprinkling `if (is_cgb)` everywhere.

### 7.6 Don't fetch instructions one byte at a time
The LR35902 has a 1-byte prefetch: the next opcode is read *during* the current instruction's last M-cycle. Emulating this gives you the right cycle count for free. If you ignore it, you'll be off by 4 T-cycles per instruction, which is a 0.4% speedup games will notice as a slight pitch-up in audio.

### 7.7 Don't ignore the CGB-only registers in the MMIO struct
The MMIO struct must be exactly 256 bytes because `bus.mmio[addr - 0xFF00]` is the raw byte. If you skip the CGB-only fields, the offsets of `BANK`, `IE`, etc. shift, and writes to them silently write to the wrong byte. The `comptime` offset asserts in §4.2 catch this at build time — *use them*.

### 7.8 Don't make the frontend know about CPU internals
`main.zig` and `sdl.zig` should depend only on `Emulator`'s public API (`step`, `framebuffer`, `key_down`, `key_up`). If the frontend reaches into `emu.cpu.regs`, the abstraction is leaking.

### 7.9 Don't put APU emulation behind a "we'll add it later" `unreachable`
If you stub APU register reads to `0xFF` and writes to no-op, you must do it for *every* APU register (0xFF10–0xFF3F) and *every* read quirk (e.g. NR52's high bit is the APU enable flag). Either implement it or replace the MMIO region with a 48-byte `_pad: [48]u8` and a comptime assert.

### 7.10 Don't use `@cInclude` for code that will change often
SDL2's `SDL.h` is stable; once you `@cImport` it, it should not need to be re-imported. The emulator's *own* headers should never be `@cImport`'d — only C libraries.

---

## 8. Integration Points

### 8.1 External Libraries

| Library | Integration | Why | Notes |
|---------|-------------|-----|-------|
| **SDL2** | `@cImport(@cInclude("SDL.h"))` + `b.dependency("sdl2")` | Window, input, audio. Stable, ubiquitous, simple C-ABI. | v1 needs only video + events; defer audio to v2. |
| **miniaudio** (v2) | `@cInclude("miniaudio.h")` — single header, no link | If we drop SDL audio in favor of miniaudio. | Currently, SDL2 audio is fine. |
| **Blargg test ROMs** | Not linked; loaded as `.gb` files at runtime | `cpu_instrs`, `instr_timing`, `dmg_sound` (later), `mem_timing` | Run them with `./zigboy roms/cpu_instrs.gb` and read serial output. |
| **Mooneye test ROMs** | Same | `timer/*`, `ppu/*`, `oam_dma/*`, `interrupt/*` | Pass/fail is a magic value in a memory address; we can read it from a test runner. |
| **dmg-acid2** | Same | Visual test of PPU correctness. Pass = looks like a reference image. | Reference image is in the dmg-acid2 repo. |

### 8.2 Internal Module Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| `main.zig` ↔ `sdl.zig` | `sdl.run(emu: *Emulator) !void` | The SDL module owns the *real-time* loop. The Emulator owns the *emulated-time* loop. |
| `main.zig` ↔ `Emulator` | `Emulator.init(allocator, rom)`, `emu.step()`, `emu.run_frame()`, `emu.framebuffer()`, `emu.key_*()` | The full public API. |
| `Cpu` ↔ `Bus` | `bus.read8(addr)`, `bus.write8(addr, val)`, `bus.consume_pending_cycles()` | Cpu never touches PPU/Timer directly. |
| `Bus` ↔ `Ppu` | `ppu.tick(t_cycles)`, `ppu.read_vram(addr)`, `ppu.read_oam(addr)`, `ppu.write_vram(addr, val)`, `ppu.write_oam(addr, val)`, `ppu.frame_ready` | Bus never reaches into `ppu.screen_output` except at frame present time. |
| `Bus` ↔ `Timer` | `timer.tick(t_cycles)`, `timer.read_div()`, `timer.write_div(value)` | Timer never calls back into Bus. |
| `Bus` ↔ `Cart` | `cart.read_rom(addr)`, `cart.write_rom(addr, val)` (handles MBC register writes), `cart.read_ram(addr)`, `cart.write_ram(addr, val)`, `cart.save_battery(path)` | Cart is the *only* component that owns ROM and external RAM. |
| `Bus` ↔ `Dma` | `dma.start(source_page)`, `dma.tick(t_cycles)`, `dma.is_active()`, `dma.read_source_byte()` | Dma owns the OAM DMA state machine. |
| `Bus` ↔ `Joypad` | `joypad.tick(t_cycles)`, `joypad.read_p1()`, `joypad.write_p1(value)`, `joypad.key_down(key)`, `joypad.key_up(key)` | Joypad is the *only* component the frontend calls into directly (besides Ppu.framebuffer). |

---

## 9. Sources

### Primary documentation
- **[gbdev.io Pan Docs](https://gbdev.io/pandocs/)** — community-maintained, near-definitive GB hardware reference. Memory map, I/O register table, PPU modes, interrupt table, MBC specs. (HIGH confidence, well-cited.)
- **[gbdev.io wiki](https://gbdev.io/wiki)** — Emulator Development FAQ, list of emulators, test ROMs.
- **[Game Boy: Complete Technical Reference (gekkio)](https://gekkio.fi/files/gb-docs/gbctr.pdf)** — gekkio's deep-dive. Authoritative for obscure behaviors (OAM DMA bus conflicts, OAM corruption bug, PPU timing).
- **[The Cycle-Accurate Game Boy Doctor (BGB)](http://bgb.bircd.org/)** — the reference emulator for cycle accuracy. Windows-only.

### Reference emulators (see §2 for per-emulator notes)
- **[SameBoy (LIJI32/SameBoy)](https://github.com/LIJI32/SameBoy)** — *the* high-accuracy C reference.
- **[Mooneye GB (Gekkio/mooneye-gb)](https://github.com/Gekkio/mooneye-gb)** — *the* Rust reference; clarity of design.
- **[Ryp/gb-emu-zig](https://github.com/Ryp/gb-emu-zig)** — closest existing Zig reference.
- **[fengb/fundude](https://github.com/fengb/fundude)** — historical Zig reference.
- **[agentultra/zig8](https://github.com/agentultra/zig8)** — current Zig Chip-8.
- **[Luukdegram/lion](https://github.com/Luukdegram/lion)** — Zig Chip-8 with C-ABI bindings.

### Test ROMs
- **[Blargg's test ROMs](http://gbdev.gg8.se/wiki/articles/Test_Roms)** — `cpu_instrs`, `instr_timing`, `mem_timing`, `dmg_sound`, etc.
- **[Mooneye Test Suite](https://github.com/Gekkio/mooneye-test-suite)** — fine-grained acceptance tests.
- **[Wilbert Pol's test ROMs](https://github.com/wilbertpol/mooneye-gb/tree/master/tests/acceptance)** — merged into Mooneye.
- **[dmg-acid2](https://github.com/mattcurrie/dmg-acid2)** — visual PPU test.

### Zig documentation
- **[ziglang.org documentation](https://ziglang.org/documentation/master/)** — language reference.
- **[Zig learn](https://ziglearn.org/)** — beginner-friendly intro.
- **[Zig guide: comptime](https://zig.guide/language/comptime/)** — how to use `comptime` for code generation.
- **[In-depth: packed structs](https://www.openmymind.net/learning_zig/packed_structs/)** — useful patterns.

### Internal
- [PROJECT.md](../PROJECT.md) — ZigBoy's project requirements and constraints.

---

## 10. Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Standard architecture (CPU/bus/PPU/timer/joypad) | **HIGH** | Consensus across SameBoy, Mooneye, Gambatte, BGB, Ryp, fundude. Pan Docs confirm the memory map. |
| Data flow (one tick) | **HIGH** | SameBoy's `GB_cpu_run` + `GB_run` is the canonical model. Ryp's `consume_pending_cycles` is identical. |
| Component responsibilities | **HIGH** | All 6 reference emulators agree. |
| Build order / MVP slice | **MEDIUM-HIGH** | The "ROM-only → timer → PPU BG → PPU sprites → MBC" order is the standard one. Ryp's commit history (visible in their repo) confirms this is how their emulator grew. |
| Zig-specific patterns | **HIGH** | `packed struct` for registers and MMIO is a known idiom; Ryp is the proof. Comptime opcode tables are textbook. |
| C-ABI interop for SDL2 | **HIGH** | `@cImport` is the documented way. Ryp and Luukdegram both use it. |
| Scalability | **N/A** | A GB emulator is bounded by definition: max 2 MiB ROM, 8 KiB RAM, 1 CPU, 1 PPU, 1 input device. There is no scale problem. |
| Performance | **MEDIUM-HIGH** | Cycle-accurate in Zig should easily hit >60× real-time on a modern desktop. fundude hit 2000% in WASM at 0.6.0; modern Zig 0.14+ is much faster. The bin size of "<5 MB" is realistic given no GC, no runtime, and a small SDL2 surface. |
| Binary size | **MEDIUM** | SDL2 (compiled from C, statically linked) will be the dominant cost (~1–2 MB). The Zig runtime + emulator code should be < 1 MB stripped. v2 audio with miniaudio adds < 100 KB. |

### Gaps to Address
- **PPU OAM corruption bug** — SameBoy's `bitwise_glitch_*` functions are required only for very specific old games (e.g. *Prehistorik Man*). Defer to v2 unless a "must play" ROM needs it.
- **OAM DMA bus conflicts (CGB-specific)** — DMG doesn't have these. Safe to ignore for v1.
- **SGB** — explicitly out of scope per PROJECT.md; no need to research.
- **MBC6, MBC7, HuC1, HuC3, TPP1, Game Boy Camera** — extremely rare; can be added ad-hoc in v2 if a user requests.
- **Exact instruction cycle counts** — the LR35902 cycle table is published in many places, but the corner cases (e.g. the "HALT bug", `EI` delay, conditional `RET` extra cycle) need cross-checking against Mooneye and SameBoy during Phase 1.
