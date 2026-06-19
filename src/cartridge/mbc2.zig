const std = @import("std");
const addr = @import("../addr.zig");

pub const Mbc2 = struct {
    rom: []const u8,
    ram: [addr.MBC2_RAM_SIZE]u8,
    rom_bank: u8,
    ram_enable: bool,
    title: [addr.CART_TITLE_LEN]u8,
    cart_type: u8,
    rom_size: u8,
    ram_size: u8,
    checksum_ok: bool,

    pub fn load(allocator: std.mem.Allocator, rom_bytes: []const u8) !Mbc2 {
        if (rom_bytes.len < addr.CART_MIN_SIZE) return error.RomTooSmall;
        if (rom_bytes.len > addr.CART_MAX_SIZE) return error.RomTooLarge;

        var title: [addr.CART_TITLE_LEN]u8 = .{0} ** addr.CART_TITLE_LEN;
        const title_len = @min(@as(usize, addr.CART_TITLE_LEN), rom_bytes.len - addr.CART_TITLE);
        @memcpy(title[0..title_len], rom_bytes[addr.CART_TITLE..][0..title_len]);

        const cart_type = rom_bytes[addr.CART_TYPE];
        const rom_size = rom_bytes[addr.CART_ROM_SIZE];
        const ram_size = rom_bytes[addr.CART_RAM_SIZE];
        const checksum = rom_bytes[addr.CART_CHECKSUM];

        var checksum_sum: u8 = 0;
        for (rom_bytes[addr.CART_CHECKSUM_BEGIN..addr.CART_CHECKSUM_END]) |b| checksum_sum +%= b;
        const checksum_ok = (checksum_sum +% checksum) == 0;
        if (!checksum_ok) {
            std.log.warn("header checksum mismatch: sum(0x{X:0>4}-0x{X:0>4}) = 0x{X:02}, expected 0x00", .{ addr.CART_CHECKSUM_BEGIN, addr.CART_CHECKSUM_END, checksum_sum +% checksum });
        }

        const rom = try allocator.alloc(u8, rom_bytes.len);
        @memcpy(rom, rom_bytes);

        return Mbc2{
            .rom = rom,
            .ram = .{0} ** addr.MBC2_RAM_SIZE,
            .rom_bank = addr.MBC2_INITIAL_BANK,
            .ram_enable = false,
            .title = title,
            .cart_type = cart_type,
            .rom_size = rom_size,
            .ram_size = ram_size,
            .checksum_ok = checksum_ok,
        };
    }

    pub fn deinit(self: *Mbc2, allocator: std.mem.Allocator) void {
        allocator.free(self.rom);
    }

    pub fn readRom(self: *Mbc2, address: u16) u8 {
        const index = @as(usize, address);
        if (address < addr.ROM_BANK_SIZE) {
            return if (index < self.rom.len) self.rom[index] else addr.UNMAPPED_READ;
        }
        const bank = self.rom_bank & addr.MBC2_ROM_BANK_MASK;
        const bank_offset = @as(usize, bank) * addr.ROM_BANK_SIZE + (index - addr.ROM_BANK_SIZE);
        return if (bank_offset < self.rom.len) self.rom[bank_offset] else addr.UNMAPPED_READ;
    }

    pub fn readRam(self: *Mbc2, address: u16) u8 {
        if (!self.ram_enable) return addr.UNMAPPED_READ;
        const ram_addr = address - addr.CART_RAM_BASE;
        if (ram_addr >= addr.MBC2_RAM_SIZE) return addr.UNMAPPED_READ;
        return self.ram[ram_addr] | addr.MBC2_RAM_READ_MASK;
    }

    pub fn writeRom(self: *Mbc2, address: u16, val: u8) void {
        if (address < addr.ROM_BANK_SIZE >> 6) { // 0x0000-0x00FF
            if ((address & addr.MBC2_BIT8) == 0) {
                self.ram_enable = (val & addr.LOW_NIBBLE_MASK) == addr.RAM_ENABLE_MAGIC;
            } else {
                self.rom_bank = val & addr.MBC2_ROM_BANK_MASK;
                if (self.rom_bank == 0) self.rom_bank = addr.MBC2_INITIAL_BANK;
            }
        } else if (address < addr.MBC2_REGION_END) {
            if ((address & addr.MBC2_BIT8) != 0) {
                self.rom_bank = val & addr.MBC2_ROM_BANK_MASK;
                if (self.rom_bank == 0) self.rom_bank = addr.MBC2_INITIAL_BANK;
            } else {
                self.ram_enable = (val & addr.LOW_NIBBLE_MASK) == addr.RAM_ENABLE_MAGIC;
            }
        }
    }

    pub fn writeRam(self: *Mbc2, address: u16, val: u8) void {
        if (!self.ram_enable) return;
        const ram_addr = address - addr.CART_RAM_BASE;
        if (ram_addr >= addr.MBC2_RAM_SIZE) return;
        self.ram[ram_addr] = val & addr.LOW_NIBBLE_MASK;
    }

    pub fn getRamSlice(self: *Mbc2) []u8 {
        return &self.ram;
    }
};
