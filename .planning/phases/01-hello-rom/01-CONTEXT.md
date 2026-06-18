# Phase 01: Hello, ROM - Context

**Gathered:** 2026-06-18
**Status:** Ready for planning

<domain>
## Phase Boundary

Stand up `zig build` toolchain with SDL3 dependency wiring. Implement the Sharp LR35902 CPU core with packed-struct register file, comptime 256-entry opcode dispatcher, and bus-centered cycle accounting. Load ROM-only cartridges, parse headers, and boot Blargg's `cpu_instrs.gb` end-to-end via `zig build test` — no SDL3 window, no PPU rendering, no MBCs yet.

**In scope for this phase:**
- `build.zig` + `build.zig.zon` with castholm/SDL v0.5.1+3.4.10 (static)
- `src/main.zig` — SDL_Init/SDL_Quit no-op stub, ROM path from argv[1]
- `src/lib.zig` — re-exports `Emulator`
- CPU: LR35902 packed struct register file, 256+256 comptime opcode tables
- Bus: full 16-bit address map with cycle accounting, open-bus convention
- Cartridge: ROM-only loader + header parser (title, type, size, checksum warn)
- Tests: fetch + cache Blargg cpu_instrs.gb, run headless via zig build test
- Emulator: init(allocator), loadRom(path), stepInstruction(), stepMCycle(), runForFrames(n), deinit()

**Out of scope:**
- PPU rendering and modes (Phase 3)
- MBC1/2/3/5 (Phase 2)
- Timer DIV/TIMA/TMA/TAC (Phase 2 — static stub in P1)
- Interrupt dispatch (VBlank/STAT/timer/joypad) beyond IME/IE/IF (Phase 2)
- Joypad P1 register beyond static stub (Phase 2)
- SDL3 window/renderer/input (Phase 3)
- APU audio (v1.x deferred)
- Save states, BESS formats (v1.x deferred)
- Boot ROM (v1.x deferred)
- CGB/SGB (out of scope for v1)
- Link cable, IR, Printer (out of scope for v1)
- Debugger UI (out of scope for v1)

</domain>

<decisions>
## Implementation Decisions

### SDL3 Build Wiring
- **D-01:** Cablear SDL3 en Fase 1. `build.zig.zon` + `b.dependency("sdl", ...)` + `b.addTranslateC` en Fase 1 para build graph estable desde el principio. Fase 3 sustituye el stub por la ventana real sin refactorizar build.zig.
- **D-02:** Stub Init/Quit no-op en `src/main.zig`. `SDL_Init(SDL_INIT_VIDEO)` al arranque, `SDL_Quit()` al final, sin ventana. El emulador nunca depende de SDL3 — solo el host (main.zig) lo toca.
- **D-03:** castholm/SDL pineado a `v0.5.1+3.4.10` (tag fijo). Actualización manual deliberada para build reproducible.
- **D-04:** Linkage static (`preferred_linkage = .static`). Cero deps runtime. `strip` + `lto = .full` para release.

### Test ROM Fetch
- **D-05:** Fetch + cache local. `zig build test` detecta falta de ROM, descarga, cachea. El test falla con mensaje claro si el fetch falla.
- **D-06:** URL: `https://raw.githubusercontent.com/retrio/gb-test-roms/master/cpu_instrs/cpu_instrs.gb`
- **D-07:** Caché en `tests/roms/cpu_instrs.gb`. Directorio `tests/roms/` gitignored. Ruta simple y visible.
- **D-08:** Auto-fetch en `zig build test`. Sin comando separado. Cero acción manual para primer test.

### Emulator Public API
- **D-09:** API completa y granular: `stepInstruction()`, `stepMCycle()`, `runForFrames(n)`. Caller elige granularidad. Consistente con tests (algunos quieren step-by-step, otros quieren batch).
- **D-10:** `Emulator.init(allocator: std.mem.Allocator)` — caller provee allocator. Patrón estándar Zig 0.16.
- **D-11:** Métodos devuelven `!void`. Errores fatales: `BusError.Unmapped`, `CpuError.UndocumentedOpcode`, etc. Caller propaga con `try`. Sin error recovery mágico.
- **D-12:** Sin callbacks ni vtable. `emu.getFrameBuffer() -> *[160*144]u8`, `emu.setButtonState(GamepadButton, bool)`. Getters explícitos.

### Bus Stub Behavior (Phase 1)
- **D-13:** Open-bus devuelve `0xFF` (DMG real, líneas en alto). Coincide con lo que Blargg's cpu_instrs espera.
- **D-14:** Serial stub: captura bytes escritos en SB (0xFF01) para que tests de Blargg reporten "Passed". Joypad stub: P1 = 0xCF inicial (ninguna tecla presionada, fila alta+baja seleccionadas).
- **D-15:** Timer stub estático: DIV = 0x00, TIMA = 0x00, TMA = 0x00, TAC = 0x00. Sin incrementos, sin interrupciones. Timer real en Fase 2.
- **D-16:** VRAM (8 KiB, 0x8000-0x9FFF) y OAM (160 B, 0xFE00-0xFE9F) inicializados a 0xFF. Sin render, sin sprites, sin OAM DMA. PPU en Fase 3.

