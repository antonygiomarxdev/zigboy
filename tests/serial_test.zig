const std = @import("std");
const emu = @import("emulator");

/// Minimal GB ROM that writes "Passed\n" to serial port then halts.
/// Generated at comptime to avoid needing a real ROM file.
fn buildSerialRom() [0x180]u8 {
    var rom: [0x180]u8 = @splat(0x00);

    // Cartridge header at 0x100
    rom[0x100] = 0x00; // NOP
    rom[0x101] = 0xC3; // JP entry
    rom[0x102] = 0x50;
    rom[0x103] = 0x01; // -> 0x0150

    // Cartridge name at 0x134
    const title = "SERIALTEST";
    @memcpy(rom[0x134..][0..title.len], title);

    // Cartridge type: 0x00 = ROM-ONLY
    rom[0x147] = 0x00;
    // ROM size: 0x00 = 32KB
    rom[0x148] = 0x00;

    // Header checksum (0x14D): boot ROM checks that
    // (sum of bytes 0x134-0x14C + byte at 0x14D) & 0xFF == 0
    var csum: u8 = 0;
    var i: u16 = 0x134;
    while (i < 0x14D) : (i += 1) {
        csum +%= rom[i];
    }
    rom[0x14D] = 0 -% csum;

    // Code at 0x150
    const msg = "Passed\n";
    var offset: u16 = 0x150;
    for (msg) |ch| {
        rom[offset] = 0x3E; offset += 1; // LD A, imm8
        rom[offset] = ch;   offset += 1; // (character)
        rom[offset] = 0xE0; offset += 1; // LDH (0xFF01), A
        rom[offset] = 0x01; offset += 1;
        // Don't bother with SC — capture happens on SB write
    }

    // Infinite loop
    rom[offset] = 0x18; offset += 1; // JR -2
    rom[offset] = 0xFE; offset += 1;

    return rom;
}

test "serial output capture" {
    const allocator = std.testing.allocator;
    const rom_bytes = &buildSerialRom();
    const rom_slice = try allocator.dupe(u8, rom_bytes);
    defer allocator.free(rom_slice);

    var gameboy = try emu.Emulator.init(allocator, rom_slice);
    defer gameboy.deinit();

    // Run enough cycles to execute the serial writes
    var i: u32 = 0;
    while (i < 10000) : (i += 1) {
        gameboy.stepMCycle();
    }

    const output = gameboy.getSerialOutput();
    try std.testing.expect(std.mem.indexOf(u8, output, "Passed") != null);
}
