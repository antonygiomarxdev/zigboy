# Requirements: ZigBoy

**Defined:** 2026-06-18
**Core Value:** Run any Game Boy ROM with cycle-accurate CPU and timing, with a smaller binary and lower overhead than comparable emulators — using Zig as both implementation language and a forcing function for performance.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Core (ROM and Persistence)

- [x] **CORE-01**: User can load a `.gb` ROM file from disk and parse the cartridge header (title, type, ROM/RAM size, header checksum)
- [ ] **CORE-02**: User can save battery-backed RAM to `<rom>.sav` on exit and restore on next launch
- [ ] **CORE-03**: User can reset the emulator (cold restart) from the host UI

### CPU (Sharp LR35902)

- [x] **CPU-01**: User can run any main opcode (256 base + 256 CB-prefix) with correct register and flag behavior
- [ ] **CPU-02**: User can trigger and handle interrupts (VBlank, LCD STAT, timer, joypad) with IME and IE/IF registers
- [x] **CPU-03**: User can HALT the CPU and wake on interrupt (with HALT-bug quirk)
- [x] **CPU-04**: Emulator correctly emulates LR35902 documented quirks: HALT bug, EI delay (one-instruction gap), conditional `RET` extra M-cycle, undocumented opcodes
- [x] **CPU-05**: Emulator runs at the DMG nominal 4.194304 MHz with M-cycle accuracy

### Bus (MMU)

- [x] **BUS-01**: User's program can read/write at any address in the 16-bit address space with correct banking and timing
- [x] **BUS-02**: Echo RAM (0xE000–0xFDFF) reads/writes mirror WRAM (0xC000–0xDDFF) transparently
- [ ] **BUS-03**: OAM DMA transfer copies 160 bytes from XX00 to OAM in 160 M-cycles, locking the CPU from OAM
- [x] **BUS-04**: Every M-cycle the bus advances CPU, timer, PPU, and any pending DMA — emulating real hardware timing

### Cartridge (MBC)

- [x] **CART-01**: Emulator supports ROM-only cartridges
- [ ] **CART-02**: Emulator supports MBC1 in mode 0 (up to 2 MiB ROM / 32 KiB RAM) and mode 1 (up to 512 KiB ROM / 32 KiB RAM, with mode-flag register)
- [ ] **CART-03**: Emulator supports MBC2 (256 × 4-bit built-in RAM)
- [ ] **CART-04**: Emulator supports MBC3 (up to 2 MiB ROM / 32 KiB RAM; RTC deferred to v2)
- [ ] **CART-05**: Emulator supports MBC5 (up to 8 MiB ROM / 128 KiB RAM, 9-bit bank register)

### PPU (Picture Processing Unit)

- [ ] **PPU-01**: Emulator advances the PPU in modes 0/1/2/3 with correct 456-dot line timing
- [ ] **PPU-02**: User sees a rendered background layer (BG) with correct scroll (SCY, SCX) and tile fetch
- [ ] **PPU-03**: User sees a window layer (when enabled) at WX/WY position
- [ ] **PPU-04**: User sees OAM sprites (8×8 and 8×16) with correct priority, flip, and palette attributes
- [ ] **PPU-05**: Emulator blocks the CPU from OAM/VRAM during PPU mode 3 (mode-3 bus blocking)
- [ ] **PPU-06**: Emulator raises a STAT interrupt on mode 0/1/2 entry and on LYC=LY
- [ ] **PPU-07**: Emulator raises a VBlank interrupt on line 144

### Timer

- [ ] **TIMER-01**: DIV register increments at 16384 Hz
- [ ] **TIMER-02**: TIMA increments at the TAC-selected rate (4 frequencies)
- [ ] **TIMER-03**: TIMA overflow reloads from TMA and fires a timer interrupt
- [ ] **TIMER-04**: Emulator implements the documented DIV/TAC write falling-edge quirk

### Input

- [ ] **INPUT-01**: User can press host keys mapped to the Game Boy D-pad (Up/Down/Left/Right)
- [ ] **INPUT-02**: User can press host keys mapped to the Game Boy buttons (A/B/Start/Select)
- [ ] **INPUT-03**: Emulator fires a joypad interrupt on any direction/button transition

### Host (SDL3 frontend)

