const std = @import("std");
const RomOnly = @import("cartridge/mod.zig").RomOnly;

// ── MMIO Packed Struct ───────────────────────────────────────────────

pub const MMIO = extern struct {
    JOYP: u8,                    // 0xFF00
    SB: u8,                      // 0xFF01
    SC: u8,                      // 0xFF02
    _pad_03: u8,                 // 0xFF03
    DIV: u8,                     // 0xFF04
    TIMA: u8,                    // 0xFF05
    TMA: u8,                     // 0xFF06
    TAC: u8,                     // 0xFF07
    _pad_08_0E: [7]u8,           // 0xFF08-0xFF0E
    IF: u8,                      // 0xFF0F
    _pad_10_3F: [48]u8,          // 0xFF10-0xFF3F (APU region)
    _pad_40_4F: [16]u8,          // 0xFF40-0xFF4F (PPU region)
    BANK: u8,                    // 0xFF50
    _pad_51_7E: [46]u8,          // 0xFF51-0xFF7E
    _pad_7F: u8,                 // 0xFF7F
    _pad_80_FE: [127]u8,         // 0xFF80-0xFFFE (HRAM — handled separately)
    IE: u8,                      // 0xFFFF
};

comptime {
    std.debug.assert(@sizeOf(MMIO) == 256);
    std.debug.assert(@offsetOf(MMIO, "JOYP") == 0x00);
    std.debug.assert(@offsetOf(MMIO, "SB") == 0x01);
    std.debug.assert(@offsetOf(MMIO, "SC") == 0x02);
    std.debug.assert(@offsetOf(MMIO, "DIV") == 0x04);
    std.debug.assert(@offsetOf(MMIO, "TIMA") == 0x05);
    std.debug.assert(@offsetOf(MMIO, "TMA") == 0x06);
    std.debug.assert(@offsetOf(MMIO, "TAC") == 0x07);
    std.debug.assert(@offsetOf(MMIO, "IF") == 0x0F);
    std.debug.assert(@offsetOf(MMIO, "BANK") == 0x50);
    std.debug.assert(@offsetOf(MMIO, "IE") == 0xFF);
}

// ── Bus Struct ───────────────────────────────────────────────────────

