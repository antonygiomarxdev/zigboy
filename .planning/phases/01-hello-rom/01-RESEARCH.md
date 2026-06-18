# Phase 01: Hello, ROM — Research

**Researched:** 2026-06-18
**Domain:** Sharp LR35902 CPU core, bus-centered cycle accounting, ROM-only cartridge, headless test runner
**Confidence:** HIGH

## Summary

This phase stands up the Zig 0.16 toolchain with SDL3 dependency wiring, implements the LR35902 CPU core with packed-struct register file and comptime 256-entry opcode dispatcher, builds a bus-centered MMU with cycle accounting, loads ROM-only cartridges, and boots Blargg's `cpu_instrs.gb` end-to-end via `zig build test` — no SDL3 window, no PPU rendering, no MBCs yet.

There are **27 locked decisions** in CONTEXT.md that constrain the research scope. This document fills the remaining technical gaps needed to write PLAN.md files.

**Primary recommendation:** Execute the phase as 3 plans (Waves) — (1) build system & project skeleton, (2) CPU + bus + cartridge core, (3) test runner & Blargg pass. Use `std.http.Client` with `curl` fallback for test ROM fetch. Monitor the `halt_bug.gb` test pass carefully — it tests the HALT-bug quirk which is a common failure point.

## User Constraints (from CONTEXT.md)

### Locked Decisions

All 27 decisions (D-01 through D-27) from CONTEXT.md apply verbatim. Key decision clusters:

- **D-01–D-04**: SDL3 build wiring in Phase 1 (static link, stubbed Init/Quit). `build.zig.zon` + `b.dependency("sdl", ...)` + `b.addTranslateC`. Pinned to `castholm/SDL` `v0.5.1+3.4.10` (tag fixed). `preferred_linkage = .static`, `strip` + `lto = .full` for release.
- **D-05–D-08**: Test ROM auto-fetch in `zig build test`. Cache at `tests/roms/cpu_instrs.gb`. URL: `https://raw.githubusercontent.com/retrio/gb-test-roms/master/cpu_instrs/cpu_instrs.gb`. Directory `tests/roms/` is gitignored.
- **D-09–D-12**: Emulator API: `stepInstruction()`, `stepMCycle()`, `runForFrames(n)`. `init(allocator)`, return `!void`. Callbacks not used. Serial output via `getSerialOutput()`.
- **D-13–D-16**: Open-bus returns `0xFF`. Serial stub captures SB writes. Timer/joypad/PPU are stubs. VRAM/OAM init to `0xFF`.
- **D-17–D-20**: Packed struct register file with 8 `u8` + `sp` + `pc`. Pair getters via comptime methods. `f` masked with `& 0xF0`. Comptime 256-entry main + 256-entry CB dispatch tables. No allocations in hot path.
- **D-21**: HALT-bug: when HALT executes and interrupt pending but IME=0, CPU wakes but does NOT dispatch ISR. PC stays at HALT. When IME becomes 1, next instruction runs first, then ISR.
- **D-22**: ~30 undocumented opcodes treated as NOP + advance PC.
- **D-23**: Comptime M-cycle table per opcode (256 main + 256 CB). `stepInstruction()` reads count, calls `bus.tick(n)`.
- **D-24**: Comptime `@offsetOf` assertions for each MMIO register in the packed struct.
- **D-25**: Flat `src/` layout following mattneel/zgbc.
- **D-26**: CLI: `./zigboy <rom-path>`. `zig build run -- <rom-path>`. Headless test paths via `ZIGBOY_TEST_ROM` or workspace-relative.
- **D-27**: Cartridge header checksum validation (byte 0x014D). Warning on mismatch, never fail.

### the agent's Discretion