- [ ] **HOST-01**: User can launch ZigBoy with a ROM path argument and see a window
- [ ] **HOST-02**: User sees the GB framebuffer rendered to the SDL3 window at native 160×144 (scaled)
- [ ] **HOST-03**: Emulator paces frames at 59.7275 Hz (DMG exact) using wall-clock tracking, dropping frames if behind
- [ ] **HOST-04**: User can quit the emulator by closing the window or pressing a host quit key
- [ ] **HOST-05**: User can toggle fullscreen with a host key

### Build and Distribution

- [x] **BUILD-01**: `zig build` produces a single statically-linked binary
- [x] **BUILD-02**: `zig build test` runs a headless test suite (CPU + bus + MBC + timer) without SDL3 (test runner compiles; runtime crashes due to pre-existing CPU bug — will be resolved by Plan 01-02 bug fix)
- [ ] **BUILD-03**: Release build is `ReleaseFast` with `strip` and `lto=.full`
- [ ] **BUILD-04**: Canonical ship target is `x86_64-linux-musl` (no glibc dependency)
- [ ] **BUILD-05**: Binary size under 5 MB on Linux x86_64-musl release build

### Accuracy Gates (Test ROMs)

- [ ] **ACC-01**: Emulator passes all of Blargg's `cpu_instrs.gb`
- [ ] **ACC-02**: Emulator passes Blargg's `dmg-acid.gb` (or `dmg-acid2`)
- [ ] **ACC-03**: Emulator passes Mooneye's `timer/` test suite
- [ ] **ACC-04**: Emulator passes Mooneye's `interrupt/` test suite
- [ ] **ACC-05**: Emulator passes Mooneye's `ppu/` test suite
- [ ] **ACC-06**: Emulator passes Mooneye's `oam_dma/` test suite
- [ ] **ACC-07**: Emulator passes Mooneye's `emulator-only/mbc{1,3,5}/` test suite
- [ ] **ACC-08**: Emulator runs commercial DMG titles (e.g., Tetris, Pokémon Red) without crashes and with working saves
- [ ] **ACC-09**: Emulator sustains > 60 FPS for any DMG ROM on a modern desktop CPU (single-threaded)

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Audio (APU)

- **AUDIO-01**: Emulator implements the 4-channel DMG APU (square 1, square 2, wave, noise) in cycle-accurate form
- **AUDIO-02**: User hears APU output at 44.1 kHz or 96 kHz via SDL3 audio stream
- **AUDIO-03**: Emulator supports per-channel enable flags (NR52)
- **AUDIO-04**: APU runs even when CPU is stopped (if audio is enabled)

### Save States and Replay

- **STATE-01**: User can save and load a snapshot of emulator state (BESS 1.0 format)
- **STATE-02**: Save states are cross-compatible with SameBoy and BGB (BESS 1.0)
- **STATE-03**: User can rewind gameplay by N frames via a savestate ring buffer

### Boot ROM and Models

- **BOOT-01**: Emulator loads the official DMG boot ROM (when present) and runs the boot sequence
- **BOOT-02**: Emulator supports MGB (Game Boy Pocket) boot ROM model
- **BOOT-03**: User can choose boot model (DMG / MGB / no-boot) from the command line

### Peripherals

- **PERIPH-01**: Emulator supports the Game Boy link cable (serial port) for 2-player link games
- **PERIPH-02**: Emulator supports the Game Boy infrared port (for very few specific titles)
- **PERIPH-03**: Emulator supports the Game Boy Printer (and saves print output as PNG/PDF)

### Color and Enhanced Hardware

- **CGB-01**: Emulator detects and runs Game Boy Color ROMs in CGB mode
- **CGB-02**: CGB PPU supports double-speed mode, palette RAM, VRAM bank switching
- **CGB-03**: CGB CPU runs at 4.194304 / 8.388608 MHz selectable
- **SGB-01**: Emulator supports the Super Game Boy command stream
- **SGB-02**: SGB border / palette / attribute commands render correctly

### Debug and TAS

