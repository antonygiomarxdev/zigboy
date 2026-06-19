const std = @import("std");
const c = @import("c");
const emu = @import("emulator");
const lib = @import("lib.zig");

fn readRom(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    var io_threaded = std.Io.Threaded.init(allocator, .{});
    const io = io_threaded.io();
    return std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(emu.CART_MAX_SIZE));
}

fn keyToButton(scancode: c.SDL_Scancode) ?emu.addr.JoypadButton {
    return switch (scancode) {
        c.SDL_SCANCODE_UP => .up,
        c.SDL_SCANCODE_DOWN => .down,
        c.SDL_SCANCODE_LEFT => .left,
        c.SDL_SCANCODE_RIGHT => .right,
        c.SDL_SCANCODE_Z => .b,
        c.SDL_SCANCODE_X => .a,
        c.SDL_SCANCODE_RETURN => .start,
        c.SDL_SCANCODE_RSHIFT => .select,
        else => null,
    };
}

pub fn main(init: std.process.Init.Minimal) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.Args.toSlice(init.args, allocator);
    if (args.len < 2) {
        std.debug.print("Usage: zigboy <rom-path>\n", .{});
        std.process.exit(1);
    }
    const rom_path = args[1];

    const rom_bytes = readRom(allocator, rom_path) catch |err| {
        std.debug.print("Failed to read ROM '{s}': {}\n", .{ rom_path, err });
        std.process.exit(1);
    };

    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
        std.debug.print("SDL_Init failed: {s}\n", .{c.SDL_GetError()});
        std.process.exit(1);
    }
    defer c.SDL_Quit();

    const window = c.SDL_CreateWindow("ZigBoy", 480, 432, c.SDL_WINDOW_RESIZABLE) orelse {
        std.debug.print("SDL_CreateWindow failed: {s}\n", .{c.SDL_GetError()});
        std.process.exit(1);
    };
    defer c.SDL_DestroyWindow(window);

    const renderer = c.SDL_CreateRenderer(window, null) orelse {
        std.debug.print("SDL_CreateRenderer failed: {s}\n", .{c.SDL_GetError()});
        std.process.exit(1);
    };
    defer c.SDL_DestroyRenderer(renderer);

    const texture = c.SDL_CreateTexture(
        renderer,
        @as(c_uint, @bitCast(c.SDL_PIXELFORMAT_RGBX8888)),
        c.SDL_TEXTUREACCESS_STREAMING,
        160,
        144,
    ) orelse {
        std.debug.print("SDL_CreateTexture failed: {s}\n", .{c.SDL_GetError()});
        std.process.exit(1);
    };
    defer c.SDL_DestroyTexture(texture);

    var gameboy = try emu.Emulator.init(allocator, rom_bytes);
    defer gameboy.deinit();

    _ = lib;

    var pixels: [emu.addr.FRAMEBUFFER_LEN * 4]u8 = undefined;

    const perf_freq = c.SDL_GetPerformanceFrequency();
    const frame_ticks = perf_freq * emu.addr.T_CYCLES_PER_FRAME / emu.addr.DMG_CLOCK_HZ;
    var last_frame = c.SDL_GetPerformanceCounter();

    main_loop: while (true) {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event)) {
            switch (event.type) {
                c.SDL_EVENT_QUIT => break :main_loop,
                c.SDL_EVENT_KEY_DOWN => {
                    if (event.key.scancode == c.SDL_SCANCODE_ESCAPE) break :main_loop;
                    if (event.key.scancode == c.SDL_SCANCODE_F) {
                        const flags = c.SDL_GetWindowFlags(window);
                        _ = c.SDL_SetWindowFullscreen(window, (flags & c.SDL_WINDOW_FULLSCREEN) == 0);
                        continue;
                    }
                    if (keyToButton(event.key.scancode)) |button| {
                        gameboy.setButtonState(button, true);
                    }
                },
                c.SDL_EVENT_KEY_UP => {
                    if (keyToButton(event.key.scancode)) |button| {
                        gameboy.setButtonState(button, false);
                    }
                },
                else => {},
            }
        }

        const now = c.SDL_GetPerformanceCounter();
        const elapsed = now - last_frame;
        if (elapsed < frame_ticks) {
            const remaining_ms = (frame_ticks - elapsed) * 1000 / perf_freq;
            if (remaining_ms > 0) {
                c.SDL_Delay(@intCast(remaining_ms));
            }
        }

        gameboy.runForFrames(1);

        const fb = gameboy.getFrameBuffer();
        for (fb, 0..) |shade, i| {
            const offset = i * 4;
            const rgba = switch (shade) {
                emu.addr.SHADE_WHITE => [4]u8{ 0xFF, 0xFF, 0xFF, 0xFF },
                emu.addr.SHADE_LIGHT => [4]u8{ 0xAA, 0xAA, 0xAA, 0xFF },
                emu.addr.SHADE_DARK => [4]u8{ 0x55, 0x55, 0x55, 0xFF },
                emu.addr.SHADE_BLACK => [4]u8{ 0x00, 0x00, 0x00, 0xFF },
                else => [4]u8{ 0x00, 0x00, 0x00, 0xFF },
            };
            pixels[offset + 0] = rgba[0];
            pixels[offset + 1] = rgba[1];
            pixels[offset + 2] = rgba[2];
            pixels[offset + 3] = rgba[3];
        }

        _ = c.SDL_UpdateTexture(texture, null, &pixels, 160 * 4);
        _ = c.SDL_RenderTexture(renderer, texture, null, null);
        _ = c.SDL_RenderPresent(renderer);

        last_frame = now;
    }
}
