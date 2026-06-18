# Phase 01: Hello, ROM - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-18
**Phase:** 01-hello-rom
**Areas discussed:** SDL3 wiring, Test ROM fetch, Emulator API, Bus stub behavior, CPU register layout

---

## SDL3 Wiring

| Option | Description | Selected |
|--------|-------------|----------|
| Sí, en Fase 1 | Connect castholm/SDL via b.dependency in Fase 1. main.zig stub with SDL_Init/SDL_Quit only | ✓ |
| No, diferir a Fase 3 | Minimal build.zig in Fase 1, SDL3 wiring in Fase 3 only | |
| Solo en build, sin código | build.zig declares SDL3 dep, but no .zig imports it | |

| Option | Description | Selected |
|--------|-------------|----------|
| Init + Quit no-op | SDL_Init(SDL_INIT_VIDEO) at start, SDL_Quit() at end, no window | ✓ |
| Init + headless flag | Detect --headless CLI flag to skip SDL_Init | |
| Sin stub, archivo placeholder | main.zig empty, SDL lib linked but unused | |

| Option | Description | Selected |
|--------|-------------|----------|
| Pinear tag v0.5.1+3.4.10 | Exact tag, zero surprises, manual updates | ✓ |
| Latest con hash commit | HEAD of castholm/SDL, auto-receive bugfixes | |
| Tag + update plan | Tagged but allow zig build --update updates | |

| Option | Description | Selected |
|--------|-------------|----------|
| Static (preferred_linkage = .static) | Single static binary, zero runtime deps | ✓ |
| Dynamic | libSDL3.so separate, user must install it | |

**User's choice:** Sí en Fase 1, Init/Quit no-op, tag v0.5.1+3.4.10, static linkage
**Notes:** User is learning emulation. Receptive to recommendations.

---

## Test ROM Fetch

| Option | Description | Selected |
|--------|-------------|----------|
| Fetch + cache local | Auto-download cpu_instrs.gb from URL if missing in tests/roms/ | ✓ |
| Manual + README | User downloads ROM manually, README explains how | |
| Solo unit tests, ROM integration aparte | Unit tests only in Fase 1, integration suite separate | |

| Option | Description | Selected |
|--------|-------------|----------|
| retrio/gb-test-roms | raw.githubusercontent.com URL, maintained repo | ✓ |
| Otra URL | Different source repo | |
| Solo documentar | No URL, ask user where ROM is on first run | |

| Option | Description | Selected |
|--------|-------------|----------|
| tests/roms/ gitignored | local cache, visible path, gitignored | ✓ |
| Zig cache global | .zig-cache/roms/, hidden but deletable | |
| XDG cache dir | ~/.cache/zigboy/roms/, persistent, less portable | |

| Option | Description | Selected |
|--------|-------------|----------|
| Auto-fetch en test | zig build test auto-downloads if missing | ✓ |
| Comando explícito | Separate zig build fetch-test-roms command | |
| Ambos: default + override | Auto-fetch with --no-auto-fetch override | |

**User's choice:** Fetch + cache, retrio URL, tests/roms/ gitignored, auto-fetch in test
**Notes:** Accepted all recommendations.

---

## Emulator API

| Option | Description | Selected |
|--------|-------------|----------|
| stepInstruction() | Single-opcode granularity, simple for most tests | |
| stepMCycle() | M-cycle primitive, more hardware-faithful | |
| Ambos: high-level + low-level | stepInstruction(), stepMCycle(), runForFrames(n) all available | ✓ |

| Option | Description | Selected |
|--------|-------------|----------|
| init(allocator) | Caller provides std.mem.Allocator, standard Zig 0.16 pattern | ✓ |
| init con arena interno | Emulator manages internal arena, caller doesn't worry | |
| init() sin allocator (fixed-size) | All state fixed-size, zero allocations, max speed | |

| Option | Description | Selected |
|--------|-------------|----------|
| try! con error union | Step methods return !void, errors are fatal, try-propagation | ✓ |
| Bool state, no errors | Errors logged or accumulated in last_error field, keep running | |
| Error union selectivo | Non-fatal errors (undocumented opcode) silently NOP, only real errors propagate | |

| Option | Description | Selected |
|--------|-------------|----------|
| Funciones getter explícitas | getFrameBuffer() -> *[160*144]u8, setButtonState(Btn, bool) | ✓ |
| Struct público EmulatorState | Pub state field, caller reads/writes directly | |
| Signals/eventos (vtable) | vtable + callbacks, comptime generics | |

**User's choice:** All three granularity methods, init(allocator), !void errors, explicit getters
**Notes:** User chose full flexibility (all three stepping methods) rather than single primitive.

