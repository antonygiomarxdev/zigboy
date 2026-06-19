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
    selected_sprites: [addr.SPRITES_MAX_PER_LINE]u8,
    selected_count: u8,

    pub fn fixupBus(self: *Ppu, bus: *Bus) void {
        self.bus = bus;
    }

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
            .selected_sprites = undefined,
            .selected_count = 0,
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
                self.bus.mmio.STAT = addr.STAT_INIT_VAL;
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
                self.scanOamSprites(0);
            }
        }

        if (self.bus.mmio.LY < addr.LY_VBLANK_START) {
            const dot_pos = self.dot_counter;
            const old_mode = self.mode;
            const new_mode: PpuMode = if (dot_pos < addr.DOTS_OAM) .oam_scan else if (dot_pos < addr.DOTS_OAM + addr.DOTS_DRAWING) .drawing else .hblank;
            if (new_mode != old_mode) {
                self.mode = new_mode;
                self.updateStat();
                if (new_mode == .oam_scan) {
                    self.scanOamSprites(self.bus.mmio.LY);
                }
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

        self.renderSprites(ly);
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

            const bit = addr.SPRITE_MAX_COL - @as(u3, @truncate(x_in_tile));
            const color_id = ((plane1 >> bit) & 1) << 1 | ((plane0 >> bit) & 1);

            const shade = @as(u8, @truncate((bgp >> (@as(u3, @intCast(color_id)) * addr.PALETTE_SHIFT_PER_COLOR)) & addr.PALETTE_COLOR_MASK));
            const pixel: u8 = switch (shade) {
                addr.PAL_ID_WHITE => addr.SHADE_WHITE,
                addr.PAL_ID_LIGHT => addr.SHADE_LIGHT,
                addr.PAL_ID_DARK => addr.SHADE_DARK,
                addr.PAL_ID_BLACK => addr.SHADE_BLACK,
                else => addr.SHADE_WHITE,
            };

            const fb_idx = @as(usize, ly) * addr.SCREEN_WIDTH + x;
            self.framebuffer[fb_idx] = pixel;
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

            const bit = addr.SPRITE_MAX_COL - @as(u3, @truncate(x_in_tile));
            const color_id = ((plane1 >> bit) & 1) << 1 | ((plane0 >> bit) & 1);

            const shade = @as(u8, @truncate((bgp >> (@as(u3, @intCast(color_id)) * addr.PALETTE_SHIFT_PER_COLOR)) & addr.PALETTE_COLOR_MASK));
            const pixel: u8 = switch (shade) {
                addr.PAL_ID_WHITE => addr.SHADE_WHITE,
                addr.PAL_ID_LIGHT => addr.SHADE_LIGHT,
                addr.PAL_ID_DARK => addr.SHADE_DARK,
                addr.PAL_ID_BLACK => addr.SHADE_BLACK,
                else => addr.SHADE_WHITE,
            };

            const fb_idx = @as(usize, ly) * addr.SCREEN_WIDTH + x;
            self.framebuffer[fb_idx] = pixel;
        }
    }

    pub fn scanOamSprites(self: *Ppu, ly: u8) void {
        const lcdc = self.bus.mmio.LCDC;
        if (lcdc & addr.LCDC_OBJ_ENABLE == 0) {
            self.selected_count = 0;
            return;
        }

        const sprite_height: u8 = if (lcdc & addr.LCDC_OBJ_SIZE != 0) addr.SPRITE_HEIGHT_16 else addr.SPRITE_HEIGHT_8;
        self.selected_count = 0;

        var i: u8 = 0;
        while (i < addr.SPRITE_NUM_ENTRIES and self.selected_count < addr.SPRITES_MAX_PER_LINE) : (i += 1) {
            const sy = self.oam[i * addr.SPRITE_ENTRY_SIZE];
            const y_pixel = sy -% addr.SPRITE_Y_OFFSET;
            if (ly >= y_pixel and ly < y_pixel + sprite_height) {
                self.selected_sprites[self.selected_count] = i;
                self.selected_count += 1;
            }
        }
    }

    pub fn renderSprites(self: *Ppu, ly: u8) void {
        const lcdc = self.bus.mmio.LCDC;
        if (lcdc & addr.LCDC_OBJ_ENABLE == 0) return;
        if (self.selected_count == 0) return;

        const sprite_height: u8 = if (lcdc & addr.LCDC_OBJ_SIZE != 0) addr.SPRITE_HEIGHT_16 else addr.SPRITE_HEIGHT_8;

        // Sort selected sprites by priority: lower X first; if same X, lower index first
        var sorted: [addr.SPRITES_MAX_PER_LINE]u8 = undefined;
        @memcpy(sorted[0..self.selected_count], self.selected_sprites[0..self.selected_count]);
        const count = self.selected_count;

        {
            var i: usize = 0;
            while (i < count) : (i += 1) {
                var j: usize = i + 1;
                while (j < count) : (j += 1) {
                    const ax = self.oam[sorted[i] * addr.SPRITE_ENTRY_SIZE + 1];
                    const bx = self.oam[sorted[j] * addr.SPRITE_ENTRY_SIZE + 1];
                    if (ax > bx or (ax == bx and sorted[i] > sorted[j])) {
                        const tmp = sorted[i];
                        sorted[i] = sorted[j];
                        sorted[j] = tmp;
                    }
                }
            }
        }

        for (0..addr.SCREEN_WIDTH) |x| {
            var best_color_id: u2 = 0;
            var best_priority: bool = false;
            var best_palette: bool = false;
            var found: bool = false;

            for (sorted[0..count]) |sprite_idx| {
                const sx = self.oam[sprite_idx * addr.SPRITE_ENTRY_SIZE + 1];
                if (sx == 0) continue;
                const x_pixel = sx -% addr.SPRITE_X_OFFSET;
                if (x < x_pixel or x >= x_pixel + addr.SPRITE_WIDTH) continue;

                const sy = self.oam[sprite_idx * addr.SPRITE_ENTRY_SIZE];
                const y_pixel = sy -% addr.SPRITE_Y_OFFSET;
                if (ly < y_pixel) continue;
                const y_in_sprite = ly - y_pixel;
                if (y_in_sprite >= sprite_height) continue;

                const flags = self.oam[sprite_idx * addr.SPRITE_ENTRY_SIZE + 3];
                const tile_index = self.oam[sprite_idx * addr.SPRITE_ENTRY_SIZE + 2];

                var sprite_row = y_in_sprite;
                if (flags & addr.SPRITE_ATTR_Y_FLIP != 0) {
                    sprite_row = sprite_height - 1 - y_in_sprite;
                }

                const effective_tile = if (sprite_height == addr.SPRITE_HEIGHT_16)
                    if (sprite_row < addr.SPRITE_HEIGHT_8) tile_index & addr.SPRITE_TILE_MASK else tile_index | addr.SPRITE_TILE_LSB
                else
                    tile_index;

                const tile_row = if (sprite_height == addr.SPRITE_HEIGHT_16)
                    sprite_row % addr.SPRITE_HEIGHT_8
                else
                    sprite_row;

                const tile_addr = addr.VRAM_BASE + @as(u16, effective_tile) * addr.TILE_SIZE_BYTES + @as(u16, tile_row) * addr.TILE_BYTES_PER_ROW;
                const vram_offset = tile_addr - addr.VRAM_BASE;

                var x_in_sprite = @as(u3, @truncate(x - x_pixel));
                if (flags & addr.SPRITE_ATTR_X_FLIP != 0) {
                    x_in_sprite = (addr.SPRITE_WIDTH - 1) - x_in_sprite;
                }
                const bit = (addr.SPRITE_WIDTH - 1) - x_in_sprite;

                const plane0 = self.vram[vram_offset];
                const plane1 = self.vram[vram_offset + 1];
                const color_id: u2 = @truncate(((plane1 >> bit) & 1) << 1 | ((plane0 >> bit) & 1));

                if (color_id == 0) continue;

                best_color_id = color_id;
                best_priority = flags & addr.SPRITE_ATTR_PRIORITY != 0;
                best_palette = flags & addr.SPRITE_ATTR_PALETTE != 0;
                found = true;
                break;
            }

            if (found) {
                const palette = if (best_palette) self.bus.mmio.OBP1 else self.bus.mmio.OBP0;
                const shade = @as(u8, @truncate((palette >> (@as(u3, @intCast(best_color_id)) * addr.PALETTE_SHIFT_PER_COLOR)) & addr.PALETTE_COLOR_MASK));
                const pixel: u8 = switch (shade) {
                    0 => addr.SHADE_WHITE,
                    1 => addr.SHADE_LIGHT,
                    2 => addr.SHADE_DARK,
                    3 => addr.SHADE_BLACK,
                    else => addr.SHADE_WHITE,
                };

                const fb_idx = @as(usize, ly) * addr.SCREEN_WIDTH + x;
                if (best_priority) {
                    if (self.framebuffer[fb_idx] == addr.SHADE_WHITE) {
                        self.framebuffer[fb_idx] = pixel;
                    }
                } else {
                    self.framebuffer[fb_idx] = pixel;
                }
            }
        }
    }

    pub fn getFramebuffer(self: *Ppu) *const [addr.FRAMEBUFFER_LEN]u8 {
        return &self.framebuffer;
    }
};
