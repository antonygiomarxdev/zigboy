const std = @import("std");
const addr = @import("../addr.zig");

pub const Mbc1 = struct {
    rom: []const u8,
    ram: []u8,
    rom_bank_lo: u8,
    rom_bank_hi: u8,
    ram_bank: u8,
    mode_flag: bool,
    ram_enable: bool,
    title: [addr.CART_TITLE_LEN]u8,
    cart_type: u8,
    rom_size: u8,
    ram_size: u8,
    checksum_ok: bool,

    pub fn load(allocator: std.mem.Allocator, rom_bytes: []const u8) !Mbc1 {
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

        const ram_bank_count: usize = switch (ram_size) {
            addr.RAM_SIZE_0 => 0, addr.RAM_SIZE_1 => 1, addr.RAM_SIZE_2 => 1, addr.RAM_SIZE_4 => 4, else => 0,
        };
        const ram = try allocator.alloc(u8, ram_bank_count * addr.RAM_BANK_SIZE);

        return Mbc1{
            .rom = rom,
            .ram = ram,
            .rom_bank_lo = addr.MBC1_INITIAL_BANK,
            .rom_bank_hi = 0,
            .ram_bank = 0,
            .mode_flag = false,
            .ram_enable = false,
            .title = title,
            .cart_type = cart_type,
            .rom_size = rom_size,
            .ram_size = ram_size,
            .checksum_ok = checksum_ok,
        };
    }

    pub fn deinit(self: *Mbc1, allocator: std.mem.Allocator) void {
        allocator.free(self.rom);
        allocator.free(self.ram);
    }

    fn getCombinedRomBank(self: *Mbc1) u8 {
        const combined = (@as(u8, self.rom_bank_hi) << addr.MBC1_BANK_HI_SHIFT) | (self.rom_bank_lo & addr.MBC1_BANK_LO_MASK);
        if (combined == addr.MBC1_BANK_PROHIBITED_0 or
            combined == addr.MBC1_BANK_PROHIBITED_20 or
            combined == addr.MBC1_BANK_PROHIBITED_40 or
            combined == addr.MBC1_BANK_PROHIBITED_60) {
            return combined + 1;
        }
        return combined;
    }

    fn getEffectiveRomBank(self: *Mbc1) u8 {
        if (self.mode_flag) {
            return self.rom_bank_lo & addr.MBC1_BANK_LO_MASK;
        }
        return self.getCombinedRomBank();
    }

    fn getEffectiveRamBank(self: *Mbc1) u8 {
        if (self.mode_flag) {
            return self.ram_bank & addr.MBC1_RAM_BANK_MASK;
        }
        return 0;
    }

    pub fn readRom(self: *Mbc1, address: u16) u8 {
        const index = @as(usize, address);
        if (address < addr.ROM_BANK_SIZE) {
            return if (index < self.rom.len) self.rom[index] else addr.UNMAPPED_READ;
        }
        const bank = self.getEffectiveRomBank();
        const bank_offset = @as(usize, bank) * addr.ROM_BANK_SIZE + (index - addr.ROM_BANK_SIZE);
        return if (bank_offset < self.rom.len) self.rom[bank_offset] else addr.UNMAPPED_READ;
    }

    pub fn readRam(self: *Mbc1, address: u16) u8 {
        if (!self.ram_enable) return addr.UNMAPPED_READ;
        const bank = self.getEffectiveRamBank();
        const offset = @as(usize, bank) * addr.RAM_BANK_SIZE + (address - addr.CART_RAM_BASE);
        return if (offset < self.ram.len) self.ram[offset] else addr.UNMAPPED_READ;
    }

    pub fn writeRom(self: *Mbc1, address: u16, val: u8) void {
        switch (address >> 13) {
            0x00, 0x01 => {
                self.ram_enable = (val & addr.LOW_NIBBLE_MASK) == addr.RAM_ENABLE_MAGIC;
            },
            0x02, 0x03 => {
                self.rom_bank_lo = val & addr.MBC1_BANK_LO_MASK;
                if (self.rom_bank_lo == 0) self.rom_bank_lo = addr.MBC1_INITIAL_BANK;
            },
            0x04, 0x05 => {
                if (self.mode_flag) {
                    self.ram_bank = val & addr.MBC1_RAM_BANK_MASK;
                } else {
                    self.rom_bank_hi = val & addr.MBC1_RAM_BANK_MASK;
                }
            },
            0x06, 0x07 => {
                self.mode_flag = (val & addr.MBC1_MODE_FLAG_BIT) != 0;
            },
            else => {},
        }
    }

    pub fn writeRam(self: *Mbc1, address: u16, val: u8) void {
        if (!self.ram_enable) return;
        const bank = self.getEffectiveRamBank();
        const offset = @as(usize, bank) * addr.RAM_BANK_SIZE + (address - addr.CART_RAM_BASE);
        if (offset < self.ram.len) self.ram[offset] = val;
    }

    pub fn getRamSlice(self: *Mbc1) []u8 {
        return self.ram;
    }
};
