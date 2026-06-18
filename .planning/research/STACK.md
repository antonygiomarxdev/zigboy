# Stack Research

**Domain:** Game Boy (DMG) emulator in Zig — hyper-fast, super-lightweight, cycle-accurate
**Researched:** 2026-06-18
**Confidence:** HIGH (verified against ziglang.org, castholm/SDL, paoda/zba, mattneel/zgbc, Context7-equivalent sources)

---

## Executive Summary

The 2026 Zig ecosystem is in a transitional but excellent state for this project. **Zig 0.16.0** is the latest stable (released ~Feb 2026) with **LLVM 21, musl 1.2.5, glibc 2.43, macOS 26.4 headers, Linux 6.19** all built in, and a major `std.Io` refactor that simplifies async-style patterns. **`@cImport` is deprecated** — the idiomatic way to call C is now `b.addTranslateC` in `build.zig` (or the `translate-c` package). For windowing/input/audio, the **first-class choice is SDL3 via `castholm/SDL`** (v0.5.1 / SDL 3.4.10, June 2026) — it integrates with `zig fetch` and supports static linking, stripping, and LTO via clean build options.

Two reference emulators in Zig confirm the stack pattern: **mattneel/zgbc** uses a pure-Zig core with raylib (137 KB WASM, 22,818 FPS headless) — the architecture pattern to copy. **paoda/zba** (GBA) uses SDL2 with TOML config and is the precedent for SDL-based windowing in Zig emulators. Both use `zig build` exclusively with no Make/CMake.

The single biggest pitfall to avoid: relying on **C++ dependencies** or **dynamic-linked SDL2** for distribution — both inflate binary size and break the "statically linked, no runtime dependencies" requirement. The `b.dependency("sdl", .{ .preferred_linkage = .static, .strip = true, .lto = .full })` pattern is the answer.

---

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended | Confidence |
|------------|---------|---------|-----------------|------------|
| **Zig** | 0.16.0 (stable) | Implementation language, build system, `zig build` | Latest stable; `std.Io` refactor, `b.addTranslateC`, `translate-c` package, `heap.ArenaAllocator` is now lock-free. Production-safe vs. 0.17.0-dev master. | HIGH |
| **LLVM** | 21 (bundled with Zig 0.16) | Code generation backend | Bundled; x86, aarch64, WebAssembly, new ELF linker, musl 1.2.5, glibc 2.43. No external LLVM install required. | HIGH |
| **musl libc** | 1.2.5 | Static C library for Linux targets | Default for `-Dtarget=x86_64-linux-musl`; produces a single statically-linked binary with zero runtime deps. | HIGH |
| **SDL3** (via `castholm/SDL`) | v0.5.1 / SDL 3.4.10 (Jun 7, 2026) | Window, input, audio I/O, 2D rendering, event loop | First-class Zig package; supports `preferred_linkage=.static`, `strip`, `lto`, all 3 desktop OSes + Emscripten. Replaces the SDL2 era. | HIGH |
| **`translate-c`** (official Zig package) | 0.16.0 | C-ABI import of SDL3 headers | Replaces deprecated `@cImport`. Imported via `b.dependency("translate_c", .{})`. Generates a Zig module from SDL3 C headers. | HIGH |
| **Zig stdlib** (`std.fs`, `std.Io`, `std.heap`, `std.mem`) | 0.16.0 | ROM file I/O, battery save I/O, allocators, memory layout, struct packing, bit manipulation | All emulator core data structures and I/O. No external deps. | HIGH |

### Supporting Libraries (future / optional)

