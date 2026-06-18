const std = @import("std");

pub const RomOnly = struct {
    rom: []const u8,
    title: [16]u8,
    cart_type: u8,
    rom_size: u8,
    ram_size: u8,
    checksum: u8,
    checksum_ok: bool,

    pub fn load(allocator: std.mem.Allocator, rom_bytes: []const u8) !RomOnly {
        if (rom_bytes.len < 0x0150) {
            return error.RomTooSmall;
        }

        // Check for oversized ROM (> 8 MiB cap per threat model T-01-05)
        if (rom_bytes.len > 8 * 1024 * 1024) {
            return error.RomTooLarge;
        }

        // Parse header fields
        var title: [16]u8 = .{0} ** 16;
        const title_len = @min(@as(usize, 16), rom_bytes.len - 0x0134);
        @memcpy(title[0..title_len], rom_bytes[0x0134..][0..title_len]);

        const cart_type = rom_bytes[0x0147];
        const rom_size = rom_bytes[0x0148];
        const ram_size = rom_bytes[0x0149];
        const checksum = rom_bytes[0x014D];

        // Compute header checksum (sum of bytes 0x0134-0x014C mod 0x100)
        var checksum_sum: u8 = 0;
        for (rom_bytes[0x0134..0x014C]) |b| {
            checksum_sum +%= b;
        }
        const checksum_ok = checksum_sum == checksum;
        if (!checksum_ok) {
            std.log.warn("header checksum mismatch: expected 0x{X:02}, got 0x{X:02}", .{
                checksum, checksum_sum,
            });
        }

        // Allocate and copy ROM bytes for owned storage
        const rom = try allocator.alloc(u8, rom_bytes.len);
        @memcpy(rom, rom_bytes);

        return RomOnly{
            .rom = rom,
            .title = title,
            .cart_type = cart_type,
            .rom_size = rom_size,
            .ram_size = ram_size,
            .checksum = checksum,
            .checksum_ok = checksum_ok,
        };
    }

    pub fn deinit(self: *RomOnly, allocator: std.mem.Allocator) void {
        allocator.free(self.rom);
    }

    pub fn readRom(self: *RomOnly, addr: u16) u8 {
        // ROM-only: no banking, addr maps directly into the ROM array.
        // For addresses beyond the loaded ROM, wrap or return 0xFF.
        const index = @as(usize, addr);
        if (index < self.rom.len) {
            return self.rom[index];
        }
        return 0xFF;
    }
};