- **DEBUG-01**: Emulator has a built-in debugger UI (breakpoints, register view, disassembly, memory view)
- **DEBUG-02**: User can step / continue / step-over from the debugger
- **TAS-01**: User can record input to a movie file and play it back deterministically
- **TAS-02**: Movies are cross-compatible with bgb-rs / SameBoy TAS format

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Game Boy Color (CGB) | Doubles CPU/PPU complexity; better to ship a complete DMG than a half-finished CGB |
| Super Game Boy (SGB) | Separate video processor; no commercial demand for DMG emulator niche |
| Link cable / IR / Printer | Peripheral complexity not justified for v1 single-player emulator |
| Mobile (iOS/Android) | Desktop-first; SDL3 mobile support is secondary |
| WebAssembly / browser | Core stability first; WASM is a known-good target later |
| Debugger UI in v1 | Powerful but scope-heavy; deserves its own tool/project |
| TAS / movie recording | Power-user feature; not core to "play DMG games" value |
| Real-time cycle-perfect vsync | Frame pacing with drop-when-behind is sufficient; post-processing is separate work |
| Cheat code UI | Out of scope; users can patch ROMs externally |
| GBC backwards-compat quirks | Only relevant if CGB mode is enabled; explicitly v2+ |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

### Phase 1: Hello, ROM

| Requirement | Phase | Status |
|-------------|-------|--------|
| CORE-01 | Phase 1, Plan 01-02 | Completed 2026-06-18 |
| CPU-01 | Phase 1, Plan 01-02 | Completed 2026-06-18 |
| CPU-03 | Phase 1, Plan 01-02 | Completed 2026-06-18 |
| CPU-04 | Phase 1, Plan 01-02 | Completed 2026-06-18 |
| CPU-05 | Phase 1, Plan 01-02 | Completed 2026-06-18 |
| BUS-01 | Phase 1, Plan 01-02 | Completed 2026-06-18 |
| BUS-02 | Phase 1, Plan 01-02 | Completed 2026-06-18 |
| BUS-04 | Phase 1, Plan 01-02 | Completed 2026-06-18 |
| CART-01 | Phase 1, Plan 01-02 | Completed 2026-06-18 |
| BUILD-01 | Phase 1, Plan 01-01 | Completed 2026-06-18 |
| BUILD-02 | Phase 1, Plan 01-03 | Completed (test runner compiles, runtime crash deferred) |
| ACC-01 | Phase 1 | Pending |

### Phase 2: Playable DMG library

| Requirement | Phase | Status |
|-------------|-------|--------|
| CPU-02 | Phase 2 | Pending |
| BUS-03 | Phase 2 | Pending |
| CART-02 | Phase 2 | Pending |
| CART-03 | Phase 2 | Pending |
| CART-04 | Phase 2 | Pending |
| CART-05 | Phase 2 | Pending |
| CORE-02 | Phase 2 | Pending |
| CORE-03 | Phase 2 | Pending |
| TIMER-01 | Phase 2 | Pending |
| TIMER-02 | Phase 2 | Pending |
| TIMER-03 | Phase 2 | Pending |
| TIMER-04 | Phase 2 | Pending |
| INPUT-01 | Phase 2 | Pending |
| INPUT-02 | Phase 2 | Pending |
| INPUT-03 | Phase 2 | Pending |
| ACC-03 | Phase 2 | Pending |
| ACC-04 | Phase 2 | Pending |
| ACC-07 | Phase 2 | Pending |

### Phase 3: Picture on screen

| Requirement | Phase | Status |
|-------------|-------|--------|
| PPU-01 | Phase 3 | Pending |
| PPU-02 | Phase 3 | Pending |
| PPU-03 | Phase 3 | Pending |
| PPU-04 | Phase 3 | Pending |
| PPU-05 | Phase 3 | Pending |
| PPU-06 | Phase 3 | Pending |
| PPU-07 | Phase 3 | Pending |
| HOST-01 | Phase 3 | Pending |
| HOST-02 | Phase 3 | Pending |
| HOST-03 | Phase 3 | Pending |
| HOST-04 | Phase 3 | Pending |
| HOST-05 | Phase 3 | Pending |
| ACC-02 | Phase 3 | Pending |
| ACC-05 | Phase 3 | Pending |
| ACC-06 | Phase 3 | Pending |

### Phase 4: Ship it

| Requirement | Phase | Status |
|-------------|-------|--------|
| BUILD-03 | Phase 4 | Pending |
| BUILD-04 | Phase 4 | Pending |
| BUILD-05 | Phase 4 | Pending |
| ACC-08 | Phase 4 | Pending |
| ACC-09 | Phase 4 | Pending |

**Coverage:**
- v1 requirements: 50 total
- Mapped to phases: 50
- Unmapped: 0 ✓

---
*Requirements defined: 2026-06-18*
*Last updated: 2026-06-18 after Plan 01-02 completion*
