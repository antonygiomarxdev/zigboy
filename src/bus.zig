const std = @import("std");
const addr = @import("addr.zig");
const Cartridge = @import("cartridge/mod.zig").Cartridge;

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
    _pad_08_0E: [addr.MMIO_PAD_08_0E_SIZE]u8, // 0xFF08-0xFF0E
    IF: u8,                      // 0xFF0F
    _pad_10_3F: [addr.MMIO_APU_SIZE]u8, // 0xFF10-0xFF3F (APU region)
    _pad_40_4F: [addr.MMIO_PPU_SIZE]u8, // 0xFF40-0xFF4F (PPU region)
    BANK: u8,                    // 0xFF50
    _pad_51_7E: [addr.MMIO_PAD_51_7E_SIZE]u8, // 0xFF51-0xFF7E
    _pad_7F: [addr.MMIO_PAD_7F_SIZE]u8, // 0xFF7F
    _pad_80_FE: [addr.HRAM_SIZE]u8, // 0xFF80-0xFFFE (HRAM — handled separately)
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
    cart: *Cartridge,
    serial_output: [256]u8,
    serial_index: usize,
    t_cycles: u64,
    div_counter: u16,
    tima_counter: u16,
    action_buttons: u4,
    direction_buttons: u4,

    pub fn getTCycles(self: *Bus) u64 {
        return self.t_cycles;
    }

    pub fn init(cart: *Cartridge) Bus {
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
            .div_counter = 0,
            .tima_counter = 0,
            .action_buttons = 0x0F,
            .direction_buttons = 0x0F,
        };
        @memset(&bus.wram, addr.RAM_INIT_VALUE);
        @memset(&bus.hram, addr.RAM_INIT_VALUE);
        @memset(&bus.vram_stub, addr.RAM_INIT_VALUE);
        @memset(&bus.oam_stub, addr.RAM_INIT_VALUE);
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
            ._pad_08_0E = .{0} ** addr.MMIO_PAD_08_0E_SIZE,
            .IF = addr.IF_INIT,
            ._pad_10_3F = .{0} ** addr.MMIO_APU_SIZE,
            ._pad_40_4F = .{0} ** addr.MMIO_PPU_SIZE,
            .BANK = 0x00,
            ._pad_51_7E = .{0} ** addr.MMIO_PAD_51_7E_SIZE,
            ._pad_7F = .{0} ** addr.MMIO_PAD_7F_SIZE,
            ._pad_80_FE = .{0} ** addr.HRAM_SIZE,
            .IE = 0x00,
        };
        return bus;
    }

    pub fn read8(self: *Bus, address: u16) u8 {
        self.t_cycles += addr.T_CYCLES_PER_M_CYCLE;
        return switch (address >> 12) {
            0x0...0x7 => self.cart.readRom(address),
            0x8...0x9 => self.vram_stub[address - addr.VRAM_BASE],
            0xA...0xB => self.cart.readRam(address),
            0xC...0xD => self.wram[address - addr.WRAM_BASE],
            0xE => self.wram[address - addr.ECHO_BASE],
            0xF => switch (address) {
                addr.OAM_BASE...addr.OAM_END - 1 => self.oam_stub[address - addr.OAM_BASE],
                addr.UNUSABLE_BASE...addr.UNUSABLE_END - 1 => addr.UNMAPPED_READ,
                addr.IO_BASE...addr.IO_END - 1 => self.mmioRead(@intCast(address & addr.LOW_BYTE_MASK)),
                addr.HRAM_BASE...addr.HRAM_END - 1 => self.hram[address - addr.HRAM_BASE],
                addr.IE_ADDR => self.mmio.IE,
                else => addr.UNMAPPED_READ,
            },
            else => addr.UNMAPPED_READ,
        };
    }

    pub fn write8(self: *Bus, address: u16, val: u8) void {
        self.t_cycles += addr.T_CYCLES_PER_M_CYCLE;
        switch (address >> 12) {
            0x0...0x7 => self.cart.writeRom(address, val),
            0x8...0x9 => {},
            0xA...0xB => self.cart.writeRam(address, val),
            0xC...0xD => self.wram[address - addr.WRAM_BASE] = val,
            0xE => self.wram[address - addr.ECHO_BASE] = val,
            0xF => switch (address) {
                addr.OAM_BASE...addr.OAM_END - 1 => {},
                addr.UNUSABLE_BASE...addr.UNUSABLE_END - 1 => {},
                addr.IO_BASE...addr.IO_END - 1 => self.mmioWrite(@intCast(address & addr.LOW_BYTE_MASK), val),
                addr.HRAM_BASE...addr.HRAM_END - 1 => self.hram[address - addr.HRAM_BASE] = val,
                addr.IE_ADDR => self.mmio.IE = val,
                else => {},
            },
            else => {},
        }
    }

    pub fn tick(self: *Bus, mcycles: u4) void {
        const t_cycles_delta = @as(u64, mcycles) * addr.T_CYCLES_PER_M_CYCLE;

        // VBlank check
        const prev_frames = self.t_cycles / addr.T_CYCLES_PER_FRAME;
        self.t_cycles += t_cycles_delta;
        const new_frames = self.t_cycles / addr.T_CYCLES_PER_FRAME;
        if (new_frames > prev_frames) {
            self.mmio.IF |= addr.IF_VBLANK;
        }

        // DIV: 16-bit counter increments every T-cycle
        // DIV register at 0xFF04 = counter >> 8 (upper 8 bits)
        self.div_counter +%= @as(u16, @truncate(t_cycles_delta));
        self.mmio.DIV = @truncate(self.div_counter >> 8);

        // TIMA: increments at TAC-selected rate when enabled
        if (self.mmio.TAC & addr.TIMER_TAC_ENABLE != 0) {
            self.tima_counter +%= @as(u16, @truncate(t_cycles_delta));
            const threshold: u16 = switch (self.mmio.TAC & addr.TIMER_TAC_CLOCK_MASK) {
                0b00 => addr.TIMER_CLOCK_1024,
                0b01 => addr.TIMER_CLOCK_16,
                0b10 => addr.TIMER_CLOCK_64,
                0b11 => addr.TIMER_CLOCK_256,
                else => unreachable,
            };
            while (self.tima_counter >= threshold) {
                self.tima_counter -= threshold;
                self.mmio.TIMA +%= 1;
                if (self.mmio.TIMA == 0) {
                    self.mmio.TIMA = self.mmio.TMA;
                    self.mmio.IF |= addr.IF_TIMER;
                }
            }
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

    pub fn getFrameBuffer(self: *Bus) *const [addr.FRAMEBUFFER_LEN]u8 {
        // Phase 1 stub — returns zeroed buffer
        // In Phase 3 this will point to the PPU framebuffer
        const buf = @as(*const [addr.FRAMEBUFFER_LEN]u8, @ptrCast(&self.oam_stub));
        return buf;
    }

    fn mmioRead(self: *Bus, offset: u8) u8 {
        const bytes = std.mem.asBytes(&self.mmio);
        return switch (offset) {
            addr.JOYP => blk: {
                const sel = self.mmio.JOYP & (addr.JOYP_SELECT_ACTION | addr.JOYP_SELECT_DIRECTION);
                const matrix: u4 = if (sel & addr.JOYP_SELECT_ACTION == 0 and sel & addr.JOYP_SELECT_DIRECTION == 0)
                    self.action_buttons & self.direction_buttons
                else if (sel & addr.JOYP_SELECT_ACTION == 0)
                    self.action_buttons
                else if (sel & addr.JOYP_SELECT_DIRECTION == 0)
                    self.direction_buttons
                else
                    0x0F;
                break :blk addr.JOYP_UNUSED_BITS | sel | @as(u8, matrix);
            },
            addr.SB => bytes[offset],
            addr.SC => bytes[offset],
            addr.DIV => bytes[offset],
            addr.TIMA => bytes[offset],
            addr.TMA => bytes[offset],
            addr.TAC => bytes[offset],
            addr.IF => bytes[offset] | addr.IF_UNUSED_BITS,
            else => bytes[offset],
        };
    }

    fn mmioWrite(self: *Bus, offset: u8, val: u8) void {
        const bytes = std.mem.asBytes(&self.mmio);
        switch (offset) {
            addr.JOYP => self.mmio.JOYP = (val & (addr.JOYP_SELECT_ACTION | addr.JOYP_SELECT_DIRECTION)) | addr.JOYP_UNUSED_BITS | 0x0F,
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
            addr.DIV => {
                bytes[offset] = 0x00;
                self.div_counter = 0;
                self.tima_counter = 0;
            },
            addr.TIMA, addr.TMA, addr.TAC => {
                bytes[offset] = val;
            },
            addr.IF => bytes[addr.IF] = val & addr.INTERRUPT_MASK,
            else => bytes[offset] = val,
        }
    }
};