---

## Bus Stub Behavior

| Option | Description | Selected |
|--------|-------------|----------|
| 0xFF (DMG real) | Unmapped reads return 0xFF, matches real hardware and Blargg expectation | ✓ |
| 0x00 (easier debug) | Unmapped reads return 0x00, easier to spot in logs | |
| Tracking del último valor | Returns last bus-written value, most accurate but overkill for P1 | |

| Option | Description | Selected |
|--------|-------------|----------|
| Stub completo de serial+joypad | Serial captures SB bytes for Blargg output; Joypad P1=0xCF | ✓ |
| Solo lo mínimo | SB=0xFF, SC=0x00, P1=0xCF initial, no capture | |
| Hook para tests | Expose serial_output: [256]u8 buffer for test harness | |

| Option | Description | Selected |
|--------|-------------|----------|
| Stub estático | DIV=0, TIMA=0, TMA=0, TAC=0, no increments, no interrupts | ✓ |
| Tiny timer funcional | DIV increments at 16384 Hz, but no TIMA/TMA/TAC | |
| Timer completo ya | Full timer impl (DIV, TIMA, TMA, TAC, falling-edge quirk) in P1 | |

| Option | Description | Selected |
|--------|-------------|----------|
| Stubs open-bus | VRAM 8KiB and OAM 160B initialized to 0xFF, no render, no DMA | ✓ |
| Stubs zeroed | VRAM/OAM initialized to 0x00, not DMG-accurate | |
| Stubs + DMA functionality | Plus OAM DMA (160 cycles, bus lock), pre-work for Phase 2 | |

**User's choice:** 0xFF open-bus, full serial+joypad stub, static timer, open-bus VRAM/OAM
**Notes:** All recommendations accepted. Focus on DMG accuracy over convenience.

---

## CPU Register Layout

| Option | Description | Selected |
|--------|-------------|----------|
| packed struct 8x u8 | 8 fields: a,f,b,c,d,e,h,l + pc/sp. Pair getter methods. Type-safe, comptime-friendly | ✓ |
| packed struct con u16 superpuestos | Five u16: af,bc,de,hl,sp,pc. F in high byte of AF. Mask-prone | |
| struct plano (sin packed) | 8x u8 + pc + sp, no packed, no type guarantees from ARCHITECTURE.md | |

| Option | Description | Selected |
|--------|-------------|----------|
| u16 little-endian | Direct u16 for pc/sp. All targets (x86_64, aarch64) are LE, no swap | ✓ |
| u16 con helper read16/write16 | u16 with lo|hi<<8 helpers. Standard pattern, equally efficient | |

| Option | Description | Selected |
|--------|-------------|----------|
| Comptime opcode tables | 256-entry table, pc at instruction start, fetch() reads and advances pc | ✓ |
| PC con buffer de prefetch | 1-byte prefetch buffer, more hardware-faithful, not needed for cpu_instrs | |
| Match con comptime switch | Big switch instead of table, more readable but slower | |

| Option | Description | Selected |
|--------|-------------|----------|
| Tabla CB separada | Two tables: 256 main + 256 CB. Extra fetch only for CB opcodes | ✓ |
| Tabla 512 con marker | Single 512-entry table with bit 8 as CB marker. One dispatch, harder to read | |
| Switch anidado | switch(opcode) with case 0xCB => switch(cb_opcode). Verbose but legible | |

**User's choice:** packed struct 8x u8, u16 LE for pc/sp, comptime tables, separate CB table
**Notes:** All recommendations accepted.

---

## Additional Areas (agent-documented)

The user accepted agent recommendations for 7 additional areas. See CONTEXT.md D-21..D-27 for details:
- **D-21:** HALT-bug handling (CPU-04) — documented halt bug behavior
- **D-22:** Undocumented opcodes (CPU-04) — NOP behavior
- **D-23:** M-cycle measurement (BUS-04) — comptime M-cycle tables
- **D-24:** MMIO comptime asserts — compile-time offset checks
- **D-25:** Source file naming — flat src/ layout per mattneel/zgbc
- **D-26:** CLI interface — argv[1] for ROM path
- **D-27:** Cart header checksum — parse, warn on invalid, never fail

---

## the agent's Discretion

- Implementation details of fetch URL (std.http.Client vs curl)
- Comptime opcode table generation pattern (macro vs inline list)
- Logging level choice (debug for tests, info for CLI)
- RomLoader function placement (cartridge/rom_only.zig vs Emulator.loadRom method)

## Deferred Ideas

None — discussion stayed within Phase 1 scope.