### CPU Register File
- **D-17:** `packed struct` con 8 campos `u8` (a, f, b, c, d, e, h, l) + `sp: u16` + `pc: u16`. Pares via métodos comptime: `getBc() -> u16`, `setBc(v: u16)`. `f` enmascarado con `& 0xF0` al escribir — bits bajos siempre 0 (DMG real).
- **D-18:** `u16` little-endian para `pc` y `sp`. Todas las plataformas target (x86_64, aarch64) son LE. Sin swap innecesario.

### Comptime Opcode Dispatch
- **D-19:** Tabla comptime de 256 entradas para opcodes main. `pc` apunta al inicio de la instrucción. `fetch()` lee byte de `bus[pc]` y avanza `pc` por el tamaño del opcode. Cero alocaciones en hot path.
- **D-20:** Tabla CB separada de 256 entradas. `stepInstruction()` detecta opcode `0xCB`, hace `fetch()` del segundo byte, dispatch en tabla CB. Separación limpia, costo marginal solo en CB opcodes.

### HALT-Bug Handling (CPU-04)
- **D-21:** Implementar HALT-bug documentado: cuando `HALT` se ejecuta y un interrupt está pendiente pero `IME=0`, el CPU despierta (sale de HALT) pero NO despacha la ISR. `PC` permanece en la instrucción HALT. Cuando `IME=1` después, la siguiente instrucción corre primero, luego la ISR. Blargg's `halt_bug.gb` testea este comportamiento.

### Undocumented Opcodes (CPU-04)
- **D-22:** Los ~30 opcodes no documentados del LR35902 se tratan como NOP (no operación) + avance de PC. El costo de dispatch es marginal. Comportamiento documentado en Pan Docs. Suficiente para pasar cpu_instrs.

### M-Cycle Measurement (BUS-04)
- **D-23:** Tabla comptime de 256 entradas con M-cycles por opcode main. Tabla separada de 256 para CB-prefix. `stepInstruction()` lee cycle count de la tabla y llama `bus.tick(n)` para avanzar timer/PPU stubs exactamente N M-cycles. Consistente con el modelo bus-centered.

### MMIO Comptime Asserts
- **D-24:** Aplicar `comptime std.debug.assert(@offsetOf(Mmio, field) == addr)` para cada registro MMIO en el Mmio packed struct. Compile-time check. Errores de offset se detectan en tiempo de compilación, no en runtime.

### Source File Naming
- **D-25:** Estructura plana siguiendo mattneel/zgbc:
  - `src/main.zig` — CLI entry point (SDL3 stub + ROM path)
  - `src/lib.zig` — re-export del Emulator
  - `src/cpu.zig` — LR35902 register file + opcode dispatch
  - `src/bus.zig` — MMU con read8/write8, address dispatch, cycle accounting
  - `src/cartridge/rom_only.zig` — ROM-only loader + header parser
  - `src/Emulator.zig` — top-level struct, init/run/deinit
  - `build.zig` + `build.zig.zon` — build system
  - `tests/` — test suite zig build test

### Command-Line Interface
- **D-26:** `./zigboy <rom-path>`. El binario lee `argv[1]` como path del ROM. `zig build run -- <rom-path>` pasa el argumento. Para tests headless, el path se resuelve relativo al workspace o se pasa via variable de entorno `ZIGBOY_TEST_ROM`.

### Cartridge Header Checksum (CORE-01)
- **D-27:** Parsear header checksum (byte 0x014D) y validarlo (suma de bytes 0x0134-0x014C == 0). Si inválido, loguear warning pero no fallar. El DMG real ignora el checksum y ejecuta igual. Blargg's cpu_instrs.gb tiene checksum válido.

### the agent's Discretion
- Patrón de fetch URL: usar `std.http.Client` o `std.process.Child` con `curl`. Si `std.http.Client` de Zig 0.16 es suficiente, preferirlo sobre dep externa.
- Despliegue de tablas comptime: macro `generateOpcodeTable(comptime T: type)` vs lista inline de 256 entradas.
- Logging: `std.log` o wrapper mínimo. Nivel `debug` para tests, `info` para CLI.
- El RomLoader puede ser una función en `cartridge/rom_only.zig` o un método de `Emulator.loadRom()`.

