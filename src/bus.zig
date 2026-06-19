const std = @import("std");
const addr = @import("addr.zig");
const Cartridge = @import("cartridge/mod.zig").Cartridge;
const Ppu = @import("ppu.zig").Ppu;

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
    LCDC: u8,                    // 0xFF40
    STAT: u8,                    // 0xFF41
    SCY: u8,                     // 0xFF42
    SCX: u8,                     // 0xFF43
    LY: u8,                      // 0xFF44
    LYC: u8,                     // 0xFF45
    DMA: u8,                     // 0xFF46
    BGP: u8,                     // 0xFF47
    OBP0: u8,                    // 0xFF48
    OBP1: u8,                    // 0xFF49
    WY: u8,                      // 0xFF4A
    WX: u8,                      // 0xFF4B
    _pad_4C_4F: [addr.MMIO_PAD_4C_4F_SIZE]u8, // 0xFF4C-0xFF4F
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
    std.debug.assert(@offsetOf(MMIO, "LCDC") == addr.LCDC);
    std.debug.assert(@offsetOf(MMIO, "STAT") == addr.STAT);
    std.debug.assert(@offsetOf(MMIO, "SCY") == addr.SCY);
    std.debug.assert(@offsetOf(MMIO, "SCX") == addr.SCX);
    std.debug.assert(@offsetOf(MMIO, "LY") == addr.LY);
    std.debug.assert(@offsetOf(MMIO, "LYC") == addr.LYC);
    std.debug.assert(@offsetOf(MMIO, "DMA") == addr.DMA);
    std.debug.assert(@offsetOf(MMIO, "BGP") == addr.BGP);
    std.debug.assert(@offsetOf(MMIO, "OBP0") == addr.OBP0);
    std.debug.assert(@offsetOf(MMIO, "OBP1") == addr.OBP1);
    std.debug.assert(@offsetOf(MMIO, "WY") == addr.WY);
    std.debug.assert(@offsetOf(MMIO, "WX") == addr.WX);
    std.debug.assert(@offsetOf(MMIO, "BANK") == addr.BANK);
    std.debug.assert(@offsetOf(MMIO, "IE") == 0xFF);
}

// ── Bus Struct ───────────────────────────────────────────────────────