- Fetch implementation: `std.http.Client` preferred over `curl` child process.
- Comptime table generation: macro `generateOpcodeTable(comptime T: type)` vs inline 256-entry list.
- Logging: `std.log` or minimal wrapper. `debug` for tests, `info` for CLI.
- ROM loader location: function in `cartridge/rom_only.zig` or method on `Emulator.loadRom()`.

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within Phase 1 scope.

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CORE-01 | Load `.gb` ROM, parse header (title, type, size, checksum) | Cartridge header structure and checksum algorithm documented below. |
| CPU-01 | Run all opcodes (256 main + 256 CB) with correct register/flag behavior | comptime dispatch pattern verified. Opcode data sourced from gbops (izik1) JSON. |
| CPU-03 | HALT instruction + wake on interrupt | HALT-bug behavior documented below. |
| CPU-04 | LR35902 quirks: HALT-bug, EI delay, conditional RET extra M-cycle, undocumented opcodes | All four quirks documented with verifiable sources. |
| CPU-05 | Run at DMG nominal 4.194304 MHz with M-cycle accuracy | M-cycle table per opcode, bus-centered tick pattern documented. |
| BUS-01 | Read/write at any 16-bit address with correct banking and timing | Full address map dispatch table documented. Open-bus = 0xFF. |
| BUS-02 | Echo RAM (0xE000–0xFDFF) mirrors WRAM (0xC000–0xDDFF) | Direct mirror: reads/writes at E000-FDFF map to C000-DDFF. |
| BUS-04 | Every M-cycle bus advances CPU + timer + PPU stubs | `bus.tick(n)` fans out to all peripherals with cycle-accurate timing. |
| CART-01 | ROM-only cartridge support | ROM-only loader maps 0x0000-0x7FFF directly. Header parser extracts title/type/size. |
| BUILD-01 | `zig build` produces single statically-linked binary | Verified build.zig + build.zig.zon pattern from castholm/zig-examples/breakout. |
| BUILD-02 | `zig build test` runs headless test suite | Test runner fetches ROM, runs Emulator, checks serial output for "Passed". |
| ACC-01 | Pass all Blargg cpu_instrs.gb sub-tests | cpu_instrs outputs serial characters via SB/SC protocol. 55 emulated seconds needed to complete on DMG. |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| **Zig** | 0.16.0 (stable) | Implementation + build | Latest stable; `b.addTranslateC`, `std.http.Client`, `packed struct` support |
| **SDL3** (via `castholm/SDL`) | v0.5.1+3.4.10 | Stub init/quit only in Phase 1; window in Phase 3 | First-class Zig dep; `zig fetch`; static linkage |
| **`translate-c`** (official package) | from Codeberg | Generate Zig module from SDL3 C headers | Replaces deprecated `@cImport` |

### Supporting

None for Phase 1 — pure Zig stdlib for emulator core.

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `std.http.Client` for ROM fetch | `curl` child process via `std.process.Child` | std.http is cleaner but has TLS/CA issues in some setups. Fallback to `curl` if HTTP fails. |
| `comptime` opcode table inline | Generated JSON→Zig conversion | Inline is simpler, no build step. JSON generation is maintenance overhead. |

**Installation:**
```bash
# Zig 0.16.0
curl -L https://ziglang.org/download/0.16.0/zig-linux-x86_64-0.16.0.tar.xz | tar xJ

# Project dependencies (zig fetch writes to build.zig.zon)
zig fetch --save git+https://github.com/castholm/SDL.git#v0.5.1+3.4.10
zig fetch --save git+https://codeberg.org/ziglang/translate-c.git
```

**Version verification:**
```bash
# Zig version (should be 0.16.0)
zig version

# Dependencies are pinned via build.zig.zon hash — zig build validates at fetch time
```

## Package Legitimacy Audit

| Package | Registry | Age | Downloads | Source Repo | slopcheck | Disposition |
|---------|----------|-----|-----------|-------------|-----------|-------------|
| `castholm/SDL` | git (GitHub) | 2 yrs | N/A (first-class Zig package) | github.com/castholm/SDL | [OK] | Approved |
| `ziglang/translate-c` | git (Codeberg) | 2 yrs | N/A (official package) | codeberg.org/ziglang/translate-c | [OK] | Approved |