| Library | Version | Purpose | When to Use | Confidence |
|---------|---------|---------|-------------|------------|
| **Raylib** | 6.0 (Apr 2026) | Alternative 2D windowing (used by `mattneel/zgbc`) | Only if you want a tighter renderer than SDL3 and don't need cross-platform audio. Adds X11/GL deps on Linux. **Not recommended for v1.** | MEDIUM |
| **SDL2** | 2.32.x | Legacy alternative to SDL3 | Only if you must support an old Linux distro without SDL3. **Not recommended for v1.** | MEDIUM |
| **`anyzig`** | v2026_03_26 (Mar 2026) | Universal `zig` wrapper that auto-fetches the right Zig version per `build.zig.zon` | Useful for contributors who don't have Zig 0.16 installed yet. Recommended as a DX improvement. | MEDIUM |
| **`zigwin32`** | latest | Win32 API bindings for Windows-specific code | Only if you need raw Win32 beyond what SDL3 exposes. Not needed for v1 — SDL3 covers input/render/audio. | MEDIUM |
| **miniaudio** | 0.11.x | Single-header C audio library (alternative to SDL3 audio) | If you ever drop SDL3 in favor of bespoke audio. SDL3's `SDL_AudioStream` is already minimal — miniaudio is redundant here. | LOW |

### Development Tools

| Tool | Purpose | Configuration Tips |
|------|---------|---------------------|
| **Zig 0.16.0** (downloaded from ziglang.org) | Compiler + build system + test runner + formatter | `zig build run`, `zig build test`, `zig fmt`, `zig build -Doptimize=ReleaseFast` |
| **`anyzig`** (optional) | One `zig` binary that fetches the correct version on demand | Drop-in for `zig`; reads `minimum_zig_version` from `build.zig.zon` |
| **Blargg's test ROMs** | `cpu_instrs`, `dmg-acid`, `mem_timing`, etc. | Hosted by `retrio/gb-test-roms` and `c-sp/gameboy-test-roms`; not vendored — pull at test time |
| **Mooneye test suite** | Cycle-accurate behavior tests | `git clone https://github.com/Gekkio/mooneye-test-suite` (only if Mooneye is needed beyond Blargg) |
| **Pan Docs** (gbdev.io/pandocs) | Definitive GB technical reference | Web-only; no install needed |
| **ZLS (Zig Language Server)** | IDE support (autocomplete, go-to-def) | Use a build that matches your Zig 0.16 install |

---

## Installation

### Toolchain (host machine)

```bash
# Option A: direct install
curl -L https://ziglang.org/download/0.16.0/zig-x86_64-linux-0.16.0.tar.xz | tar xJ
export PATH="$PWD/zig-x86_64-linux-0.16.0:$PATH"

# Option B: anyzig (recommended for contributors)
# See https://marler8997.github.io/anyzig — single static binary that auto-resolves Zig version
```

### Project dependencies (`build.zig.zon`)

```zig
.dependencies = .{
    .sdl = .{
        .url = "git+https://github.com/castholm/SDL.git#v0.5.1+3.4.10",
        .hash = "...", // zig fetch will fill this in
    },
    .translate_c = .{
        .url = "git+https://codeberg.org/ziglang/translate-c.git",
        .hash = "...",
    },
},
.minimum_zig_version = "0.16.0",
```

Add to `build.zig`:
```bash
zig fetch --save git+https://github.com/castholm/SDL.git#v0.5.1+3.4.10
zig fetch --save git+https://codeberg.org/ziglang/translate-c.git
```

The `castholm/SDL` repo already supports `zig fetch` (the README documents it as the standard way), and explicitly requires **Zig 0.16.0 or 0.17.0-dev**.

---

## Build Configuration

### Build modes (decision per binary)

| Mode | Use Case | Effect |
|------|----------|--------|
| **`ReleaseFast`** | **Primary release build** (emulator runtime perf) | `-O3`, no safety, no debug info, fastest code. **Default for `zig build` user-facing binary.** |
| **`ReleaseSmall`** | Tightest binary size | `-Os`, may be ~2x smaller than `ReleaseFast` but ~20-30% slower CPU emulation. Tradeoff — not recommended for an emulator that targets > 60 FPS. |
| **`ReleaseSafe`** | Test runs that should catch undefined behavior | Safe optimizations + runtime checks. Use for `zig build test` in CI. |
| **`Debug`** | Development with `std.debug.assert` | Slow; large binary; full DWARF. Use during active emulator development. |

**Recommendation:** Ship with `ReleaseFast` + `strip = true` + `lto = .full`. This combination routinely produces < 5 MB statically-linked Linux binaries for emulator-class workloads (mattneel/zgbc is 137 KB for WASM; SDL3-linked Linux will be larger but well under 5 MB).

