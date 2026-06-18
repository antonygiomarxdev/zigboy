# Roadmap: ZigBoy

## Overview

ZigBoy is a hyper-fast, super-lightweight Game Boy (DMG) emulator written in Zig.
The journey moves from a headless test harness that boots Blargg's `cpu_instrs.gb`
(Phase 1: "Hello, ROM") through a fully working but unrendered commercial game
library (Phase 2: "Playable DMG library"), to a picture-on-screen SDL3 build
(Phase 3: "Picture on screen"), and finally to a shipped, statically-linked,
< 5 MB Linux binary that passes the full Blargg+Mooneye accuracy suite
(Phase 4: "Ship it"). Each phase is a vertical MVP slice — by the end of each
phase, the user can run the emulator headless or visible and see a real,
observable milestone.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Hello, ROM** — Skeleton + CPU + Bus + ROM-only cart, passes Blargg `cpu_instrs`
- [ ] **Phase 2: Playable DMG library** — Timer + Interrupts + Joypad + MBC1/2/3/5 + .sav, runs commercial DMG games headless
- [ ] **Phase 3: Picture on screen** — PPU + SDL3 host + 59.7275 Hz frame pacing, Tetris visible in a window
- [ ] **Phase 4: Ship it** — Release build, full accuracy gates, cross-platform, < 5 MB static binary, CI

## Phase Details

### Phase 1: Hello, ROM
**Goal**: Stand up the `zig build` toolchain, implement the LR35902 CPU core with the bus and a ROM-only cart, and boot Blargg's `cpu_instrs.gb` end-to-end via `zig build test` — no SDL3, no PPU, no MBCs yet.
**Mode:** mvp
**Depends on**: Nothing (first phase)
**Requirements**: CORE-01, CPU-01, CPU-03, CPU-04, CPU-05, BUS-01, BUS-02, BUS-04, CART-01, BUILD-01, BUILD-02, ACC-01
**Success Criteria** (what must be TRUE):
  1. `zig build` produces a ZigBoy binary that, when run with `zigboy tests/cpu_instrs.gb`, executes the ROM and reaches the test-pass screen ("Passed")
  2. `zig build test` runs the headless test suite and 100% of the Blargg `cpu_instrs` sub-tests pass
  3. The CPU correctly emulates LR35902 quirks (HALT-bug, EI delay, conditional `RET` extra M-cycle, undocumented opcodes) as verified by the quirk-specific Blargg sub-tests
  4. ROM-only cartridges load and dispatch correctly (header parsed, banking is a no-op)
  5. The bus advances CPU + timer + (stub) PPU on every M-cycle, with cycle-counted timing
**Plans**: 3 plans

Plans:
- [x] 01-01-PLAN.md — Build skeleton: build.zig.zon + build.zig with castholm/SDL v0.5.1+3.4.10 static + built-in translate-c; src/main.zig SDL3 Init/Quit stub; src/lib.zig + Emulator.zig stub; .gitignore (Wave 1)
- [ ] 01-02-PLAN.md — CPU + bus + ROM-only cart: packed-struct regfile, 256+256 comptime opcode tables, bus MMU with full 16-bit address dispatch + cycle accounting + peripheral stubs + serial capture + echo RAM, ROM-only loader with header checksum (Wave 2)
- [ ] 01-03-PLAN.md — Test ROM runner: auto-fetch cpu_instrs.gb, run via Emulator, assert "Passed" in serial output; build.zig test step; ACC-01 gate (Wave 3)