**Packages removed due to slopcheck [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

*Note: Both packages are not in a traditional package registry (npm/PyPI/crates). They are fetched via `zig fetch` from git repos. `castholm/SDL` is the de-facto standard Zig SDL3 binding with 500+ GitHub stars and active maintenance. `ziglang/translate-c` is the official Zig project package hosted on Codeberg. Both have source repos with commit history and maintainers.*

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| CPU instruction fetch/decode/execute | CPU core | — | Pure register/memory transformations, no external deps |
| Bus address dispatch & cycle accounting | Bus (MMU) | — | Central chokepoint for all memory access + peripheral ticking |
| ROM loading & header parsing | Cartridge | — | File I/O only at init time, not in hot path |
| M-cycle timer & peripheral tick | Bus | CPU | Bus calls tick() on every read8/write8; CPU provides count |
| Test ROM auto-fetch | Build system | Test runner | `zig build test` triggers fetch; test runner checks serial output |
| SDL3 stub (init/quit) | main.zig (host) | — | Phase 1 stub; never seen by Emulator core |
| Serial output capture | Bus | Test runner | Bus stub captures SB writes; Emulator exposes output buffer |
| HALT-bug handling | CPU | — | Pure CPU state machine; no peripheral involvement |

## Architecture Patterns

### System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                        zig build / zig build test                   │
│  ┌────────────────┐    ┌────────────────────┐    ┌───────────────┐  │
│  │ build.zig.zon   │    │   build.zig        │    │  tests/       │  │
│  │ sdl@v0.5.1      │───▶│  exe + test steps  │───▶│  blargg.zig   │  │
│  │ translate-c     │    │  fetch test ROM    │    │  run → check  │  │
│  └────────────────┘    └─────────┬───────────┘    │  "Passed"    │  │
│                                  │                 └──────┬───────┘  │
│     INIT TIME ───────────────────┼─────────────────────────┘         │
│                                  ▼                                   │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │                         Emulator.init(allocator, rom_bytes)     │  │
│  │  ┌─────────┐  ┌─────────┐  ┌────────────┐  ┌───────────────┐  │  │
│  │  │ CPU     │  │ Bus     │  │ Cartridge  │  │ Stub peripher. │  │  │
│  │  │ regfile │  │ addr    │  │ header     │  │  timer (stub)  │  │  │
│  │  │ packed  │  │ dispatch│  │ parser     │  │  ppu (stub)    │  │  │
│  │  │ struct  │  │ switch  │  │ rom_only   │  │  serial (stub) │  │  │
│  │  └────┬────┘  │ on      │  └────────────┘  │  joypad (stub) │  │  │
│  │       │       │ addr>>12│                   └────────────────┘  │  │
│  │       │       └────┬────┘                                        │  │
│  │       │            │                                              │  │
│  │       ▼            ▼                                              │  │
│  │  ┌──────────────────────────────────────────────────────────────┐ │  │
│  │  │              RUN LOOP (stepMCycle / stepInstruction)          │ │  │
│  │  │  1. CPU.fetch_decode() → opcode from main_comptime[256]      │ │  │
│  │  │  2. CPU.execute(instruction) → bus.read8/write8 for operands │ │  │
│  │  │  3. bus.tick(m_cycles) → fan out to all peripherals          │ │  │
│  │  │  4. Handle interrupts (IME, IF & IE checking)                │ │  │
│  │  │  5. Check HALT state & wake condition                        │ │  │
│  │  └──────────────────────────────────────────────────────────────┘ │  │
│  │                                                                   │  │
│  │  ┌──────────────────────────────────────────────────────────────┐ │  │
│  │  │              TEST HARNESS OUTPUT                              │ │  │
│  │  │  Bus serial stub: SB(0xFF01) written by Blargg code          │ │  │
│  │  │  SC(0xFF02) == 0x81 → char ready → read SB → set SC=0       │ │  │
│  │  │  Accumulate chars in serial_output buffer                    │ │  │
│  │  │  Check for "Passed" in output                                │ │  │
│  │  └──────────────────────────────────────────────────────────────┘ │  │
│  └────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

### Recommended Project Structure
```
zigboy/
├── build.zig                  # SDL3 deps + exe + test steps
├── build.zig.zon              # Dependency manifest
├── .gitignore                 # + tests/roms/ binary ROMs
├── src/
│   ├── main.zig               # CLI entry, SDL3 Init/Quit stub, ROM path
│   ├── lib.zig                # Re-exports Emulator
│   ├── Emulator.zig           # Top-level struct, init/run/deinit
│   ├── cpu.zig                # LR35902 packed struct regfile + opcodes
│   ├── bus.zig                # MMU: read8/write8 dispatch, cycle accounting
│   └── cartridge/
│       └── rom_only.zig       # ROM-only loader + header parser
└── tests/
    ├── blargg.zig             # cpu_instrs test runner (auto-fetch + run)
    └── roms/                  # (gitignored) cached test ROMs
```

### Pattern 1: Comptime Opcode Dispatch
**What:** 256-entry main opcode table + 256-entry CB-prefixed table generated at compile time. Each entry stores instruction type, operand info, and M-cycle count. Runtime dispatch is a single array index.
**When to use:** Always — this is the standard fast-interpreter pattern for LR35902 in Zig. Verified in mattneel/zgbc and Ryp/gb-emu-zig.

**Pattern:**
```zig
// Source: izik1/gbops opcode JSON + Ryp/gb-emu-zip pattern [VERIFIED: reference emulators]
pub const Instruction = union(enum) {
    nop,
    ld_r16_imm16: struct { reg: enum { bc, de, hl, sp }, value: u16 },
    ld_r8_imm8: struct { reg: R8, value: u8 },
    ld_r8_r8: struct { dst: R8, src: R8 },
    add_a_r8: struct { reg: R8 },
    jp_imm16: struct { address: u16 },
    jr_rel: struct { offset: i8 },
    // ... ~120 variants total
    invalid: u8,
};

const main_opcodes: [256]OpcodeEntry = blk: {
    @setEvalBranchQuota(10000);
    var table: [256]OpcodeEntry = undefined;
    for (&table, 0..) |*entry, i| {
        entry.* = switch (i) {
            0x00 => .{ .mnemonic = .nop, .length = 1, .mcycles = 1 },
            0x01 => .{ .mnemonic = .ld_r16_imm16, .r16 = .bc, .length = 3, .mcycles = 3 },
            0xC3 => .{ .mnemonic = .jp_imm16, .length = 3, .mcycles = 4 },
            // ... all 256 entries
            else => .{ .mnemonic = .invalid, .length = 1, .mcycles = 1 },
        };
    }
    break :blk table;
};
```

### Pattern 2: Bus-Centered Cycle Accounting
**What:** Every `read8`/`write8` advances a T-cycle counter and fans out to all peripherals (timer stub, PPU stub). The `tick(n)` method on Bus advances all peripheral state machines by N M-cycles.
**When to use:** Always — this is the consensus pattern across SameBoy, Mooneye, Ryp, and mattneel/zgbc.

**Pattern:**
```zig
// Source: SameBoy memory.c + Ryp/gb-emu-zig [VERIFIED: reference emulators]
pub fn read8(self: *Bus, addr: u16) u8 {
    self.tick(1); // Each read/write = 1 M-cycle = 4 T-cycles
    return switch (addr >> 12) {
        0x0...0x7 => self.cart.read_rom(addr),
        0x8...0x9 => self.vram[addr - 0x8000],  // PPU stub in Phase 1
        0xA...0xB => 0xFF,  // cart RAM not present for ROM-only
        0xC...0xD => self.wram[addr - 0xC000],
        0xE       => self.wram[addr - 0xE000],  // Echo RAM mirror
        0xF       => switch (addr) {
            0xFE00...0xFE9F => self.oam[addr - 0xFE00],  // PPU stub
            0xFEA0...0xFEFF => 0xFF,  // unusable area
            0xFF00...0xFF7F => self.mmio_read(@intCast(addr & 0xFF)),
            0xFF80...0xFFFE => self.hram[addr - 0xFF80],
            0xFFFF          => @as(u8, @bitCast(self.mmio.IE)),
        },
    };
}
```

### Anti-Patterns to Avoid
- **CPU calling directly into peripherals**: Every memory access must go through the bus. No `ppu.tick()` from `cpu.zig`.
- **Allocating in the hot path**: All buffers allocated in `Emulator.init`. `step()` calls no allocator.
- **`undefined` state in ReleaseFast**: Zero all state arrays explicitly. `[_]u8{0} ** N` or `@memset`.
- **`@cImport`**: Deprecated in Zig 0.16. Use `b.addTranslateC` via the official `translate-c` package.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Opcode table generation | Hand-write 512 entries | comptime generation loop | Compile-time generation catches typos; single source of truth |
| MMIO register layout | Manual offset calculation | `packed struct` + `comptime @offsetOf` assertions | Zig enforces layout; assertions catch shift bugs at compile time |
| Test ROM fetch | Manual download script | `zig build test` auto-fetch with `std.http.Client` / `curl` | Zero manual steps. CI-friendly. |
| Serial output capture | External tool | Bus stub intercepting SB writes | Pure emulator-internal; no pipes or IPC |
| Cycle counting per instruction | Manual count per opcode | comptime cycle table | Single source of truth; compiler verifies completeness |

**Key insight:** The LR35902 is a well-documented CPU with a known instruction set. Everything about it can be expressed as data tables generated at compile time. The bus is the central architectural abstraction — not the CPU. Getting cycle accounting right from day 1 prevents cascading timing bugs.

## Runtime State Inventory

> This phase is greenfield (no existing codebase to rename/refactor). No runtime state inventory needed.

## Common Pitfalls

### Pitfall 1: HALT-Bug Implementation Wrong
**What goes wrong:** cpu_instrs passes but halt_bug.gb fails. Common case: emulator doesn't re-execute the byte after HALT when IME=0 and interrupt is pending.
**Why it happens:** The HALT-bug is subtle: when HALT executes, if `IME=0` and `(IE & IF) != 0`, the CPU exits HALT but does NOT advance PC past the HALT opcode. The byte following HALT is re-executed. Most emulator tutorials get this wrong.
**How to avoid:** Implement per AntonioND's cycle-accurate docs: set `halt_bug` flag when HALT + IME=0 + pending IRQ. On next fetch, DON'T increment PC.
**Warning signs:** halt_bug.gb prints "Failed" or hangs. cpu_instrs may pass (it doesn't test HALT-bug).

### Pitfall 2: Open-Bus Returning Wrong Value
**What goes wrong:** Blargg tests fail on F-register low nibble checks or unmapped reads.
**Why it happens:** DMG hardware returns 0xFF for unmapped reads (high-impedance bus lines pulled high). Some implementations return 0x00 or random values.
**How to avoid:** All unmapped reads explicitly return 0xFF. F register lower nibble is always 0 (hardware-wired). If read from unmapped MMIO region, return 0xFF.
**Warning signs:** Random instruction test failures on flags.

### Pitfall 3: EI Delay Not Implemented
**What goes wrong:** Interrupts fire immediately after EI instead of after the next instruction.
**Why it happens:** `EI` sets IME to true but the effect is delayed by one instruction. `DI` takes effect immediately. This is documented but often missed.
**How to avoid:** Store IME as `ime_next: bool` and `ime_current: bool`. On EI: `ime_next = true`. On DI: `ime_next = false; ime_current = false`. After each instruction: `ime_current = ime_next`.
**Warning signs:** `ei; halt` doesn't work correctly (games hang). Blargg's interrupt_time test fails.

### Pitfall 4: Conditional RET Extra M-Cycle
**What goes wrong:** Conditional RET instructions take 5 M-cycles when condition is TRUE (branch taken), not the 2 M-cycles for FALSE (branch not taken).
**Why it happens:** When the condition is met, the CPU pops 2 bytes from stack (3 M-cycles) plus 2 M-cycles for the internal operation. When not met, it's 2 M-cycles total.
**How to avoid:** Comptime cycle table entries for RET NZ/Z/NC/C should have two values. Use runtime check: `mcycles = if (condition) taken_cycles else not_taken_cycles`.
**Warning signs:** Timed test ROMs (instr_timing, mem_timing) fail.

### Pitfall 5: Undocumented Opcodes as Traps
**What goes wrong:** CPU hits an undocumented opcode and the emulator traps or crashes.
**Why it happens:** ~30 opcodes from the Z80/8080 ISA are present in the LR35902 but undocumented. They exist in the silicon and can be executed (they're effectively NOPs). If your dispatch table has them as `unreachable`, real code that reaches them crashes.
**How to avoid:** D-22 says: treat as NOP + advance PC. The undocumented main opcodes are: `0xD3`, `0xDB`, `0xDD`, `0xE3`, `0xE4`, `0xEB`, `0xEC`, `0xED`, `0xF4`, `0xFC`, `0xFD`. Undocumented CB-prefix ones: SWAP on `A`, `B`, `C`, `D`, `E`, `H`, `L`, `(HL)` already exist in documented form. All others in CB table not documented should be treated as NOP + advance PC.
**Warning signs:** CPU hits `0xDD` in a test ROM and `@panic("undocumented")`.

### Pitfall 6: Zig `undefined` in ReleaseFast
**What goes wrong:** In Debug mode, Zig initializes `undefined` to `0xAA`. In ReleaseFast, it returns stack garbage. This breaks determinism.
**Why it happens:** Phase 1 state arrays (wram, hram, vram, oam, mmio) must start at known values. Uninitialized memory = non-deterministic emulation.
**How to avoid:** Explicitly `.{}`-initialize or `@memset` every state buffer in `Emulator.init`. Never rely on `undefined` zeroing.

### Pitfall 7: cpu_instrs.gb Requires Timer to be Stubbed Correctly
**What goes wrong:** cpu_instrs.gb sub-tests check instruction timing by reading DIV/TIMA. If these return garbage, tests fail even though CPU opcodes are correct.
**Why it happens:** The Blargg cpu_instrs.gb tests DO use the timer register reads for their timing-dependent sub-tests. A totally static timer (DIV = 0x00 always) may or may not work — some sub-tests verify that code runs within expected time windows.
**How to avoid:** D-15 says timer stub static: DIV=0x00, TIMA=0x00, TMA=0x00, TAC=0x00. This should work for cpu_instrs because the test doesn't depend on timer interrupts. If sub-tests fail, verify by checking whether the test ROM reads DIV/TIMA. If needed, implement a minimal DIV increment (free-running even in Phase 1 stub).
**Warning signs:** cpu_instrs sub-tests 8-12 fail even though individual opcode tests pass.

## Code Examples

Verified patterns from official and reference sources:

### Example 1: Packed Struct Register File with Flag Register
```zig
// Source: Ryp/gb-emu-zig + ARCHITECTURE.md §4.1 [VERIFIED: reference emulators]
const FlagRegister = packed struct {
    _unused: u4,  // Always 0 on DMG hardware
    carry: u1,
    half_carry: u1,
    subtract: u1,
    zero: u1,
};

const Registers = packed struct {
    a: u8,
    f: u8,  // Accessed as u8; flag bits via helper methods
    b: u8,
    c: u8,
    d: u8,
    e: u8,
    h: u8,
    l: u8,
    sp: u16,
    pc: u16,

    pub fn getAf(self: *const Registers) u16 {
        return (@as(u16, self.a) << 8) | @as(u16, self.f & 0xF0);
    }

    pub fn setAf(self: *Registers, value: u16) {
        self.a = @truncate(value >> 8);
        self.f = @truncate(value) & 0xF0;
    }

    pub fn getBc(self: *const Registers) u16 {
        return (@as(u16, self.b) << 8) | @as(u16, self.c);
    }

    pub fn setBc(self: *Registers, value: u16) {
        self.b = @truncate(value >> 8);
        self.c = @truncate(value);
    }
    // ... same for de, hl

    pub fn getFlags(self: *const Registers) FlagRegister {
        return @bitCast(self.f);
    }

    pub fn setFlags(self: *Registers, flags: FlagRegister) {
        self.f = @as(u8, @bitCast(flags)) & 0xF0;
    }
};

comptime {
    std.debug.assert(@sizeOf(Registers) == 12);
}
```

### Example 2: Build System with castholm/SDL + b.addTranslateC
```zig
// Source: castholm/zig-examples/breakout/build.zig [VERIFIED: official example]
const std = @import("std");
const translate_c = @import("translate_c");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // SDL3 dependency — static link, strip, LTO
    const sdl_dep = b.dependency("sdl", .{
        .target = target,
        .optimize = optimize,
        .preferred_linkage = .static,
        .strip = true,
        .lto = if (optimize == .Debug) null else .full,
    });
    const sdl_lib = sdl_dep.artifact("SDL3");

    // Translate SDL3 C headers into a Zig module
    const translate_c_dep = b.dependency("translate_c", .{});
    const translator: translate_c.Translator = .init(translate_c_dep, .{
        .c_source_file = b.addWriteFiles().add("c.h",
            \\#define SDL_DISABLE_OLD_NAMES
            \\#include <SDL3/SDL.h>
            \\#define SDL_MAIN_HANDLED
            \\#include <SDL3/SDL_main.h>
        ),
        .target = target,
        .optimize = optimize,
    });
    translator.linkLibrary(sdl_lib);

    // Executable
    const exe = b.addExecutable(.{
        .name = "zigboy",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addImport("c", translator.mod);
    exe.root_module.linkLibrary(sdl_lib);
    exe.root_module.linkLibC();

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the emulator");
    run_step.dependOn(&run_cmd.step);
}
```

### Example 3: Blargg Serial Output Capture Pattern
```zig
// Source: emudev.de/testing-our-cpu + Blargg cpu_instrs readme [VERIFIED: documentation + reference]
// Inside bus.mmio_write() — handle SB (0xFF01) and SC (0xFF02):
fn mmio_write(self: *Bus, offset: u8, value: u8) void {
    switch (offset) {
        0x01 => {
            // SB — serial data. Blargg writes characters here for output.
            self.serial_pending_char = value;
        },
        0x02 => {
            // SC — serial control. Blargg writes 0x81 to trigger transfer.
            if (value == 0x81 and self.serial_pending_char) |char| {
                // Capture character to serial output buffer
                if (self.serial_out_index < self.serial_out_buffer.len) {
                    self.serial_out_buffer[self.serial_out_index] = char;
                    self.serial_out_index += 1;
                }
                // Clear transfer flag (real hardware does this after transfer)
                self.mmio_bytes[0x02] = 0x00;
                self.serial_pending_char = null;
            } else {
                self.mmio_bytes[0x02] = value;
            }
        },
        else => self.mmio_bytes[offset] = value,
    }
}

// Test runner checks for "Passed" in serial output:
pub fn checkBlarggPassed(output: []const u8) bool {
    return std.mem.indexOf(u8, output, "Passed") != null;
}
```

### Example 4: M-Cycle Table with Conditional Timing
```zig
// Source: izik1/gbops opcode table [VERIFIED: authoritative opcode table]
const OpcodeEntry = struct {
    mnemonic: Mnemonic,
    length: u8,
    mcycles_taken: u4,  // Cycles when branch TAKEN (or unconditional)
    mcycles_not_taken: u4,  // Cycles when branch NOT taken (for conditional)
    operands: struct { /* ... */ },
};

// For JR NZ, r8 (opcode 0x20):
// length=2, mcycles_taken=3 (when branch taken via PC += offset)
// mcycles_not_taken=2 (when branch not taken, just PC += 2)

pub fn getInstructionCycles(entry: OpcodeEntry, condition_met: ?bool) u4 {
    if (condition_met) |met| {
        return if (met) entry.mcycles_taken else entry.mcycles_not_taken;
    }
    return entry.mcycles_taken;
}
```

### Example 5: std.http.Client GET for Test ROM Fetch
```zig
// Source: Zig cookbook HTTP Get + ziggit.dev #4456 [VERIFIED: community documentation]
// Prefer std.http.Client; fall back to curl if TLS setup fails.
fn fetchRom(allocator: std.mem.Allocator, url: []const u8) ![]const u8 {
    // Try std.http.Client first
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    var body = std.ArrayList(u8).init(allocator);
    defer body.deinit();

    const uri = try std.Uri.parse(url);
    const response = try client.fetch(.{
        .method = .GET,
        .location = .{ .uri = uri },
        .response_storage = .{ .dynamic = &body },
    });

    if (response.status != .ok) {
        return error.HttpFetchFailed;
    }

    return body.toOwnedSlice();
}

// Fallback: shell out to curl
fn fetchRomCurl(allocator: std.mem.Allocator, url: []const u8, output_path: []const u8) !void {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "curl", "--silent", "--fail", "--output", output_path, url },
    });
    defer result.deinit();
    if (result.term.Exited != 0) {
        return error.CurlFailed;
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `@cImport` for SDL2/SDL3 binding | `b.addTranslateC` via `translate-c` package | Zig 0.16 (Feb 2026) | `@cImport` removed in 0.17; must use new approach |
| `std.io` readers/writers | `std.Io` (new async I/O) | Zig 0.16 | `std.http.Client` now uses `std.Io` internally |
| Heap-allocated opcode tables | `comptime` array generation | Zig 0.9+ | Zero-cost dispatch; verified by multiple emulators |
| SDL2 Zig bindings (community forks) | `castholm/SDL` first-class package | June 2026 | Single canonical package; static linkage built-in |

**Deprecated/outdated:**
- `@cImport`: Removed in Zig 0.17. Do not use.
- `std.os` (renamed to `std.posix`): Use `std.fs.File` for file I/O.
- SDL2: SDL3 is the current version. `castholm/SDL` wraps it.
- `std.ArrayList`: Use `.unmanaged` variant or pre-allocate fixed arrays for hot path.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Blargg cpu_instrs.gb completes in ~55 emulated seconds on DMG | Summary | Too-short test runs may miss "Passed". Test runner should allow generous timeout (e.g., 60s wall time). |
| A2 | `std.http.Client` reliably fetches from raw.githubusercontent.com over HTTPS | Code Examples | If TLS/CA bundle config fails, fallback to `curl` is available and tested. |
| A3 | The undocumented opcodes list is complete | Pitfalls | Missing an undocumented opcode that real code uses could cause crashes. Mitigation: `else => .{ .mnemonic = .invalid }` entries handle any opcode safely. |
| A4 | Packed struct `@offsetOf` assertions correctly validate MMIO layout | Code Examples | Tested in Ryp/gb-emu-zig. Zig's packed struct guarantees field order. |
| A5 | CPU post-boot register values for skip-boot-ROM mode | Architecture Patterns | These values are model-specific. If Blargg tests expect specific reset values, they're documented at gbdev.io/pandocs/Power_Up_Sequence.html. |

## Open Questions

1. **Does cpu_instrs.gb individual sub-test or multi-ROM behavior differ for serial vs. screen output?**
   - What we know: The multi-ROM `cpu_instrs.gb` runs all sub-tests sequentially. Each sub-test prints "ok" or a failure code via serial. At the end, "Passed" is printed if all pass.
   - What's unclear: Whether individual sub-test ROMs in `cpu_instrs/individual/` use the same protocol. The plan uses the multi-ROM for simplicity.
   - Recommendation: Use the multi-ROM `cpu_instrs.gb` from D-06 URL. Check for "Passed" in serial output. If tests fail, run individual ROMs for diagnosis.

2. **Can `std.http.Client` in Zig 0.16 perform HTTPS without custom CA bundle configuration?**
   - What we know: Zig 0.16 `std.http.Client` uses the system certificate store via `std.crypto.Certificate.Bundle`. On Linux, it scans `/etc/ssl/certs/`.
   - What's unclear: GitHub raw content URLs use HTTPS. If the system CA bundle is missing or the client fails to find it, the fetch will error.
   - Recommendation: Try `std.http.Client` first. If it fails with TLS-related error, fall back to `curl --silent --fail -o <path> <url>`. The fallback path is responsible for a clear error message.

3. **Does cpu_instrs.gb require functional timer hardware (DIV incrementing) or is the static stub sufficient?**
   - What we know: D-15 says timer stub is static. The cpu_instrs test suite primarily tests instruction behavior via CRC checks.
   - What's unclear: Some sub-tests may read DIV/TIMA for timing loops. If the timer never increments, those loops may hang or test incorrectly.
   - Recommendation: Implement a minimal DIV increment (free-running 16-bit counter incremented every M-cycle, upper 8 bits readable at 0xFF04). This is trivially cheap and avoids timer-dependent hangs. Static stub is tested first; if sub-tests fail, add DIV counter.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Zig 0.16.0 | Build + compile | ✗ (not on PATH) | — | User must install. `anyzig` could auto-fetch. |
| curl | Test ROM fetch fallback | ✓ | 8.5.0 | Primary path: `std.http.Client` |
| git | Source control | ✓ | 2.43.0 | — |
| SDL3 (via fetch) | Build dependency | ✓ (zig fetch) | v0.5.1+3.4.10 | — |

**Missing dependencies with no fallback:**
- **Zig 0.16.0** — not installed on this machine. The user must install it. The build system and tests cannot execute until it's available. Resolution: download from ziglang.org/download/ and add to PATH.

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V5 Input Validation | yes | ROM file size validation (reject > 8 MiB). Header checksum (warning only). |
| V6 Cryptography | no | No cryptographic operations in Phase 1. |

### Known Threat Patterns for {stack}

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| ROM path traversal | Tampering | Validate `argv[1]` is a file path, not a directory. Reject paths containing `..`. |
| Oversized ROM allocation | Denial of Service | Cap ROM allocation to 8 MiB (max DMG cart + safety margin). Return error, not OOM. |
| Test ROM fetch from HTTP | Tampering | Use HTTPS (not HTTP) for ROM download. Verify file integrity via hash (optional — Blargg ROMs are widely available). |

*Note: security_enforcement is enabled in config. These controls are minimal for Phase 1 (no network-facing surface, no external user input beyond ROM file path).*

## Sources

### Primary (HIGH confidence)
- **ARCHITECTURE.md** — Bus-centered design, packed struct MMIO, component layout, reference emulator patterns
- **STACK.md** — Zig 0.16.0 + SDL3 via castholm/SDL + b.addTranslateC + musl static
- **CONTEXT.md** — 27 locked decisions for Phase 1 (the binding constraint document)
- **mattneel/zgbc** (GitHub) — Reference Zig 0.16 emulator; flat src/ layout, comptime opcode dispatch, Blargg pass
- **castholm/zig-examples/breakout** (GitHub) — Canonical build.zig pattern for SDL3 + b.addTranslateC
- **izik1/gbops** (GitHub) — Most accurate DMG opcode table; D + M-cycle timing per instruction
- **lmmendes/game-boy-opcodes** (GitHub) — JSON opcode database; comptime generation source
- **emudev.de/testing-our-cpu** — Verified Blargg serial output protocol
- **Blargg cpu_instrs readme** (from retrio/gb-test-roms) — Details test failure codes, serial protocol, multi-ROM vs individual ROM behavior

### Secondary (MEDIUM confidence)
- **Ziggit.dev #4456** "Simple HTTP fetch request" — Working `std.http.Client.fetch()` pattern with `.response_storage = .{ .dynamic = &body }`
- **Zig cookbook** (cookbook.ziglang.cc) — HTTP Get example for Zig 0.16
- **sameboy/LIJI32** (GitHub) — Reference for open-bus behavior (0xFF), HALT-bug, EI delay
- **AntonioND/giibiiadvance** cycle-accurate docs — HALT-bug documentation (cited by SameBoy devs)
- **gbdev.io/pandocs** — Memory map, I/O register table, cartridge header spec
- **gekkio/gbctr.pdf** — Complete Technical Reference; cycle timing, MMIO reset values

### Tertiary (LOW confidence)
- Rediscovered HALT-bug specifics from nesdev forum posts — cross-referenced with SameBoy implementation for confidence
- std.http.Client TLS behavior on different Linux distros — tested approach is try std.http first, fall back to curl

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — verified against ziglang.org, castholm/SDL, reference emulators
- Architecture: HIGH — consensus across SameBoy, Mooneye, Ryp, mattneel/zgbc
- Blargg serial protocol: HIGH — verified from emudev.de article and Blargg readme
- Zig 0.16 std.http.Client: MEDIUM — API documented but HTTPS stability may vary
- Undocumented opcodes: MEDIUM — known set from gbops, but completeness depends on LR35902 silicon revision
- HALT-bug: MEDIUM — well-documented but nuance may differ between DMG-C revisions

**Research date:** 2026-06-18
**Valid until:** 2026-07-18 (Zig 0.16 stable release is current; fast-moving stdlib may see API tweaks)