pub const Bus = struct {
    wram: [addr.WRAM_SIZE]u8,
    hram: [addr.HRAM_SIZE]u8,
    mmio: MMIO,
    ppu: Ppu,
    cart: *Cartridge,
    serial_output: [256]u8,
    serial_index: usize,
    t_cycles: u64,
    div_counter: u16,
    tima_counter: u16,
    action_buttons: u4,
    direction_buttons: u4,
    dma_active: bool,
    dma_source_high: u8,
    dma_index: u8,

    pub fn getTCycles(self: *Bus) u64 {
        return self.t_cycles;
    }

    pub fn init(cart: *Cartridge) Bus {
        var bus = Bus{
            .wram = undefined,
            .hram = undefined,
            .mmio = undefined,
            .ppu = undefined,
            .cart = cart,
            .serial_output = undefined,
            .serial_index = 0,
            .t_cycles = 0,
            .div_counter = 0,
            .tima_counter = 0,
            .action_buttons = 0x0F,
            .direction_buttons = 0x0F,
            .dma_active = false,
            .dma_source_high = 0,
            .dma_index = 0,
        };
        @memset(&bus.wram, addr.RAM_INIT_VALUE);
        @memset(&bus.hram, addr.RAM_INIT_VALUE);
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
            .LCDC = 0x00,
            .STAT = 0x00,
            .SCY = 0x00,
            .SCX = 0x00,
            .LY = 0x00,
            .LYC = 0x00,
            .DMA = 0x00,
            .BGP = 0x00,
            .OBP0 = 0x00,
            .OBP1 = 0x00,
            .WY = 0x00,
            .WX = 0x00,
            ._pad_4C_4F = .{0} ** addr.MMIO_PAD_4C_4F_SIZE,
            .BANK = 0x00,
            ._pad_51_7E = .{0} ** addr.MMIO_PAD_51_7E_SIZE,
            ._pad_7F = .{0} ** addr.MMIO_PAD_7F_SIZE,
            ._pad_80_FE = .{0} ** addr.HRAM_SIZE,
            .IE = 0x00,
        };
        bus.ppu = Ppu.init(&bus);
        return bus;
    }

    pub fn read8(self: *Bus, address: u16) u8 {
        self.t_cycles += addr.T_CYCLES_PER_M_CYCLE;
        return switch (address >> 12) {
            0x0...0x7 => self.cart.readRom(address),
            0x8...0x9 => blk: {
                if (self.ppu.mode == .drawing or self.ppu.mode == .oam_scan) {
                    break :blk addr.UNMAPPED_READ;
                }
                break :blk self.ppu.vram[address - addr.VRAM_BASE];
            },
            0xA...0xB => self.cart.readRam(address),
            0xC...0xD => self.wram[address - addr.WRAM_BASE],
            0xE => self.wram[address - addr.ECHO_BASE],
             0xF => switch (address) {
                addr.OAM_BASE...addr.OAM_END - 1 => blk: {
                    if (self.dma_active or self.ppu.mode == .drawing or self.ppu.mode == .oam_scan) {
                        break :blk addr.DMA_BLOCK_VAL;
                    }
                    break :blk self.ppu.oam[address - addr.OAM_BASE];
                },
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
            0x8...0x9 => {
                if (self.ppu.mode != .drawing) {
                    self.ppu.vram[address - addr.VRAM_BASE] = val;
                }
            },
            0xA...0xB => self.cart.writeRam(address, val),
            0xC...0xD => self.wram[address - addr.WRAM_BASE] = val,
            0xE => self.wram[address - addr.ECHO_BASE] = val,
             0xF => switch (address) {
                addr.OAM_BASE...addr.OAM_END - 1 => {
                    if (!self.dma_active and self.ppu.mode != .drawing and self.ppu.mode != .oam_scan) {
                        self.ppu.oam[address - addr.OAM_BASE] = val;
                    }
                },
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

        self.t_cycles += t_cycles_delta;

        // PPU advance
        self.ppu.tick(mcycles);

        // DIV: 16-bit counter increments every T-cycle
        // DIV register at 0xFF04 = counter >> 8 (upper 8 bits)
        self.div_counter +%= @as(u16, @truncate(t_cycles_delta));
        self.mmio.DIV = @truncate(self.div_counter >> 8);

        // OAM DMA: one byte per M-cycle from source page to OAM
        if (self.dma_active) {
            var i: u4 = 0;
            while (i < mcycles) : (i += 1) {
                if (self.dma_index < addr.DMA_TRANSFER_SIZE) {
                    self.dmaTransfer();
                } else {
                    self.dma_active = false;
                }
            }
        }

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

    fn dmaTransfer(self: *Bus) void {
        const src_addr = (@as(u16, self.dma_source_high) << addr.DMA_SOURCE_SHIFT) | @as(u16, self.dma_index);
        const byte = switch (src_addr >> 12) {
            0x0...0x7 => self.cart.readRom(src_addr),
            0x8...0x9 => self.ppu.vram[src_addr - addr.VRAM_BASE],
            0xA...0xB => self.cart.readRam(src_addr),
            0xC...0xD => self.wram[src_addr - addr.WRAM_BASE],
            0xE => self.wram[src_addr - addr.ECHO_BASE],
            0xF => if (src_addr >= addr.HRAM_BASE and src_addr < addr.HRAM_END)
                self.hram[src_addr - addr.HRAM_BASE]
            else if (src_addr == addr.IE_ADDR)
                self.mmio.IE
            else
                addr.UNMAPPED_READ,
            else => addr.UNMAPPED_READ,
        };
        self.ppu.oam[self.dma_index] = byte;
        self.dma_index += 1;
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
        return self.ppu.getFramebuffer();
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
            addr.DMA => {
                bytes[offset] = val;
                self.dma_active = true;
                self.dma_source_high = val;
                self.dma_index = 0;
            },
            addr.IF => bytes[addr.IF] = val & addr.INTERRUPT_MASK,
            else => bytes[offset] = val,
        }
    }
};
