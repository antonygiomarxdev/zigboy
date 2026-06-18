# ZigBoy

## What This Is

ZigBoy is a hyper-fast, super-lightweight Game Boy (DMG) emulator written in Zig.
It targets cycle-accurate execution, minimal binary size, low memory footprint, and
fast startup — leveraging Zig's compile-time features, manual memory management,
and C-ABI interop. The intended audience is emulator enthusiasts, developers
learning emulator/architecture work, and anyone who wants a clean, modern Zig
reference for the Game Boy platform.

## Core Value

Run any Game Boy ROM with cycle-accurate CPU and timing, with a smaller binary
and lower overhead than comparable emulators (e.g. SameBoy C, Gambatte) — using
Zig as both the implementation language and a forcing function for performance.

## Requirements

### Validated

<!-- Shipped and confirmed valuable. -->

(None yet — ship to validate)

### Active

<!-- Current scope. Building toward these. -->

- [ ] Load and parse a Game Boy ROM (.gb) header and cartridge metadata
- [ ] Implement the Sharp LR35902 CPU core (registers, flags, instruction set, interrupts)
- [ ] Implement memory bus (ROM bank 0/1N, VRAM, WRAM, HRAM, OAM, I/O, Echo RAM)
- [ ] Implement the PPU (background, window, sprites, OAM DMA, mode-based timing)
- [ ] Implement MBC1 / MBC3 / MBC5 cartridge controllers (common mapper coverage)
- [ ] Implement timer and divider (DIV/TIMA/TMA/TAC)
- [ ] Implement joypad input
- [ ] Render the Game Boy framebuffer to a desktop window (SDL2 / miniaudio)
- [ ] Save/load battery-backed RAM (.sav) per ROM
- [ ] Pass Blargg's `cpu_instrs` and `dmg-acid` test ROMs
- [ ] Build a single statically-linked binary with no runtime dependencies

### Out of Scope

- Game Boy Color (CGB) support — DMG-only for v1; CGB requires separate PPU/PPU bus work
- Game Boy Printer, Infrared, Link Cable — peripheral complexity not justified for v1
- Super Game Boy (SGB) — separate video processor, deferred indefinitely
- Audio (APU) output — v1 focuses on video/inputs; APU can come after visuals are stable
- Mobile platforms (iOS/Android) — desktop-first
- WebAssembly / browser builds — defer until core is stable
- Debugger / disassembler UI — runtime stats only in v1; full debugger is a separate tool
- TAS / movie recording — not a v1 goal
- Cycle-accurate pixel-perfect vsync post-processing — frame pacing is good enough for v1

## Context

- **Target hardware:** Original Game Boy (DMG-01), Sharp LR35902, 8-bit, 4.19 MHz
- **Reference documents:** Pan Docs (gbdev.io/pandocs), Blargg's test ROMs, Mooneye's
  test suite, gbdev wiki
- **Zig version:** Latest stable (0.14+); use `zig build` as the canonical build system
- **Target platform for v1:** Linux x86_64 first, then macOS ARM64, then Windows
- **Prior work:** None — this is a from-scratch project

## Constraints

- **Language:** Zig only (no C/C++ in the core; C-ABI interop allowed for SDL3 bindings via `b.addTranslateC`)
- **License:** MIT (target)
- **Build system:** `zig build` (no CMake, no Make, no shell scripts for build)
- **Performance target:** > 60 FPS for any DMG ROM on a modern desktop CPU; < 30 MB RAM
  working set
- **Binary target:** < 5 MB statically-linked Linux binary (release-fast, stripped)
- **No garbage collection** — manual memory or arena allocators only
- **Determinism:** Same ROM + same input → same output (frame N) bit-for-bit

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| DMG-only for v1 | CGB doubles the PPU/CPU complexity; better to ship a complete DMG than a half-finished CGB | — Pending |
| SDL2 for window/input/audio I/O | Industry-standard, well-supported, simple C-ABI; Zig can call it directly | — Pending |
| Coarse-grained phase plan | 3-5 phases so each phase ships a meaningful milestone; aligns with MVP structure | — Pending |
| Manual mode, no auto-advance at runtime | Auto-mode is for project init; once we have a roadmap we want deliberate phase gates | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-06-18 after initialization*