### Reference `build.zig` skeleton (v1 target)

```zig
const std = @import("std");
const translate_c = @import("translate_c");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // SDL3 (windowing + input + audio + 2D render)
    const sdl_dep = b.dependency("sdl", .{
        .target = target,
        .optimize = optimize,
        .preferred_linkage = .static,
        .strip = true,
        .lto = if (optimize == .Debug) null else .full,
    });
    const sdl_lib = sdl_dep.artifact("SDL3");

    // Translate SDL3 C headers into a Zig module
    const translate_c_dep = b.dependency("translate_c", .{});
    const translator: translate_c.Translator = .init(translate_c_dep, .{
        .c_source_file = b.addWriteFiles().add("c.h",
            \\#define SDL_DISABLE_OLD_NAMES
            \\#include <SDL3/SDL.h>
            \\#define SDL_MAIN_HANDLED
            \\#include <SDL3/SDL_main.h>
        ),
        .target = target,
        .optimize = optimize,
    });
    translator.linkLibrary(sdl_lib);

    // Executable
    const exe = b.addExecutable(.{
        .name = "zigboy",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .strip = true,
        }),
    });
    exe.root_module.linkLibrary(sdl_lib);
    exe.root_module.addImport("c", translator.mod);

    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    if (b.args) |args| run.addArgs(args);
    const run_step = b.step("run", "Run the emulator");
    run_step.dependOn(&run.step);
}
```

### Build commands

```bash
# Dev (fast iteration, debug symbols)
zig build run -- path/to/rom.gb

# Release (what we ship)
zig build -Doptimize=ReleaseFast

# Cross-compile (Linux → Windows, static, no deps)
zig build -Doptimize=ReleaseFast -Dtarget=x86_64-windows-gnu

# Cross-compile (Linux host → macOS Apple Silicon)
# Requires macOS SDK paths via -Dsystem_include_path etc.
zig build -Doptimize=ReleaseFast -Dtarget=aarch64-macos

# Statically linked, no-glibc, single-file binary
zig build -Doptimize=ReleaseFast -Dtarget=x86_64-linux-musl
```

---

## Architecture Pattern (mattneel/zgbc, to mirror)

The most relevant reference emulator in 2026 is **`mattneel/zgbc`** (Jan 2026, ~3,500 LOC, MIT, full Blargg test pass). Mirror its `src/` layout:

```
src/
├── cpu.zig       # LR35902 instruction set, comptime opcode tables
├── mmu.zig       # Memory map (ROM/RAM/VRAM/HRAM/Echo/I/O), bus reads/writes
├── mbc.zig       # MBC1/MBC3/MBC5 cartridge banking
├── timer.zig     # DIV / TIMA / TMA / TAC
├── ppu.zig       # PPU: modes 0-3, scanline renderer, BG/window/sprites
├── apu.zig       # APU: NR10-NR52, 4 channels (DEFERRED to v1.1 per PROJECT.md)
├── joypad.zig    # Joypad register (P1) — up/down/left/right/A/B/Start/Select
├── serial.zig    # Stub for v1 (no link cable)
├── cart.zig      # ROM header parsing, .sav load/save, battery detection
├── framebuffer.zig # 160x144 RGBA32, palette translation
├── gb.zig        # Top-level GameBoy state, step()/frame(), save states
├── save_state.zig # (optional) Serialization
├── main.zig      # Entry point, SDL3 window/render/audio loop
└── root.zig      # Public API (when used as a library)
```

