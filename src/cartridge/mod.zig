const std = @import("std");
const addr = @import("../addr.zig");
const RomOnly = @import("rom_only.zig").RomOnly;
const Mbc1 = @import("mbc1.zig").Mbc1;
const Mbc2 = @import("mbc2.zig").Mbc2;
const Mbc3 = @import("mbc3.zig").Mbc3;
const Mbc5 = @import("mbc5.zig").Mbc5;

pub const Cartridge = union(enum) {
    rom_only: RomOnly,
    mbc1: Mbc1,
    mbc2: Mbc2,
    mbc3: Mbc3,
    mbc5: Mbc5,

    pub fn load(allocator: std.mem.Allocator, rom_bytes: []const u8) !Cartridge {
        const cart_type = rom_bytes[addr.CART_TYPE];
        return switch (cart_type) {
            addr.CART_TYPE_ROM_ONLY => Cartridge{ .rom_only = try RomOnly.load(allocator, rom_bytes) },
            addr.CART_TYPE_MBC1, addr.CART_TYPE_MBC1_RAM, addr.CART_TYPE_MBC1_RAM_BATT => Cartridge{ .mbc1 = try Mbc1.load(allocator, rom_bytes) },
            addr.CART_TYPE_MBC2, addr.CART_TYPE_MBC2_BATT => Cartridge{ .mbc2 = try Mbc2.load(allocator, rom_bytes) },
            addr.CART_TYPE_MBC3, addr.CART_TYPE_MBC3_RAM, addr.CART_TYPE_MBC3_RAM_BATT, addr.CART_TYPE_MBC3_TIMER_BATT => Cartridge{ .mbc3 = try Mbc3.load(allocator, rom_bytes) },
            addr.CART_TYPE_MBC5, addr.CART_TYPE_MBC5_RAM, addr.CART_TYPE_MBC5_RAM_BATT, addr.CART_TYPE_MBC5_RUMBLE, addr.CART_TYPE_MBC5_RUMBLE_RAM, addr.CART_TYPE_MBC5_RUMBLE_RAM_BATT => Cartridge{ .mbc5 = try Mbc5.load(allocator, rom_bytes) },
            else => Cartridge{ .rom_only = try RomOnly.load(allocator, rom_bytes) },
        };
    }

    pub fn deinit(self: *Cartridge, allocator: std.mem.Allocator) void {
        switch (self.*) {
            inline else => |*c| c.deinit(allocator),
        }
    }

    pub fn readRom(self: *Cartridge, address: u16) u8 {
        return switch (self.*) {
            inline else => |*c| c.readRom(address),
        };
    }

    pub fn readRam(self: *Cartridge, address: u16) u8 {
        return switch (self.*) {
            inline else => |*c| c.readRam(address),
        };
    }

    pub fn writeRom(self: *Cartridge, address: u16, val: u8) void {
        switch (self.*) {
            inline else => |*c| c.writeRom(address, val),
        }
    }

    pub fn writeRam(self: *Cartridge, address: u16, val: u8) void {
        switch (self.*) {
            inline else => |*c| c.writeRam(address, val),
        }
    }

    pub fn getRamSlice(self: *Cartridge) []u8 {
        return switch (self.*) {
            inline else => |*c| c.getRamSlice(),
        };
    }

    pub fn hasBattery(self: *const Cartridge) bool {
        return switch (self.*) {
            .rom_only => false,
            .mbc1 => |c| c.cart_type == addr.CART_TYPE_MBC1_RAM_BATT,
            .mbc2 => |c| c.cart_type == addr.CART_TYPE_MBC2_BATT,
            .mbc3 => |c| c.cart_type == addr.CART_TYPE_MBC3_RAM_BATT or c.cart_type == addr.CART_TYPE_MBC3_TIMER_BATT,
            .mbc5 => |c| c.cart_type == addr.CART_TYPE_MBC5_RAM_BATT or c.cart_type == addr.CART_TYPE_MBC5_RUMBLE_RAM_BATT,
        };
    }

    pub fn title(self: *const Cartridge) []const u8 {
        return switch (self.*) {
            inline else => |c| &c.title,
        };
    }

    pub fn checksumOk(self: *const Cartridge) bool {
        return switch (self.*) {
            inline else => |c| c.checksum_ok,
        };
    }

    pub fn cartType(self: *const Cartridge) u8 {
        return switch (self.*) {
            inline else => |c| c.cart_type,
        };
    }
};
