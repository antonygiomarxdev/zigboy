const std = @import("std");
const Emulator = @import("emulator").Emulator;

const rom_url = "https://raw.githubusercontent.com/retrio/gb-test-roms/master/cpu_instrs/cpu_instrs.gb";
const rom_cache_path = "tests/roms/cpu_instrs.gb";

/// Try to fetch a ROM via curl child process. Returns true on success.
fn fetchRom(io: std.Io, allocator: std.mem.Allocator, url: []const u8, output_path: []const u8) bool {
    const result = std.process.run(allocator, io, .{
        .argv = &[_][]const u8{ "curl", "--silent", "--fail", "--output", output_path, url },
    }) catch return false;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    return result.term == .exited and result.term.exited == 0;
}

/// Ensure the cpu_instrs.gb ROM exists, auto-fetching if necessary.
/// Returns an allocated path that the caller must free.
fn ensureRomExists(io: std.Io, allocator: std.mem.Allocator) ![]const u8 {
    // Check ZIGBOY_TEST_ROM env var first (Zig 0.16 API via std.testing.environ)
    if (std.process.Environ.getAlloc(std.testing.environ, allocator, "ZIGBOY_TEST_ROM")) |env_path| {
        return env_path;
    } else |err| {
        if (err != error.EnvironmentVariableMissing) return err;
    }

    // Check if ROM file already exists
    const cwd = std.Io.Dir.cwd();
    if (cwd.access(io, rom_cache_path, .{})) |_| {
        // File exists — return path
        return allocator.dupe(u8, rom_cache_path);
    } else |_| {
        // File doesn't exist — try to fetch
        cwd.createDirPath(io, "tests/roms") catch {};
        if (!fetchRom(io, allocator, rom_url, rom_cache_path)) {
            std.log.err("Failed to download test ROM. Check network or manually place at {s}", .{rom_cache_path});
            return error.TestRomFetchFailed;
        }
        return allocator.dupe(u8, rom_cache_path);
    }
}

test "Blargg cpu_instrs" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const rom_path = try ensureRomExists(io, allocator);
    defer allocator.free(rom_path);

    const cwd = std.Io.Dir.cwd();
    const rom_bytes = cwd.readFileAlloc(io, rom_path, allocator, std.Io.Limit.limited(8 * 1024 * 1024)) catch |err| {
        std.debug.print("Failed to read ROM file '{s}': {}\n", .{ rom_path, err });
        return error.TestRomReadFailed;
    };
    defer allocator.free(rom_bytes);

    var emu = try Emulator.init(allocator, rom_bytes);
    defer emu.deinit();

    // Run for ~3600 virtual frames (60 FPS × 60 seconds).
    // The Blargg cpu_instrs.gb takes ~55 emulated seconds on real DMG.
    // On a modern CPU this completes in a few wall-clock seconds.
    emu.runForFrames(3600);

    const output = emu.getSerialOutput();
    const found = std.mem.indexOf(u8, output, "Passed") != null;
    if (!found) {
        const display_len = @min(output.len, @as(usize, 200));
        std.debug.print("Serial output (first {} bytes):\n{s}\n", .{ display_len, output[0..display_len] });
    }
    try std.testing.expect(found);
}
