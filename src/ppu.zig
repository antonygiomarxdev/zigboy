const std = @import("std");
const addr = @import("addr.zig");
const Bus = @import("bus.zig").Bus;

pub const PpuMode = enum(u2) {
    hblank = 0,
    vblank = 1,
    oam_scan = 2,
    drawing = 3,
};

pub const Ppu = struct {
    mode: PpuMode,
    dot_counter: u16,
    framebuffer: [addr.FRAMEBUFFER_LEN]u8,
    vram: [addr.VRAM_SIZE]u8,
    oam: [addr.OAM_SIZE]u8,
    bus: *Bus,
    wy_counter: u8,
    window_rendered_this_line: bool,

    pub fn init(bus: *Bus) Ppu {
        var ppu = Ppu{
            .mode = .oam_scan,
            .dot_counter = 0,
            .framebuffer = undefined,
            .vram = undefined,
            .oam = undefined,
            .bus = bus,
            .wy_counter = 0,
            .window_rendered_this_line = false,
        };
        @memset(&ppu.framebuffer, addr.SHADE_WHITE);
        @memset(&ppu.vram, 0);
        @memset(&ppu.oam, 0);
        return ppu;
    }

    pub fn tick(self: *Ppu, mcycles: u4) void {
        const dots = @as(u16, mcycles) * addr.T_CYCLES_PER_M_CYCLE;
        self.stepDots(dots);
    }

    fn stepDots(self: *Ppu, dots: u16) void {
        const lcd_enabled = self.bus.mmio.LCDC & addr.LCDC_ENABLE != 0;

        if (!lcd_enabled) {
            if (self.bus.mmio.LY != 0 or self.dot_counter != 0) {
                self.bus.mmio.LY = 0;
                self.dot_counter = 0;
                self.mode = .oam_scan;
                self.bus.mmio.STAT = 0x00;
                self.wy_counter = 0;
            }
            return;
        }

        self.dot_counter += dots;

        while (self.dot_counter >= addr.DOTS_PER_LINE) {
            self.dot_counter -= addr.DOTS_PER_LINE;
            self.bus.mmio.LY +%= 1;

            if (self.bus.mmio.LY == addr.LY_VBLANK_START) {
                self.mode = .vblank;
                self.bus.mmio.IF |= addr.IF_VBLANK;
                self.updateStat();
            } else if (self.bus.mmio.LY > addr.LY_MAX) {
                self.bus.mmio.LY = 0;
                self.mode = .oam_scan;
                self.updateStat();
                self.wy_counter = 0;
            }
        }

        if (self.bus.mmio.LY < addr.LY_VBLANK_START) {
            const dot_pos = self.dot_counter;
            const old_mode = self.mode;
            const new_mode: PpuMode = if (dot_pos < addr.DOTS_OAM) .oam_scan else if (dot_pos < addr.DOTS_OAM + addr.DOTS_DRAWING) .drawing else .hblank;
            if (new_mode != old_mode) {
                self.mode = new_mode;
                self.updateStat();
                if (new_mode == .drawing) {
                    self.renderLine();
                }
            }
        }

        if (self.bus.mmio.LYC == self.bus.mmio.LY) {
            self.bus.mmio.STAT |= addr.STAT_LYC;
        } else {
            self.bus.mmio.STAT &= ~@as(u8, addr.STAT_LYC);
        }

        const stat = self.bus.mmio.STAT;
        if (stat & (addr.STAT_LYC_IRQ | addr.STAT_MODE0_IRQ | addr.STAT_MODE1_IRQ | addr.STAT_MODE2_IRQ) != 0) {
            const fire = (stat & addr.STAT_LYC_IRQ) != 0 and (stat & addr.STAT_LYC) != 0 or
                (stat & addr.STAT_MODE2_IRQ) != 0 and self.mode == .oam_scan or
                (stat & addr.STAT_MODE1_IRQ) != 0 and self.mode == .vblank or
                (stat & addr.STAT_MODE0_IRQ) != 0 and self.mode == .hblank;
            if (fire) {
                self.bus.mmio.IF |= addr.IF_LCD_STAT;
            }
        }
    }

    fn updateStat(self: *Ppu) void {
        self.bus.mmio.STAT = (self.bus.mmio.STAT & addr.STAT_MODE_CLEAR) | @as(u8, @intFromEnum(self.mode));
    }

    fn renderLine(self: *Ppu) void {
        const ly = self.bus.mmio.LY;
        self.window_rendered_this_line = false;

        if (self.bus.mmio.LCDC & addr.LCDC_BG_ENABLE != 0) {
            self.renderBgLine(ly);
        }

        const win_enabled = self.bus.mmio.LCDC & addr.LCDC_WIN_ENABLE != 0;
        if (win_enabled and ly >= self.bus.mmio.WY) {
            self.renderWindowLine(ly);
            self.wy_counter +%= 1;
            self.window_rendered_this_line = true;
        }
    }

    fn renderBgLine(self: *Ppu, ly: u8) void {
        const lcdc = self.bus.mmio.LCDC;
        const scy = self.bus.mmio.SCY;
        const scx = self.bus.mmio.SCX;
        const bgp = self.bus.mmio.BGP;

        const tile_map_base: u16 = if (lcdc & addr.LCDC_BG_MAP != 0) addr.TILE_MAP_1 else addr.TILE_MAP_0;

        const tile_y = (@as(u16, ly) + @as(u16, scy)) / addr.TILE_ROWS;
        const y_in_tile = (@as(u16, ly) + @as(u16, scy)) % addr.TILE_ROWS;

        for (0..addr.SCREEN_WIDTH) |x| {
            const tile_x = (@as(u16, @intCast(x)) + @as(u16, scx)) / addr.TILE_ROWS;
            const x_in_tile = (@as(u16, @intCast(x)) + @as(u16, scx)) % addr.TILE_ROWS;

            const map_addr = tile_map_base + (tile_y % addr.TILES_PER_MAP_ROW) * addr.TILES_PER_MAP_ROW + (tile_x % addr.TILES_PER_MAP_ROW);
            const tile_index = self.vram[map_addr - addr.VRAM_BASE];

            const effective_index: u16 = if (lcdc & addr.LCDC_BG_DATA != 0)
                addr.TILE_DATA_0 + @as(u16, tile_index) * addr.TILE_SIZE_BYTES
            else blk: {
                const signed_idx = @as(i16, @as(i8, @bitCast(@as(u8, tile_index))));
                const result = @as(i32, addr.TILE_DATA_1) + @as(i32, signed_idx) * addr.TILE_SIZE_BYTES;
                break :blk @as(u16, @intCast(result));
            };

            const row_offset = effective_index - addr.VRAM_BASE + y_in_tile * addr.TILE_BYTES_PER_ROW;
            const plane0 = self.vram[row_offset];
            const plane1 = self.vram[row_offset + 1];

            const bit = 7 - @as(u3, @truncate(x_in_tile));
            const color_id = ((plane1 >> bit) & 1) << 1 | ((plane0 >> bit) & 1);

            const shade = @as(u8, @truncate((bgp >> (@as(u3, @intCast(color_id)) * addr.PALETTE_SHIFT_PER_COLOR)) & addr.PALETTE_COLOR_MASK));
            const pixel: u8 = switch (shade) {
                0 => addr.SHADE_WHITE,
                1 => addr.SHADE_LIGHT,
                2 => addr.SHADE_DARK,
                3 => addr.SHADE_BLACK,
                else => addr.SHADE_WHITE,
            };

            self.framebuffer[ly * addr.SCREEN_WIDTH + x] = pixel;
        }
    }

    fn renderWindowLine(self: *Ppu, ly: u8) void {
        const lcdc = self.bus.mmio.LCDC;
        const bgp = self.bus.mmio.BGP;
        const wx = self.bus.mmio.WX;

        const tile_map_base: u16 = if (lcdc & addr.LCDC_WIN_MAP != 0) addr.TILE_MAP_1 else addr.TILE_MAP_0;

        const win_x_offset: u16 = if (wx >= addr.WX_OFFSET) @as(u16, wx) - addr.WX_OFFSET else 0;
        const win_y = @as(u16, self.wy_counter);
        const tile_y = win_y / addr.TILE_ROWS;
        const y_in_tile = win_y % addr.TILE_ROWS;

        for (0..addr.SCREEN_WIDTH) |x| {
            if (x < win_x_offset) continue;

            const win_x = x - win_x_offset;
            const tile_x = win_x / addr.TILE_ROWS;
            const x_in_tile = win_x % addr.TILE_ROWS;

            const map_addr = tile_map_base + (tile_y % addr.TILES_PER_MAP_ROW) * addr.TILES_PER_MAP_ROW + (tile_x % addr.TILES_PER_MAP_ROW);
            const tile_index = self.vram[map_addr - addr.VRAM_BASE];

            const effective_index: u16 = if (lcdc & addr.LCDC_BG_DATA != 0)
                addr.TILE_DATA_0 + @as(u16, tile_index) * addr.TILE_SIZE_BYTES
            else blk: {
                const signed_idx = @as(i16, @as(i8, @bitCast(@as(u8, tile_index))));
                const result = @as(i32, addr.TILE_DATA_1) + @as(i32, signed_idx) * addr.TILE_SIZE_BYTES;
                break :blk @as(u16, @intCast(result));
            };

            const row_offset = effective_index - addr.VRAM_BASE + y_in_tile * addr.TILE_BYTES_PER_ROW;
            const plane0 = self.vram[row_offset];
            const plane1 = self.vram[row_offset + 1];

            const bit = 7 - @as(u3, @truncate(x_in_tile));
            const color_id = ((plane1 >> bit) & 1) << 1 | ((plane0 >> bit) & 1);

            const shade = @as(u8, @truncate((bgp >> (@as(u3, @intCast(color_id)) * addr.PALETTE_SHIFT_PER_COLOR)) & addr.PALETTE_COLOR_MASK));
            const pixel: u8 = switch (shade) {
                0 => addr.SHADE_WHITE,
                1 => addr.SHADE_LIGHT,
                2 => addr.SHADE_DARK,
                3 => addr.SHADE_BLACK,
                else => addr.SHADE_WHITE,
            };

            self.framebuffer[ly * addr.SCREEN_WIDTH + x] = pixel;
        }
    }

    pub fn getFramebuffer(self: *Ppu) *const [addr.FRAMEBUFFER_LEN]u8 {
        return &self.framebuffer;
    }
};