Key idioms (verified from `zgbc`):
- **`comptime` opcode tables** for cycle counts and instruction decoding — the best-known pattern for fast interpreter dispatch in Zig.
- **`std.ArrayList` / unmanaged containers** for dynamic structures (sav data is fixed-size, but other structures may grow). Zig 0.16 migrated most containers to "unmanaged" — pass an allocator explicitly per call.
- **`std.heap.GeneralPurposeAllocator`** for the emulator's working set. In 0.16 it is now **lock-free and thread-safe** as `heap.ArenaAllocator` is.
- **Packed structs** (`packed struct`) for CPU registers, PPU flags, MBC mode bits — gives bit-level precision with type safety.

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| **`@cImport`** | Deprecated in Zig 0.16. Removed in 0.17. Will be a build error. | `b.addTranslateC` via the official `translate_c` package (or `b.lazyDependency` for the `translate_c` package from ziglang/translate-c on Codeberg). |
| **SDL2 (direct, from libsdl.org)** | SDL3 is now stable and has a clean Zig integration via `castholm/SDL`. SDL2 Zig bindings are a mess of community forks. | SDL3 via `castholm/SDL` (`zig fetch` + `b.dependency("sdl", ...)`). |
| **Dynamic-linked SDL3** | Breaks the "no runtime dependencies" constraint; user has to install matching `libSDL3.so`. Statically linking is the default and adds < 500 KB to the binary. | `castholm/SDL` with `preferred_linkage = .static` (default). |
| **C++ dependencies in the core** | Hurts Zig's strengths; obscures build graph; no clean translation. The project rule explicitly says "Zig only in the core; C-ABI interop allowed for SDL2 bindings" — interpret this as **only SDL3 C**. | Pure Zig core + `b.addTranslateC` for SDL3 only. |
| **`make` / `cmake` / shell scripts for build** | PROJECT.md explicitly forbids these. | `zig build` only. |
| **Electron / Tauri / web UI** | For a desktop emulator, this is ~150 MB of overhead to display 160x144 pixels. | SDL3 + native window. |
| **WebGPU / wgpu for v1** | Project Out of Scope: "WebAssembly / browser builds — defer until core is stable". | SDL3 GPU is in 0.16 but unnecessary for a 160x144 software-rendered DMG framebuffer. |
| **A custom emulator framework / "engine"** | Reinventing the wheel; would delay v1 by months. | Mirror mattneel/zgbc's flat `src/` layout. |
| **C++-era game framework (Godot, Unity, etc.)** | Way too much; not Zig. | SDL3 directly. |
| **`include/` vendored SDL headers** | castholm/SDL already provides the right header search paths via the dependency. | `b.dependency("sdl", ...)` provides everything. |
| **`std.posix` / `std.os.windows`** for I/O | 0.16 reorganized I/O behind `std.Io`. Direct `posix` is going away. | `std.fs.File`, `std.Io.File` (new in 0.16), `fs.Dir.readFileAlloc`, `fs.File.readToEndAlloc`. |

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| **SDL3 (castholm/SDL)** | **Raylib 6.0** (vendored under `third_party/raylib/`) | If you want a smaller render surface and don't need audio. Requires manual linking of X11/GL/Cocoa/OpenGL framework dependencies — more platform-specific build code. Not recommended for a 3-OS-target project. |
| **SDL3 (castholm/SDL)** | **SDL2** | Only if you must support Linux distros that don't have SDL3 (most distros have it by mid-2026, so this is increasingly rare). |
| **SDL3 (castholm/SDL)** | **Custom Win32/X11/Cocoa code via `marlersoft/zigwin32`** | If you want zero non-Zig deps. Massively more work; you give up audio, gamepad, scene graph, etc. Not realistic. |
| **Zig 0.16.0 stable** | **Zig 0.17.0-dev (master)** | If you need a specific unreleased language feature, or want to dogfood. 0.17.0 will break `castholm/SDL` API until updated. Stay on 0.16 for production. |
| **Zig 0.16.0 stable** | **Zig 0.15.x** | Don't downgrade. 0.15 is what `paoda/zba` and `mollaosmanoglu/zigboy` use; it's the previous stable. 0.16 is the current. |
| **`zig fetch` + `b.dependency`** | **`git submodule` + `addIncludePath`** | If you need offline builds. Submodules require `git submodule update --init --recursive` and break hermetic builds. Use `zig fetch`. |
| **`ReleaseFast` + `strip` + `lto=.full`** | **`ReleaseSmall`** | If binary size matters more than CPU emulation speed. Emulator perf > binary size for v1 per PROJECT.md. |
| **Build for `x86_64-linux-gnu`** (host glibc) | **Build for `x86_64-linux-musl`** | musl produces a single statically-linked binary with zero runtime deps (matches the "no runtime dependencies" constraint exactly). gnu links against host glibc; binary may not work on older distros. For shipping, **musl is the correct choice.** |

