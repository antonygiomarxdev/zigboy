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

    // Shared emulator module (pure Zig — no SDL3 dependency)
    const emulator_mod = b.createModule(.{
        .root_source_file = b.path("src/Emulator.zig"),
        .target = target,
        .optimize = optimize,
    });

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
    exe.root_module.addImport("emulator", emulator_mod);
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

    // Blargg cpu_instrs test
    const blargg_mod = b.createModule(.{
        .root_source_file = b.path("tests/blargg.zig"),
        .target = target,
        .optimize = optimize,
    });
    blargg_mod.addImport("emulator", emulator_mod);
    const blargg_test = b.addTest(.{ .root_module = blargg_mod });
    const blargg_run = b.addRunArtifact(blargg_test);

    // Serial capture test
    const serial_mod = b.createModule(.{
        .root_source_file = b.path("tests/serial_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    serial_mod.addImport("emulator", emulator_mod);
    const serial_test = b.addTest(.{ .root_module = serial_mod });
    const serial_run = b.addRunArtifact(serial_test);

    // PPU test (sprite + DMA)
    const ppu_mod = b.createModule(.{
        .root_source_file = b.path("tests/ppu_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    ppu_mod.addImport("emulator", emulator_mod);
    const ppu_test = b.addTest(.{ .root_module = ppu_mod });
    const ppu_run = b.addRunArtifact(ppu_test);
    const ppu_step = b.step("ppu", "Run PPU sprite/DMA tests");
    ppu_step.dependOn(&ppu_run.step);

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&blargg_run.step);
    test_step.dependOn(&serial_run.step);
    test_step.dependOn(&ppu_run.step);

    const serial_step = b.step("serial", "Run serial capture test");
    serial_step.dependOn(&serial_run.step);
}
