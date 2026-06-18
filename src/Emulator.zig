const std = @import("std");
const Cpu = @import("cpu.zig").Cpu;
const Bus = @import("bus.zig").Bus;
const RomOnly = @import("cartridge/mod.zig").RomOnly;

pub const Emulator = struct {
    cpu: Cpu,
    bus: Bus,
    cart: RomOnly,
    allocator: std.mem.Allocator,
    rom_slice: []const u8,
    framebuffer: [160 * 144]u8,

    pub fn init(allocator: std.mem.Allocator, rom_bytes: []const u8) !Emulator {
        // Copy ROM bytes into owned allocation
        const rom_slice = try allocator.alloc(u8, rom_bytes.len);
        @memcpy(rom_slice, rom_bytes);
        errdefer allocator.free(rom_slice);

        // Initialize cartridge (load and parse header)
        var cart = try RomOnly.load(allocator, rom_slice);
        errdefer cart.deinit(allocator);

        // Initialize bus (references the cartridge)
        var bus = Bus.init(&cart);

        // Initialize CPU (references the bus)
        const cpu = Cpu.init(&bus);

        var fb: [160 * 144]u8 = undefined;
        @memset(&fb, 0xFF); // White framebuffer (no PPU yet)

        return Emulator{
            .cpu = cpu,
            .bus = bus,
            .cart = cart,
            .allocator = allocator,
            .rom_slice = rom_slice,
            .framebuffer = fb,
        };
    }

    pub fn deinit(self: *Emulator) void {
        self.allocator.free(self.rom_slice);
    }

    /// Step one full instruction (may take 1-6 M-cycles).
    pub fn stepInstruction(self: *Emulator) void {
        self.cpu.stepInstruction();
    }

    /// Step one M-cycle (4 T-cycles). Fine-grained control.
    pub fn stepMCycle(self: *Emulator) void {
        self.cpu.stepMCycle();
    }

    /// Run the emulator for approximately N frames.
    /// Each frame is ~17556 M-cycles (70224 dots / 4).
    pub fn runForFrames(self: *Emulator, frames: u32) void {
        const mcycles_per_frame: u32 = 17556;
        const total_mcycles = mcycles_per_frame * frames;
        var i: u32 = 0;
        while (i < total_mcycles) : (i += 1) {
            self.stepMCycle();
        }
    }

    /// Get captured serial output (from Blargg test ROMs via SB/SC protocol).
    pub fn getSerialOutput(self: *Emulator) []const u8 {
        return self.bus.getSerialOutput();
    }

    /// Get the framebuffer (stub in Phase 1 — returns zeroed buffer).
    pub fn getFrameBuffer(self: *Emulator) *const [160 * 144]u8 {
        return &self.framebuffer;
    }

    /// Get mutable frame buffer reference (for PPU in Phase 3).
    pub fn getFrameBufferMut(self: *Emulator) *[160 * 144]u8 {
        return &self.framebuffer;
    }
};