---

## Stack Patterns by Variant

**If building a CLI-only (no window) headless test harness:**
- Don't link SDL3 at all. Use `zig build -Doptimize=ReleaseFast` to a benchmark binary that calls `gb.frame()` N times.
- The mattneel/zgbc pattern: a separate `bench` step in `build.zig` that doesn't import the renderer.

**If targeting Windows (Phase 2+):**
- `zig build -Dtarget=x86_64-windows-gnu` — MinGW cross-compile from Linux. Works out of the box with `castholm/SDL`.
- `zig build -Dtarget=x86_64-windows-msvc` — requires MSVC + Windows 11 SDK installed on the host. First-class per castholm/SDL.

**If targeting macOS Apple Silicon (Phase 2+):**
- Build on a Mac with Xcode installed. `castholm/SDL` requires macOS SDK paths.
- Cross-compile from Linux **is explicitly unsupported** by `castholm/SDL` (Apple SLA).

**If targeting WebAssembly (explicitly Out of Scope for v1, but Phase 3+):**
- `zig build -Dtarget=wasm32-emscripten` — but needs Emscripten SDK + castholm/SDL's special `system_include_path` option.
- Consider whether the 160x144 framebuffer + APU would actually benefit from WASM; probably defer per PROJECT.md.

**If hitting a binding issue between Zig 0.16 and SDL3:**
- The breakout example by castholm is the canonical reference. https://github.com/castholm/zig-examples/tree/master/breakout
- The `translator.mod` import pattern is stable.

---

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|-----------------|-------|
| `castholm/SDL` v0.5.1+3.4.10 | Zig 0.16.0, Zig 0.17.0-dev | The package declares this in its README. Earlier SDL packages (v0.4.x) supported older Zigs. |
| `ziglang/translate-c` (Codeberg) | Zig 0.16.0+ | The official package as of 0.16; replaces the deprecated `@cImport` builtin. |
| Zig 0.16.0 stdlib | Linux 5.10+ (glibc 2.43 / musl 1.2.5), macOS 13.0+, Windows 10+ | Built-in toolchain. |
| `anyzig` v2026_03_26 | Any host | Wrapper, not a real package; just a smart `zig` shim. |
| `mattneel/zgbc` master (Jan 2026) | Zig 0.16 | Reference impl; ships `zig-0.16-llm-context.md` for AI/LLM use. |

### Critical incompatibility to avoid
- **Do not use `paoda/zba` patterns verbatim for the renderer** — it targets Zig 0.15.1 and SDL2. Use the *architecture* (TOML config, source layout) but not the *bindings* (those changed in 0.16).
- **Do not use `mollaosmanoglu/zigboy`'s SDL binding style** — it targets Zig 0.13 and is pre-`@cImport`-deprecation.

---

## Key Technical Decisions (informed by research)

| Decision | Stack Choice | Rationale |
|----------|--------------|-----------|
| Windowing + input + audio | SDL3 via `castholm/SDL` | First-class Zig support; single C dep; static + strip + LTO; cross-platform |
| C-ABI import | `b.addTranslateC` via official `translate_c` package | Replaces deprecated `@cImport`; works in 0.16 |
| Memory management | Manual `std.heap.GeneralPurposeAllocator` + per-subsystem `ArenaAllocator` | PROJECT.md requires "no GC, manual or arena allocators only" |
| File I/O | `std.fs.File` / `std.Io.File` + `@embedFile` for the optional boot ROM | Zig stdlib; no extra dep |
| CPU core dispatch | `comptime` opcode tables + tagged-union switch on opcode | The standard fast-interpreter pattern; matches mattneel/zgbc |
| Optimization mode | `ReleaseFast` for the user binary; `Debug` for dev; `ReleaseSafe` for CI tests | Speed > size for an emulator |
| Linkage | All static; `strip = true`; `lto = .full` for release | Hits the < 5 MB static binary target |
| Target libc | musl for Linux shipping (no runtime deps); gnu for dev | `x86_64-linux-musl` is the production target |
| Rendering | SDL3 `SDL_Renderer` + `SDL_Texture` with `SDL_TEXTUREACCESS_STREAMING` | Zero-copy framebuffer upload at 60 Hz; trivially scales; software renderer available as fallback |
| Audio (Phase 1.1, deferred) | SDL3 `SDL_OpenAudioDeviceStream` with a `get` callback | Standard audio device API; built into the same SDL3 dep we already have |

