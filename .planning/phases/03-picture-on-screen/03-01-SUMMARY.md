# Summary: Plan 03-01 — PPU modes + BG + Window

## Goal
Implement the PPU with 4-mode state machine, background rendering with scroll, window layer, and STAT/VBlank interrupts. Replace bus stubs with a functional PPU.

## Completed ✓

### Task 1: PPU struct and mode state machine
- `src/ppu.zig` with `PpuMode` enum (hblank/vblank/oam_scan/drawing)
- 456-dot-per-line state machine, 154 lines per frame
- Mode 2 (OAM scan): dots 0-79
- Mode 3 (Drawing): dots 80-251
- Mode 0 (HBlank): dots 252-455
- Mode 1 (VBlank): lines 144-153
- VBlank interrupt (IF bit 0) fires on LY=144
- STAT interrupt fires on mode 0/1/2 entry and LYC=LY
- LCDC disable: resets LY=0, dot_counter=0, STAT=0

### Task 2: PPU register dispatch + bus integration
- Replaced `_pad_40_4F: [16]u8` with individual MMIO registers:
  - `LCDC, STAT, SCY, SCX, LY, LYC, DMA, BGP, OBP0, OBP1, WY, WX, _pad_4C_4F`
- Removed `vram_stub`, `oam_stub` from Bus — replaced with `Ppu` struct
- VRAM reads/writes route through PPU with mode-3 blocking
- OAM reads/writes route through PPU with mode-2/3 blocking
- Bus.tick() forwards M-cycles to PPU

### Task 3: Background rendering with scroll
- Tile map selection via LCDC bit 3 (0x9800 or 0x9C00)
- Tile data addressing: unsigned (0x8000) or signed (0x8800) per LCDC bit 4
- 2bpp tile data: plane 0 + plane 1, 2 bytes per row, 8 rows per tile
- SCY/SCX scroll: (LY + SCY) for Y, (pixel + SCX) for X
- BGP palette: 4 shades (0=white, 1=light, 2=dark, 3=black)
- Renders full BG line on mode 3 entry

### Task 4: Window layer
- Enabled by LCDC bit 5
- Position at WX/WY (WX offset by 7 per DMG convention)
- Uses tile map selected by LCDC bit 6
- Same tile data as BG (LCDC bit 4)
- Internal wy_counter increments per window scan line
- Overwrites BG pixels in window area

### Verification
- ✅ `zig build` — zero errors
- ✅ `zig build serial` — serial test passes
- ✅ No magic numbers in ppu.zig (all constants from addr.zig)

## Next
Proceed to Plan 03-02 (PPU sprites + OAM DMA + STAT IRQ refinements).
