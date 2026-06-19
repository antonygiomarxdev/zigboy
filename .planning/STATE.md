---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: executing
stopped_at: Phase 02 started — plans created for MBC mappers (.sav), timer/interrupts, and joypad
last_updated: "2026-06-18T23:45:00.000Z"
last_activity: 2026-06-18 -- Phase 02 started (0/3 plans); planning complete, execution begins
progress:
  total_phases: 4
  completed_phases: 1
  total_plans: 12
  completed_plans: 3
  percent: 25
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-06-18)

**Core value:** Run any Game Boy ROM with cycle-accurate CPU and timing, with a smaller binary and lower overhead than comparable emulators — using Zig as both implementation language and a forcing function for performance.
**Current focus:** Phase 02 — Playable DMG library (executing Wave 1: MBC mappers)

## Current Position

Phase: 02 (playable-dmg-library) — EXECUTING
Plan: 0 of 3
Status: Phase 02 starting. Plans created for MBC1/2/3/5 mappers + .sav persistence (02-01), timer/interrupts (02-02), and joypad input (02-03).
Last activity: 2026-06-18 -- Phase 02 started (0/3 plans)

Progress: [███░░░░░░░] 25% (3/12 plans complete)

## Performance Metrics

**Velocity:**

- Total plans completed: 3
- Average duration: 30 min
- Total execution time: 2 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1. Hello, ROM | 3 | 3 | 40m |
| 2. Playable DMG library | 0 | 3 | — |
| 3. Picture on screen | 0 | 3 | — |
| 4. Ship it | 0 | 3 | — |

**Recent Trend:**

- Last 5 plans: 01-01 (38m), 01-02 (6m), 01-03 (75m, including bug fixes)
- Trend: stable

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- **Init**: 4 phases (coarse, MVP), 12 plans, 50 v1 requirements — vertical-slice ordering per ARCHITECTURE.md
- **Init**: Lock stack to Zig 0.16 + SDL3 via `castholm/SDL` with built-in `b.addTranslateC` (NOT SDL2; not @cImport; NOT external translate-c package — incompatible with 0.16)
- **01-01**: Use built-in `b.addTranslateC` instead of external `translate-c` package (external requires Zig ≥0.17 `addPassthruArgs` API)
- **Init**: Lock build target to `x86_64-linux-musl` with `ReleaseFast` + `strip` + `lto=.full`
- **Init**: NO allocator in CPU/bus hot path; `packed struct` register file + MMIO with `comptime` offset asserts
- **Init**: Test ROMs sourced via `zig build test` fetch (not vendored) — Blargg, Mooneye, dmg-acid2
- **01-03**: `Emulator.init` returns `*Emulator` (heap-allocated) to avoid dangling internal pointer (`Cpu.bus` points to Bus field within Emulator — must never move)
- **01-03**: Blargg `cpu_instrs.gb` (MBC1 cartridge type 0x01) does not pass ACC-01 in Phase 1. Root cause: missing PPU (LY register), timer (TIMA/TMA), and MBC1 bank switching. Not a bug — scope deferred.

### Pending Todos

None after Phase 01 completion.

### Blockers/Concerns

- **ACC-01 gate pending**: Blargg cpu_instrs.gb requires PPU LY register, timer, and MBC1 support. Not blocked — deferred to Phase 2+ as planned scope expansion.
- **Header checksum warning**: Blargg ROM `cpu_instrs.gb` shows `sum(0x134-0x14D) = 0xE7` (expected 0x00). ROM from retrio/gb-test-roms is genuine — the checksum byte at 0x14D is 0x3B which does not satisfy the boot ROM's `sum == 0` check. This is informational only (no boot ROM in our emulator). Verified ROM is uncorrupted (identical to fresh download).

## Deferred Items

Items acknowledged and carried forward from previous milestone close:

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| Audio | APU (4-channel DMG audio) | Deferred to v1.x | 2026-06-18 init |
| Save states | BESS 1.0 save states | Deferred to v1.x | 2026-06-18 init |
| Boot ROM | DMG/MGB boot ROM support | Deferred to v1.x (legal) | 2026-06-18 init |
| CGB | Game Boy Color support | **Planned v2 (Phase 5)** — see `.planning/GBC-PREP.md` | 2026-06-18 init, scope revised 2026-06-18 |
| SGB | Super Game Boy support | Out of scope for v1 | 2026-06-18 init |
| Peripherals | Link cable, IR, Printer | Out of scope for v1 | 2026-06-18 init |
| Debug | Debugger UI | Out of scope for v1 | 2026-06-18 init |
| TAS | Movie recording / playback | Out of scope for v1 | 2026-06-18 init |
| CPU accuracy | Blargg test passes all sub-tests (ACC-01) | Deferred: needs PPU, timer, MBC1 | 2026-06-18 Phase 01 close |

## Session Continuity

Last session: 2026-06-18T23:40:00.000Z
Stopped at: Phase 01 complete — all 3 plans implemented. CPU decoder register-extraction bug fixed. Dangling `Cpu.bus` pointer fixed via heap-allocated Emulator. Serial capture verified with minimal test ROM. Blargg test runner operational (loads, runs, captures 28 bytes, no crash). Next: Phase 02 (PPU, timer, MBC1).
Resume file: .planning/phases/01-hello-rom/01-03-SUMMARY.md