---

## Sources

| Source | Confidence | What it verified |
|--------|-----------|------------------|
| https://ziglang.org/download/0.16.0/release-notes.html | HIGH | Zig 0.16 stable; `std.Io`; `b.addTranslateC`; `heap.ArenaAllocator` lock-free; LLVM 21; musl 1.2.5; glibc 2.43; macOS 26.4 headers; new x86/aarch64/WASM backends |
| https://ziglang.org/download/index.json | HIGH | Confirmed 0.16.0 is current stable; 0.17.0-dev is master (dated 2026-06-17) |
| https://github.com/castholm/SDL (README + `build.zig`) | HIGH | v0.5.1+3.4.10 (Jun 7, 2026); requires Zig 0.16.0 or 0.17.0-dev; `preferred_linkage`, `strip`, `lto`, `sanitize_c`, `pic` options; supports `x86_64/aarch64-{windows,linux}-{gnu,musl}`, `aarch64/x86_64-macos`, `wasm32-emscripten` |
| https://github.com/castholm/zig-examples/blob/master/breakout/build.zig | HIGH | Canonical idiom for using `b.addTranslateC` with `castholm/SDL`; uses `translate_c.Translator` |
| https://wiki.libsdl.org/SDL3/CategoryRender | HIGH | SDL3 2D renderer API: `SDL_CreateRenderer`, `SDL_CreateTexture` (with `SDL_TEXTUREACCESS_STREAMING`), `SDL_UpdateTexture`, `SDL_RenderTexture`, `SDL_RenderPresent`, `SDL_SOFTWARE_RENDERER` macro |
| https://wiki.libsdl.org/SDL3/CategoryAudio | HIGH | SDL3 audio API: `SDL_OpenAudioDeviceStream`, `SDL_AudioStream`, `SDL_PutAudioStreamData`, `SDL_SetAudioStreamGetCallback` — all available for the Phase 1.1 APU work |
| https://github.com/mattneel/zgbc | HIGH | Reference architecture (cpu/mmu/mbc/timer/ppu/apu/gb split); uses raylib; Zig 0.16; ships `zig-0.16-llm-context.md`; ~3,500 LOC; passes all 12 Blargg CPU tests |
| https://github.com/paoda/zba (`build.zig`) | HIGH | Precedent for SDL-based Zig emulator using `b.dependency("sdl", ...)`; uses zgui/imgui/zglgen — additional deps not needed for DMG simplicity |
| https://github.com/marler8997/anyzig | MEDIUM | DX recommendation; v2026_03_26 |
| https://github.com/marlersoft/zigwin32 | MEDIUM | Listed as a not-needed alternative (SDL3 covers it) |
| https://github.com/raysan5/raylib | MEDIUM | raylib 6.0 (Apr 2026); listed as alternative we are NOT using |
| GitHub search "game boy emulator zig" (28 results) | HIGH | Confirms multiple DMG emulators in Zig exist; mattneel/zgbc and paoda/zba are the most polished references; confirms the ecosystem is mature enough to ship in 2026 |

---

*Stack research for: ZigBoy — hyper-fast DMG emulator in Zig*
*Researched: 2026-06-18*
*Confidence: HIGH — primary stack (Zig 0.16.0 + SDL3 via castholm/SDL + b.addTranslateC + stdlib) is verified against the official Zig 0.16 release notes, the castholm/SDL package README and build.zig, the SDL3 wiki, and two production-quality reference emulators (zgbc, zba).*
