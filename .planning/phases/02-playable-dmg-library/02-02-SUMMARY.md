# Summary: Plan 02-02 — Timer + Interrupts

## Goal
Implement DMG timer subsystem (DIV, TIMA, TMA, TAC) and integrate with the interrupt controller. Replace Phase 1 timer stubs with cycle-accurate behavior.

## Completed ✓

### Task 1: DMG timer with cycle-accurate counting
- **DIV (0xFF04)**: 16-bit counter increments every T-cycle; DIV register = counter >> 8. Write to DIV resets counter to 0 and triggers falling-edge quirk.
- **TIMA (0xFF05)**: Increments at TAC-selected rate when enabled. 4 rates via TAC bits 0-1:
  - 0b00: 4096 Hz (1024 T-cycle threshold)
  - 0b01: 262144 Hz (16 T-cycles)
  - 0b10: 65536 Hz (64 T-cycles)
  - 0b11: 16384 Hz (256 T-cycles)
- **TMA (0xFF06)**: Timer modulo — reloads TIMA on overflow (0xFF → 0x00)
- **TAC (0xFF07)**: Bit 2 = enable, bits 0-1 = clock select
- **Overflow behavior**: TIMA wraps 0xFF → 0x00 → reload from TMA + set IF bit 2
- **Falling-edge quirk**: DIV write resets `tima_counter` accumulator
- Added `addr.TIMER_*` constants for TAC masks and clock thresholds

### Task 2: Interrupt dispatch — already complete from Phase 1
- IE/IF registers at 0xFFFF/0xFF0F (verified working)
- IME with EI/DI and EI delay (ime_next pattern)
- All 5 interrupt vectors dispatch via `@ctz(pending)` priority
- Timer interrupt (IF bit 2) now wired to TIMA overflow
- VBlank interrupt (IF bit 0) set by frame counter in tick()

### Verification
- ✅ `zig build` — zero errors
- ✅ `zig build serial` — serial output test passes

## Deferred ⏳
- Full Mooneye-level TAC falling-edge quirk (TAC enable transition AND gate) — deferred until accuracy test phase. The basic quirk (DIV write resets tima_counter) is implemented.

## Next
Proceed to Plan 02-03 (Joypad Input — P1 register, setButtonState API).
