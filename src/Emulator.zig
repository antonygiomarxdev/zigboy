const std = @import("std");
const Cpu = @import("cpu.zig").Cpu;
const Cartridge = @import("cartridge/mod.zig").Cartridge;

pub const addr = @import("addr.zig");
pub const Bus = @import("bus.zig").Bus;

pub const Emulator = struct {
    cpu: Cpu,
    bus: Bus,
    cart: Cartridge,
    allocator: std.mem.Allocator,
    rom_slice: []const u8,
    framebuffer: [addr.FRAMEBUFFER_LEN]u8,

    pub fn init(allocator: std.mem.Allocator, rom_bytes: []const u8) !*Emulator {
        const self = try allocator.create(Emulator);
        errdefer allocator.destroy(self);

        const rom_slice = try allocator.alloc(u8, rom_bytes.len);
        @memcpy(rom_slice, rom_bytes);
        errdefer allocator.free(rom_slice);

        self.cart = try Cartridge.load(allocator, rom_slice);
        errdefer self.cart.deinit(allocator);

        self.bus = Bus.init(&self.cart);
        self.bus.ppu.fixupBus(&self.bus);
        self.cpu = Cpu.init(&self.bus);
        self.allocator = allocator;
        self.rom_slice = rom_slice;
        @memset(&self.framebuffer, 0xFF);

        return self;
    }

    pub fn deinit(self: *Emulator) void {
        self.cart.deinit(self.allocator);
        self.allocator.free(self.rom_slice);
        self.allocator.destroy(self);
    }

    pub fn stepInstruction(self: *Emulator) void {
        self.cpu.stepInstruction();
    }

    pub fn stepMCycle(self: *Emulator) void {
        self.cpu.stepMCycle();
    }

    pub fn runForFrames(self: *Emulator, frames: u32) void {
        const target_t_cycles = addr.T_CYCLES_PER_FRAME * frames;
        while (self.bus.getTCycles() < target_t_cycles) {
            self.stepMCycle();
        }
    }

    pub fn getSerialOutput(self: *Emulator) []const u8 {
        return self.bus.getSerialOutput();
    }

    pub fn getSerialIndex(self: *Emulator) usize {
        return self.bus.getSerialIndex();
    }

    pub fn getTCycles(self: *Emulator) u64 {
        return self.bus.getTCycles();
    }

    pub fn getFrameBuffer(self: *Emulator) *const [addr.FRAMEBUFFER_LEN]u8 {
        return self.bus.getFrameBuffer();
    }

    pub fn getPc(self: *Emulator) u16 {
        return self.cpu.getPc();
    }

    pub fn setButtonState(self: *Emulator, button: addr.JoypadButton, pressed: bool) void {
        const bit_val: u4 = if (pressed) 0 else 1;
        const bit_idx: u3 = @as(u3, @intCast(@intFromEnum(button) & 0x03));
        const mask: u4 = @as(u4, 1) << bit_idx;

        if (@intFromEnum(button) >= 4) {
            const old = self.bus.direction_buttons;
            const new = (old & ~mask) | (bit_val << bit_idx);
            if (old != new) {
                self.bus.mmio.IF |= addr.IF_JOYPAD;
            }
            self.bus.direction_buttons = new;
        } else {
            const old = self.bus.action_buttons;
            const new = (old & ~mask) | (bit_val << bit_idx);
            if (old != new) {
                self.bus.mmio.IF |= addr.IF_JOYPAD;
            }
            self.bus.action_buttons = new;
        }
    }
};

pub const CART_MAX_SIZE = addr.CART_MAX_SIZE;
