const std = @import("std");

pub const Emulator = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !Emulator {
        return Emulator{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Emulator) void {
        _ = self;
    }
};