### Folded Todos
None — no pending todos matched Phase 1 scope.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Emulator Architecture References
- `.planning/research/ARCHITECTURE.md` — Bus-centered design, packed struct MMU, component layout
- `.planning/research/STACK.md` — Zig 0.16.0 + SDL3 via castholm/SDL + b.addTranslateC + musl static
- `.planning/research/FEATURES.md` — Table-stakes feature set for v1
- `.planning/research/PITFALLS.md` — Known gotchas (HALT-bug, open-bus, releasefast undefined, SDL2→SDL3 migration)
- `.planning/research/SUMMARY.md` — Consolidated findings with confidence ratings

### Project Requirements & Roadmap
- `.planning/REQUIREMENTS.md` — Full v1 requirements (CORE-01, CPU-01..05, BUS-01..04, CART-01, BUILD-01..02, ACC-01)
- `.planning/ROADMAP.md` § Phase 1: Hello, ROM — Goal, success criteria, 3 planned sub-phases
- `.planning/PROJECT.md` — Core value, constraints, key decisions
- `.planning/STATE.md` — Current position, accumulated context, deferred items

### External References
- **Pan Docs** (gbdev.io/pandocs) — Definitive GB technical reference: CPU opcodes, MMIO map, MMU layout, boot sequence, hardware quirks
- **GB Dev Wiki** (gbdev.io) — Extended reference for undocumented LR35902 opcodes, timer quirks, serial protocol through Blargg ROM
- **retrio/gb-test-roms** (GitHub) — Source repo for cpu_instrs.gb and other Blargg test ROMs
- **mattneel/zgbc** (GitHub, `zig-0.16-llm-context.md`) — Reference Zig 0.16 emulator architecture; src/ flat layout, comptime opcode dispatch, Blargg pass

### LR35902 CPU Specificity
- **Sharp SM83 datasheet** (archived) — Official LR35902/SM83 instruction behavior, cycle timings, undocumented opcodes (when available)
- **SameBoy C** (GitHub) — Reference implementation for HALT-bug, EI delay, conditional RET extra M-cycle behaviors

### Bus & Cartridge
- **Mooneye test suite** `emulator-only/mbc1/` — Reference for ROM-only behavior (used when no MBC is present — ROM only maps 0000-7FFF, A000-BFFF open-bus)
- **gbdev.io/pandocs** § Cartridge Header — Byte-level ROM header parsing: title (0x0134-0x0143), type (0x0147), ROM size (0x0148), RAM size (0x0149), checksum (0x014D)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
No existing source code — this is a from-scratch project. Research files under `.planning/research/` contain architecture templates and patterns from reference emulators (mattneel/zgbc, SameBoy, Mooneye).

### Established Patterns (from research)
- **Bus-centered cycle accounting** — `read8`/`write8` advance a single T-cycle counter fanned out to all peripherals (Ryp's pattern, also used by SameBoy, mattneel/zgbc)
- **packed struct MMIO** — 256-byte packed struct with comptime offset asserts (ARCHITECTURE.md § MMU)
- **comptime opcode tables** — 256-entry main + 256-entry CB, generated at compile time (mattneel/zgbc pattern)
- **Flat src/ layout** — cpu.zig, bus.zig, cartridge/ directory, Emulator.zig

### Integration Points
- `src/lib.zig` — re-exports Emulator struct; this is the single public API surface consumed by main.zig (Fase 1-3) and test harness
- `src/main.zig` — CLI entry point; in Fase 1 it validates SDL3 binding (Init/Quit) + ROM load; Fase 3 adds SDL3 window + event loop
- `build.zig.zon` — dependency declaration for castholm/SDL; stable from Fase 1 forward

</code_context>

<specifics>
## Specific Ideas

- **blargg_test_runner.zig**: A dedicated test file in `tests/` that fetches + caches cpu_instrs.gb, runs it through Emulator.tick, and asserts serial output contains "Passed". Pattern borrowed from mattneel/zgbc's test harness.
- **serial output buffer**: Emulator exposes a `serial_output: []u8` or callback-free `getSerialOutput(): []const u8` for the test harness to read Blargg's "Passed" / "Failed" markers.
- **fetch implementation**: Zig 0.16 `std.http.Client` with a simple `fetchUrl(url, allocator)` helper. If std.http is unstable, shell out to `curl --silent --fail` as fallback. Try `std.http` first.
- **Header checksum validation**: Sum bytes 0x0134-0x014C modulo 0x100 should equal byte at 0x014D. If mismatch, `std.log.warn("header checksum mismatch: expected 0x{X:02}, got 0x{X:02}", .{ expected, actual })`.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within Phase 1 scope. All 5 discussed areas and 7 agent-documented areas are in scope.

### Reviewed Todos (not folded)
None — no pending todos matched Phase 1 scope.

</deferred>

---

*Phase: 01-hello-rom*
*Context gathered: 2026-06-18*
