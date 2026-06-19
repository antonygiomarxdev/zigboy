const std = @import("std");
const c = @import("c");
const emu = @import("emulator");
const lib = @import("lib.zig");

pub fn main(init: std.process.Init.Minimal) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const args = try std.process.Args.toSlice(init.args, arena.allocator());

    if (args.len < 2) {
        std.debug.print("Usage: zigboy <rom-path>\n", .{});
        std.process.exit(1);
    }

    const rom_path = args[1];

    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
        std.debug.print("SDL_Init failed: {s}\n", .{c.SDL_GetError()});
        std.process.exit(1);
    }
    defer c.SDL_Quit();

    std.debug.print("ROM path: {s}\n", .{rom_path});
    std.debug.print("SDL_Init OK\n", .{});

    _ = lib;
}
