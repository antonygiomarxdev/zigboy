const std = @import("std");
const addr = @import("../addr.zig");

pub const RomOnly = struct {
    rom: []const u8,
    title: [addr.CART_TITLE_LEN]u8,
    cart_type: u8,
    rom_size: u8,
    ram_size: u8,
    checksum: u8,
    checksum_ok: bool,

    pub fn load(allocator: std.mem.Allocator, rom_bytes: []const u8) !RomOnly {
        if (rom_bytes.len < addr.CART_MIN_SIZE) {
            return error.RomTooSmall;
        }

        if (rom_bytes.len > addr.CART_MAX_SIZE) {
            return error.RomTooLarge;
        }

        var title: [addr.CART_TITLE_LEN]u8 = .{0} ** 16;
        const title_len = @min(@as(usize, addr.CART_TITLE_LEN), rom_bytes.len - addr.CART_TITLE);
        @memcpy(title[0..title_len], rom_bytes[addr.CART_TITLE..][0..title_len]);

        const cart_type = rom_bytes[addr.CART_TYPE];
        const rom_size = rom_bytes[addr.CART_ROM_SIZE];
        const ram_size = rom_bytes[addr.CART_RAM_SIZE];
        const checksum = rom_bytes[addr.CART_CHECKSUM];

        var checksum_sum: u8 = 0;
        for (rom_bytes[addr.CART_CHECKSUM_BEGIN..addr.CART_CHECKSUM_END]) |b| {
            checksum_sum +%= b;
        }
        const checksum_ok = (checksum_sum +% checksum) == 0;
        if (!checksum_ok) {
            std.log.warn("header checksum mismatch: sum(0x134-0x14D) = 0x{X:02}, expected 0x00", .{checksum_sum +% checksum});
        }

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

    pub fn readRom(self: *RomOnly, address: u16) u8 {
        const index = @as(usize, address);
        if (index < self.rom.len) {
            return self.rom[index];
        }
        return 0xFF;
    }
};
