const std = @import("std");
const addr = @import("addr.zig");
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
    std.debug.assert(@offsetOf(MMIO, "JOYP") == addr.JOYP);
    std.debug.assert(@offsetOf(MMIO, "SB") == addr.SB);
    std.debug.assert(@offsetOf(MMIO, "SC") == addr.SC);
    std.debug.assert(@offsetOf(MMIO, "DIV") == addr.DIV);
    std.debug.assert(@offsetOf(MMIO, "TIMA") == addr.TIMA);
    std.debug.assert(@offsetOf(MMIO, "TMA") == addr.TMA);
    std.debug.assert(@offsetOf(MMIO, "TAC") == addr.TAC);
    std.debug.assert(@offsetOf(MMIO, "IF") == addr.IF);
    std.debug.assert(@offsetOf(MMIO, "BANK") == addr.BANK);
    std.debug.assert(@offsetOf(MMIO, "IE") == 0xFF);
}

// ── Bus Struct ───────────────────────────────────────────────────────

pub const Bus = struct {
    wram: [addr.WRAM_SIZE]u8,
    hram: [addr.HRAM_SIZE]u8,
    vram_stub: [addr.VRAM_SIZE]u8,
    oam_stub: [addr.OAM_SIZE]u8,
    mmio: MMIO,
    cart: *RomOnly,
    serial_output: [256]u8,
    serial_index: usize,
    t_cycles: u64,

    pub fn getTCycles(self: *Bus) u64 {
        return self.t_cycles;
    }

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
            .JOYP = addr.JOYP_INIT,
            .SB = 0x00,
            .SC = 0x00,
            ._pad_03 = 0x00,
            .DIV = 0x00,
            .TIMA = 0x00,
            .TMA = 0x00,
            .TAC = 0x00,
            ._pad_08_0E = .{0} ** 7,
            .IF = addr.IF_INIT,
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

    pub fn read8(self: *Bus, address: u16) u8 {
        self.t_cycles += addr.T_CYCLES_PER_M_CYCLE;
        return switch (address >> 12) {
            0x0...0x7 => self.cart.readRom(address),
            0x8...0x9 => self.vram_stub[address - addr.VRAM_BASE],
            0xA...0xB => 0xFF,
            0xC...0xD => self.wram[address - addr.WRAM_BASE],
            0xE => self.wram[address - addr.ECHO_BASE],
            0xF => switch (address) {
                addr.OAM_BASE...addr.OAM_END - 1 => self.oam_stub[address - addr.OAM_BASE],
                addr.UNUSABLE_BASE...addr.UNUSABLE_END - 1 => 0xFF,
                addr.IO_BASE...addr.IO_END - 1 => self.mmioRead(@intCast(address & 0xFF)),
                addr.HRAM_BASE...addr.HRAM_END - 1 => self.hram[address - addr.HRAM_BASE],
                addr.IE_ADDR => self.mmio.IE,
                else => 0xFF,
            },
            else => 0xFF,
        };
    }

    pub fn write8(self: *Bus, address: u16, val: u8) void {
        self.t_cycles += addr.T_CYCLES_PER_M_CYCLE;
        switch (address >> 12) {
            0x0...0x7 => {},
            0x8...0x9 => {},
            0xA...0xB => {},
            0xC...0xD => self.wram[address - addr.WRAM_BASE] = val,
            0xE => self.wram[address - addr.ECHO_BASE] = val,
            0xF => switch (address) {
                addr.OAM_BASE...addr.OAM_END - 1 => {},
                addr.UNUSABLE_BASE...addr.UNUSABLE_END - 1 => {},
                addr.IO_BASE...addr.IO_END - 1 => self.mmioWrite(@intCast(address & 0xFF), val),
                addr.HRAM_BASE...addr.HRAM_END - 1 => self.hram[address - addr.HRAM_BASE] = val,
                addr.IE_ADDR => self.mmio.IE = val,
                else => {},
            },
            else => {},
        }
    }

    pub fn tick(self: *Bus, mcycles: u4) void {
        const prev_frames = self.t_cycles / addr.T_CYCLES_PER_FRAME;
        self.t_cycles += @as(u64, mcycles) * addr.T_CYCLES_PER_M_CYCLE;
        const new_frames = self.t_cycles / addr.T_CYCLES_PER_FRAME;
        if (new_frames > prev_frames) {
            self.mmio.IF |= addr.IF_VBLANK;
        }
    }

    pub fn hasInterruptRequest(self: *Bus) bool {
        const ie = self.mmio.IE;
        const intf = self.mmio.IF;
        return (ie & intf & addr.INTERRUPT_MASK) != 0;
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

    pub fn getSerialIndex(self: *Bus) usize {
        return self.serial_index;
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
            addr.JOYP => bytes[offset] & addr.LOW_NIBBLE_MASK,
            addr.SB => bytes[offset],
            addr.SC => bytes[offset],
            addr.DIV => 0x00,
            addr.TIMA => 0x00,
            addr.TMA => 0x00,
            addr.TAC => 0x00,
            addr.IF => bytes[offset] | addr.IF_UNUSED_BITS,
            else => bytes[offset],
        };
    }

    fn mmioWrite(self: *Bus, offset: u8, val: u8) void {
        const bytes = std.mem.asBytes(&self.mmio);
        switch (offset) {
            addr.JOYP => bytes[offset] = val & addr.LOW_NIBBLE_MASK,
            addr.SB => {
                if (self.serial_index < self.serial_output.len) {
                    self.serial_output[self.serial_index] = val;
                    self.serial_index += 1;
                }
                bytes[offset] = val;
            },
            addr.SC => {
                if ((val & addr.SC_TRANSFER) == addr.SC_TRANSFER and self.serial_index > 0) {
                    bytes[offset] = 0x00;
                } else {
                    bytes[offset] = val;
                }
            },
            addr.DIV, addr.TIMA, addr.TMA, addr.TAC => {
                bytes[offset] = val;
            },
            addr.IF => bytes[addr.IF] = val & addr.INTERRUPT_MASK,
            else => bytes[offset] = val,
        }
    }
};