### Phase 2: Playable DMG library
**Goal**: Add timer, interrupts, joypad, MBC1/2/3/5 mappers, and battery-backed `.sav` persistence — enough for the user to run any common commercial DMG title (Tetris, Pokémon Red, Zelda: Link's Awakening) headless with working saves, but no visible output yet.
**Mode:** mvp
**Depends on**: Phase 1
**Requirements**: CPU-02, BUS-03, CART-02, CART-03, CART-04, CART-05, CORE-02, CORE-03, TIMER-01, TIMER-02, TIMER-03, TIMER-04, INPUT-01, INPUT-02, INPUT-03, ACC-03, ACC-04, ACC-07
**Success Criteria** (what must be TRUE):
  1. User runs `zigboy game.gb` and the game logic plays correctly (verified by running Tetris headless and observing score increment over time)
  2. Battery-backed RAM persists to `<rom>.sav` on quit and restores on next launch (verified by running a save+quit+reload roundtrip)
  3. The DIV/TAC timer quirk is correctly emulated, verified by passing Mooneye's `timer/` test suite
  4. The HALT-bug and EI-delay CPU quirks integrate with interrupts correctly, verified by passing Mooneye's `interrupt/` test suite
  5. MBC1 (both modes), MBC2, MBC3, and MBC5 dispatch correctly, verified by passing Mooneye's `emulator-only/mbc{1,3,5}/` test suites
**Plans**: 3 plans

Plans:
- [ ] 02-01: MBC1/2/3/5 + .sav persistence — cart dispatch table, MBC1 mode flag, MBC5 9-bit bank register, `.sav` magic header + atomic write
- [ ] 02-02: Timer + interrupts — DIV @ 16384 Hz, TIMA @ 4 TAC rates, TMA reload, timer falling-edge quirk, full interrupt controller (IME, IE/IF) with EI delay
- [ ] 02-03: Joypad input — P1 register with select bits, host keyboard mapping (configurable in `~/.config/zigboy/keys.conf`), joypad interrupt on transition

### Phase 3: Picture on screen
**Goal**: Implement the full PPU (modes, BG, window, sprites, OAM DMA, STAT/VBlank interrupts) and an SDL3 host that renders the 160×144 framebuffer at the DMG-exact 59.7275 Hz pace. By the end, the user runs `zigboy game.gb` and sees Tetris or Pokémon Red on screen.
**Mode:** mvp
**Depends on**: Phase 2
**Requirements**: PPU-01, PPU-02, PPU-03, PPU-04, PPU-05, PPU-06, PPU-07, HOST-01, HOST-02, HOST-03, HOST-04, HOST-05, ACC-02, ACC-05, ACC-06
**Success Criteria** (what must be TRUE):
  1. User runs `zigboy tetris.gb` and sees the Tetris title screen in an SDL3 window with working keyboard controls
  2. PPU mode-3 bus blocking is emulated (CPU blocked from OAM/VRAM during mode 3), verified by passing Mooneye's `ppu/` test suite
  3. PPU renders BG, window, and 8×8/8×16 sprites with correct priority, palette, and SCX%8 behaviour, verified by passing `dmg-acid2`
  4. Frame pacing holds at 59.7275 Hz (drop-when-behind policy) — measured by an in-app FPS counter
  5. STAT interrupt fires on mode 0/1/2 entry and on LYC=LY; VBlank interrupt fires on line 144; OAM DMA works (verified by Mooneye's `oam_dma/` suite)
**Plans**: 3 plans

Plans:
- [ ] 03-01: PPU modes + BG + Window — 4-mode state machine with 456-dot line timing, BG tile fetch + scroll, Window at WX/WY
- [ ] 03-02: PPU sprites + OAM DMA + STAT IRQ — 8×8/8×16 OAM sprites with priority/flip/palette, OAM DMA (160-cycle source-to-OAM copy with bus lock), STAT interrupt (modes 0/1/2, LYC=LY)
- [ ] 03-03: SDL3 host + 59.7275 Hz frame pacing — `castholm/SDL` window/renderer, `SDL_TEXTUREACCESS_STREAMING` texture update per frame, wall-clock delta loop with frame-drop policy, keyboard → GB joypad map, window-close + fullscreen toggle

### Phase 4: Ship it
**Goal**: Tighten the build to a single statically-linked Linux binary < 5 MB, run the full Blargg+Mooneye accuracy suite end-to-end, add macOS+Windows targets, and wire up CI on GitHub Actions.
**Mode:** mvp
**Depends on**: Phase 3
**Requirements**: BUILD-03, BUILD-04, BUILD-05, ACC-08, ACC-09
**Success Criteria** (what must be TRUE):
  1. `zig build -Doptimize=ReleaseFast` produces a single statically-linked `zigboy` binary on `x86_64-linux-musl` that runs Tetris and Pokémon Red with working saves, with `file zigboy` showing no dynamic linker dependency and `size` reporting < 5 MB
  2. The full Blargg+Mooneye accuracy suite passes (all of `cpu_instrs`, `instr_timing`, `dmg-acid2`, `timer/`, `interrupt/`, `ppu/`, `oam_dma/`, `emulator-only/mbc{1,3,5}/`) in CI on every commit
  3. macOS ARM64 and Windows x86_64 cross-platform builds succeed (from a Linux builder where possible, with documented Mac-only steps for Apple SDK)
  4. A GitHub Actions workflow runs the test suite on every push and uploads a release artifact on tag
  5. Emulator sustains > 60 FPS (averaged over 60 seconds) for any DMG ROM on a modern desktop CPU (single-threaded)
**Plans**: 3 plans

Plans:
- [ ] 04-01: Release build configuration — `ReleaseFast` + `strip` + `lto=.full`, `x86_64-linux-musl` target, binary size budget enforcement in CI
- [ ] 04-02: Full accuracy gate — fetch and run Blargg + Mooneye + dmg-acid2 in CI, report pass/fail per ROM, fail the build on any regression
- [ ] 04-03: Cross-platform + CI — macOS ARM64 and Windows x86_64 targets, GitHub Actions matrix, release artifact publishing, README with build/run instructions

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Hello, ROM | 1/3 | Executing (Plans 02-03 pending) | 2026-06-18 |
| 2. Playable DMG library | 0/3 | Not started | - |
| 3. Picture on screen | 0/3 | Not started | - |
| 4. Ship it | 0/3 | Not started | - |