pub const Bus = struct {
    wram: [8 * 1024]u8,
    hram: [127]u8,
    vram_stub: [8 * 1024]u8,
    oam_stub: [160]u8,
    mmio: MMIO,
    cart: *RomOnly,
    serial_output: [256]u8,
    serial_index: usize,
    t_cycles: u64,

    pub fn init(cart: *RomOnly) Bus {
        var bus = Bus{
            .wram = undefined,
            .hram = undefined,
            .vram_stub = undefined,
            .oam_stub = undefined,
            .mmio = undefined,
            .cart = cart,
            .serial_output = undefined,
            .serial_index = 0,
            .t_cycles = 0,
        };
        @memset(&bus.wram, 0xFF);
        @memset(&bus.hram, 0xFF);
        @memset(&bus.vram_stub, 0xFF);
        @memset(&bus.oam_stub, 0xFF);
        @memset(&bus.serial_output, 0);
        bus.mmio = .{
            .JOYP = 0xCF,
            .SB = 0x00,
            .SC = 0x00,
            ._pad_03 = 0x00,
            .DIV = 0x00,
            .TIMA = 0x00,
            .TMA = 0x00,
            .TAC = 0x00,
            ._pad_08_0E = .{0} ** 7,
            .IF = 0xE0, // unused bits read as 1
            ._pad_10_3F = .{0} ** 48,
            ._pad_40_4F = .{0} ** 16,
            .BANK = 0x00,
            ._pad_51_7E = .{0} ** 46,
            ._pad_7F = 0x00,
            ._pad_80_FE = .{0} ** 127,
            .IE = 0x00,
        };
        return bus;
    }

    pub fn read8(self: *Bus, addr: u16) u8 {
        self.t_cycles += 4;
        return switch (addr >> 12) {
            0x0...0x7 => self.cart.readRom(addr),
            0x8...0x9 => self.vram_stub[addr - 0x8000],
            0xA...0xB => 0xFF, // cart RAM not present (ROM-only, open-bus)
            0xC...0xD => self.wram[addr - 0xC000],
            0xE => self.wram[addr - 0xE000], // Echo RAM mirror
            0xF => switch (addr) {
                0xFE00...0xFE9F => self.oam_stub[addr - 0xFE00],
                0xFEA0...0xFEFF => 0xFF, // unusable area, open-bus
                0xFF00...0xFF7F => self.mmioRead(@intCast(addr & 0xFF)),
                0xFF80...0xFFFE => self.hram[addr - 0xFF80],
                0xFFFF => self.mmio.IE,
                else => 0xFF,
            },
            else => 0xFF,
        };
    }

    pub fn write8(self: *Bus, addr: u16, val: u8) void {
        self.t_cycles += 4;
        switch (addr >> 12) {
            0x0...0x7 => {}, // ROM writes silently ignored (DMG behavior)
            0x8...0x9 => {}, // VRAM stub — writes silently ignored in Phase 1
            0xA...0xB => {}, // Cart RAM not present (ROM-only)
            0xC...0xD => self.wram[addr - 0xC000] = val,
            0xE => self.wram[addr - 0xE000] = val, // Echo RAM
            0xF => switch (addr) {
                0xFE00...0xFE9F => {}, // OAM stub — ignored in Phase 1
                0xFEA0...0xFEFF => {}, // Unusable area
                0xFF00...0xFF7F => self.mmioWrite(@intCast(addr & 0xFF), val),
                0xFF80...0xFFFE => self.hram[addr - 0xFF80] = val,
                0xFFFF => self.mmio.IE = val,
                else => {},
            },
            else => {},
        }
    }

    pub fn tick(self: *Bus, mcycles: u4) void {
        self.t_cycles += @as(u64, mcycles) * 4;
    }

    pub fn hasInterruptRequest(self: *Bus) bool {
        const ie = self.mmio.IE;
        const intf = self.mmio.IF;
        return (ie & intf & 0x1F) != 0;
    }

    pub fn readIF(self: *Bus) u8 {
        return self.mmio.IF;
    }

    pub fn writeIF(self: *Bus, val: u8) void {
        self.mmio.IF = val;
    }

    pub fn getSerialOutput(self: *Bus) []const u8 {
        return self.serial_output[0..self.serial_index];
    }

    pub fn getFrameBuffer(self: *Bus) *const [160 * 144]u8 {
        // Phase 1 stub — returns zeroed buffer
        // In Phase 3 this will point to the PPU framebuffer
        const buf = @as(*const [23040]u8, @ptrCast(&self.oam_stub));
        return buf;
    }

    fn mmioRead(self: *Bus, offset: u8) u8 {
        const bytes = std.mem.asBytes(&self.mmio);
        return switch (offset) {
            0x00 => bytes[offset] & 0x0F, // JOYP: only low 4 bits valid
            0x01 => bytes[offset], // SB
            0x02 => bytes[offset], // SC
            0x04 => 0x00, // DIV: static stub per D-15
            0x05 => 0x00, // TIMA: static stub
            0x06 => 0x00, // TMA: static stub
            0x07 => 0x00, // TAC: static stub
            0x0F => bytes[offset] | 0xE0, // IF: high 3 bits read as 1
            else => bytes[offset],
        };
    }

    fn mmioWrite(self: *Bus, offset: u8, val: u8) void {
        switch (offset) {
            0x00 => {
                // JOYP: only low bits writable
                const bytes = std.mem.asBytes(&self.mmio);
                bytes[0x00] = val & 0x0F;
            },
            0x01 => {
                // SB — serial data. Blargg writes characters here for output.
                if (self.serial_index < self.serial_output.len) {
                    self.serial_output[self.serial_index] = val;
                    self.serial_index += 1;
                }
                const bytes = std.mem.asBytes(&self.mmio);
                bytes[offset] = val;
            },
            0x02 => {
                // SC — serial control. Blargg writes 0x81 to trigger transfer.
                const bytes = std.mem.asBytes(&self.mmio);
                if (val & 0x81 == 0x81 and self.serial_index > 0) {
                    // Transfer complete — serial byte already captured in SB write
                    bytes[0x02] = 0x00; // Clear transfer flag
                } else {
                    bytes[0x02] = val;
                }
            },
            0x04, 0x05, 0x06, 0x07 => {
                // Timer stubs — writes accepted but values stay static per D-15
                const bytes = std.mem.asBytes(&self.mmio);
                bytes[offset] = val;
            },
            0x0F => {
                // IF: only low 5 bits writable
                const bytes = std.mem.asBytes(&self.mmio);
                bytes[0x0F] = val & 0x1F;
            },
            else => {
                const bytes = std.mem.asBytes(&self.mmio);
                bytes[offset] = val;
            },
        }
    }
};
