# Summary: Plan 02-03 — Joypad Input

## Goal
Implement DMG joypad P1 register with button state matrix, joypad interrupt, and setButtonState() API for host integration.

## Completed ✓

### Task 1: P1 register + joypad interrupt + setButtonState

**addr.zig**:
- Added `JoypadButton` enum (a/b/select/start/right/left/up/down)
- Added `JOYP_SELECT_ACTION`/`JOYP_SELECT_DIRECTION`/`JOYP_UNUSED_BITS` constants
- Added `BUTTON_A` through `BUTTON_DOWN` index constants

**bus.zig**:
- Added `action_buttons: u4`, `direction_buttons: u4` fields (active-low: 0 = pressed)
- **Fixed bug**: JOYP write was storing low nibble (`val & 0x0F`) instead of select bits (bits 5-4). Now stores `(val & 0x30) | 0xCF` — select bits + forced high/unused bits.
- **Fixed bug**: JOYP read was returning stored low nibble. Now returns button matrix based on select bits:
  - Bit 5 = 0: action buttons (A/B/Select/Start → bits 0-3)
  - Bit 4 = 0: direction buttons (Right/Left/Up/Down → bits 0-3)
  - Both = 0: wired AND of both sets
  - Neither: 0x0F (all released)
- Joypad interrupt (IF bit 4) set on button state transition in setButtonState()

**Emulator.zig**:
- Added `setButtonState(button: JoypadButton, pressed: bool)` — compares old/new state, fires joypad interrupt on transition, updates the appropriate button set

### Verification
- ✅ `zig build` — zero errors
- ✅ `zig build serial` — serial test passes

## Next
Proceed to Phase 03 (PPU — framebuffer rendering, LCD modes, scrolling, window).
