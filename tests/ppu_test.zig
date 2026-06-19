const std = @import("std");
const emu = @import("emulator");
const addr = emu.addr;

fn buildMinimalRom() [0x150]u8 {
    var rom: [0x150]u8 = @splat(0x00);
    var csum: u8 = 0;
    var i: u16 = 0x134;
    while (i < 0x14D) : (i += 1) csum +%= rom[i];
    rom[0x14D] = 0 -% csum;
    return rom;
}

test "sprite scan selected_count" {
    const allocator = std.testing.allocator;
    const rom_bytes = &buildMinimalRom();
    const rom_slice = try allocator.dupe(u8, rom_bytes);
    defer allocator.free(rom_slice);

    var gb = try emu.Emulator.init(allocator, rom_slice);
    defer gb.deinit();

    gb.bus.mmio.LCDC = addr.LCDC_ENABLE | addr.LCDC_OBJ_ENABLE;
    gb.bus.ppu.oam[0] = 16;
    gb.bus.ppu.oam[1] = 8;

    const lcdc = gb.bus.mmio.LCDC;
    const has_objs = (lcdc & addr.LCDC_OBJ_ENABLE) != 0;
    const sy = gb.bus.ppu.oam[0];
    const y_pixel = sy -% addr.SPRITE_Y_OFFSET;
    const sprite_height: u8 = 8;
    const on_line = 0 >= y_pixel and 0 < y_pixel + sprite_height;

    // Sanity: these should all be true
    try std.testing.expect(has_objs);
    try std.testing.expectEqual(@as(u8, 16), sy);
    try std.testing.expectEqual(@as(u8, 0), y_pixel);
    try std.testing.expect(on_line);

    // Verify bus pointer is correct
    try std.testing.expectEqual(&gb.bus, gb.bus.ppu.bus);

    gb.bus.ppu.scanOamSprites(0);
    try std.testing.expectEqual(@as(u8, 1), gb.bus.ppu.selected_count);
}

test "sprite rendering at top-left corner" {
    const allocator = std.testing.allocator;
    const rom_bytes = &buildMinimalRom();
    const rom_slice = try allocator.dupe(u8, rom_bytes);
    defer allocator.free(rom_slice);

    var gb = try emu.Emulator.init(allocator, rom_slice);
    defer gb.deinit();

    // Enable LCD + sprites, ensure BG is off so framebuffer starts white
    gb.bus.mmio.LCDC = addr.LCDC_ENABLE | addr.LCDC_OBJ_ENABLE;
    gb.bus.mmio.BGP = 0xE4;     // white/light/dark/black
    gb.bus.mmio.OBP0 = 0xE4;    // same palette
    gb.bus.mmio.LY = 0;

    // OAM entry 0: sprite at screen (0,0) using tile 0, no flips
    // Y=16 → screen row 0, X=8 → screen col 0
    gb.bus.ppu.oam[0] = 16;     // Y
    gb.bus.ppu.oam[1] = 8;      // X
    gb.bus.ppu.oam[2] = 0;      // tile index
    gb.bus.ppu.oam[3] = 0x00;   // flags (no priority, OBP0, no flips)

    // Tile 0 row 0: left pixel (bit 7) = color_id 1, rest = 0
    // plane0 row0 = 0x80 (bit 7 set), plane1 row0 = 0x00
    gb.bus.ppu.vram[0] = 0x80;  // plane0
    gb.bus.ppu.vram[1] = 0x00;  // plane1

    // Verify OAM data is intact
    try std.testing.expectEqual(@as(u8, 16), gb.bus.ppu.oam[0]);
    try std.testing.expectEqual(@as(u8, 8), gb.bus.ppu.oam[1]);

    // Scan OAM for line 0, then render sprites
    gb.bus.ppu.scanOamSprites(0);
    try std.testing.expectEqual(@as(u8, 1), gb.bus.ppu.selected_count);

    gb.bus.ppu.renderSprites(0);

    // Pixel at (0,0): leftmost sprite pixel, color_id = 1 → shade 1 → SHADE_LIGHT (0xAA)
    const fb_idx: usize = 0; // row 0, col 0
    try std.testing.expectEqual(addr.SHADE_LIGHT, gb.bus.ppu.framebuffer[fb_idx]);

    // Pixel at (1,0): color_id = 0 → transparent → unchanged white
    try std.testing.expectEqual(addr.SHADE_WHITE, gb.bus.ppu.framebuffer[1]);
}

test "sprite X-flip" {
    const allocator = std.testing.allocator;
    const rom_bytes = &buildMinimalRom();
    const rom_slice = try allocator.dupe(u8, rom_bytes);
    defer allocator.free(rom_slice);

    var gb = try emu.Emulator.init(allocator, rom_slice);
    defer gb.deinit();

    gb.bus.mmio.LCDC = addr.LCDC_ENABLE | addr.LCDC_OBJ_ENABLE;
    gb.bus.mmio.OBP0 = 0xE4;
    gb.bus.mmio.LY = 0;

    // Sprite at (0,0), tile 0, X-flip set
    gb.bus.ppu.oam[0] = 16;                  // Y
    gb.bus.ppu.oam[1] = 8;                   // X
    gb.bus.ppu.oam[2] = 0;                   // tile index
    gb.bus.ppu.oam[3] = addr.SPRITE_ATTR_X_FLIP; // X flip

    // Tile 0 row 0: only rightmost pixel (bit 0) = 1
    gb.bus.ppu.vram[0] = 0x01;  // plane0 bit 0 set
    gb.bus.ppu.vram[1] = 0x00;  // plane1

    gb.bus.ppu.scanOamSprites(0);
    gb.bus.ppu.renderSprites(0);

    // With X-flip, the rightmost pixel moves to the leftmost position
    // So pixel (0,0) should be non-white
    try std.testing.expectEqual(addr.SHADE_LIGHT, gb.bus.ppu.framebuffer[0]);
}

test "OAM DMA transfer from WRAM" {
    const allocator = std.testing.allocator;
    const rom_bytes = &buildMinimalRom();
    const rom_slice = try allocator.dupe(u8, rom_bytes);
    defer allocator.free(rom_slice);

    var gb = try emu.Emulator.init(allocator, rom_slice);
    defer gb.deinit();

    // Fill WRAM page at 0xC000 with a known pattern
    var i: u8 = 0;
    while (i < addr.DMA_TRANSFER_SIZE) : (i += 1) {
        gb.bus.wram[i] = i;
    }

    // Start OAM DMA from page 0xC0 (address 0xC000)
    gb.bus.write8(0xFF46, 0xC0);

    // Tick 160 M-cycles to complete DMA
    var j: u32 = 0;
    while (j < addr.DMA_TRANSFER_SIZE) : (j += 1) {
        gb.stepMCycle();
    }

    // Verify OAM matches WRAM data
    var k: u8 = 0;
    while (k < addr.DMA_TRANSFER_SIZE) : (k += 1) {
        try std.testing.expectEqual(k, gb.bus.ppu.oam[k]);
    }
}
