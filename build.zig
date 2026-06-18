const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // SDL3 dependency — static link, strip, LTO
    const sdl_lto = if (optimize != .Debug) @as(?std.zig.LtoMode, .full) else null;
    const sdl_dep = b.dependency("sdl", .{
        .target = target,
        .optimize = optimize,
        .preferred_linkage = .static,
        .strip = false, // Debug mode; release sets strip = true via exe
        .lto = sdl_lto,
    });
    const sdl_lib = sdl_dep.artifact("SDL3");

    // Translate SDL3 C headers into a Zig module using built-in addTranslateC
    const translate_c = b.addTranslateC(.{
        .root_source_file = b.addWriteFiles().add("c.h",
            \\#define SDL_DISABLE_OLD_NAMES
            \\#include <SDL3/SDL.h>
            \\#define SDL_MAIN_HANDLED
            \\#include <SDL3/SDL_main.h>
        ),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    translate_c.addIncludePath(sdl_lib.getEmittedIncludeTree());

    // C module from translated SDL3 headers
    const c_module = translate_c.createModule();

    // Executable
    const exe = b.addExecutable(.{
        .name = "zigboy",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addImport("c", c_module);
    exe.root_module.linkLibrary(sdl_lib);
    exe.root_module.link_libc = true;

    // strip + LTO for release builds
    if (optimize != .Debug) {
        exe.root_module.strip = true;
        exe.lto = .full;
    }

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the emulator");
    run_step.dependOn(&run_cmd.step);

    // Test target (placeholder — src/main.zig as test root)
    const test_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_module.addImport("c", c_module);
    test_module.linkLibrary(sdl_lib);
    test_module.link_libc = true;
    const test_exe = b.addTest(.{
        .name = "zigboy-test",
        .root_module = test_module,
    });
    const test_run = b.addRunArtifact(test_exe);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&test_run.step);
}
