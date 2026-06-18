<!-- GSD:project-start source:PROJECT.md -->

## Project

**ZigBoy**

ZigBoy is a hyper-fast, super-lightweight Game Boy (DMG) emulator written in Zig.
It targets cycle-accurate execution, minimal binary size, low memory footprint, and
fast startup — leveraging Zig's compile-time features, manual memory management,
and C-ABI interop. The intended audience is emulator enthusiasts, developers
learning emulator/architecture work, and anyone who wants a clean, modern Zig
reference for the Game Boy platform.

**Core Value:** Run any Game Boy ROM with cycle-accurate CPU and timing, with a smaller binary
and lower overhead than comparable emulators (e.g. SameBoy C, Gambatte) — using
Zig as both the implementation language and a forcing function for performance.

### Constraints

- **Language:** Zig only (no C/C++ in the core; C-ABI interop allowed for SDL2 bindings)
- **License:** MIT (target)
- **Build system:** `zig build` (no CMake, no Make, no shell scripts for build)
- **Performance target:** > 60 FPS for any DMG ROM on a modern desktop CPU; < 30 MB RAM
  working set

- **Binary target:** < 5 MB statically-linked Linux binary (release-fast, stripped)
- **No garbage collection** — manual memory or arena allocators only
- **Determinism:** Same ROM + same input → same output (frame N) bit-for-bit

<!-- GSD:project-end -->

<!-- GSD:stack-start source:research/STACK.md -->

## Technology Stack

## Executive Summary

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

## Installation

### Toolchain (host machine)

# Option A: direct install

# Option B: anyzig (recommended for contributors)

# See https://marler8997.github.io/anyzig — single static binary that auto-resolves Zig version

### Project dependencies (`build.zig.zon`)

## Build Configuration

### Build modes (decision per binary)

| Mode | Use Case | Effect |
|------|----------|--------|
| **`ReleaseFast`** | **Primary release build** (emulator runtime perf) | `-O3`, no safety, no debug info, fastest code. **Default for `zig build` user-facing binary.** |
| **`ReleaseSmall`** | Tightest binary size | `-Os`, may be ~2x smaller than `ReleaseFast` but ~20-30% slower CPU emulation. Tradeoff — not recommended for an emulator that targets > 60 FPS. |
| **`ReleaseSafe`** | Test runs that should catch undefined behavior | Safe optimizations + runtime checks. Use for `zig build test` in CI. |
| **`Debug`** | Development with `std.debug.assert` | Slow; large binary; full DWARF. Use during active emulator development. |

### Reference `build.zig` skeleton (v1 target)

### Build commands

# Dev (fast iteration, debug symbols)

# Release (what we ship)

# Cross-compile (Linux → Windows, static, no deps)

# Cross-compile (Linux host → macOS Apple Silicon)

# Requires macOS SDK paths via -Dsystem_include_path etc.

# Statically linked, no-glibc, single-file binary

## Architecture Pattern (mattneel/zgbc, to mirror)

- **`comptime` opcode tables** for cycle counts and instruction decoding — the best-known pattern for fast interpreter dispatch in Zig.
- **`std.ArrayList` / unmanaged containers** for dynamic structures (sav data is fixed-size, but other structures may grow). Zig 0.16 migrated most containers to "unmanaged" — pass an allocator explicitly per call.
- **`std.heap.GeneralPurposeAllocator`** for the emulator's working set. In 0.16 it is now **lock-free and thread-safe** as `heap.ArenaAllocator` is.
- **Packed structs** (`packed struct`) for CPU registers, PPU flags, MBC mode bits — gives bit-level precision with type safety.

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

## Stack Patterns by Variant

- Don't link SDL3 at all. Use `zig build -Doptimize=ReleaseFast` to a benchmark binary that calls `gb.frame()` N times.
- The mattneel/zgbc pattern: a separate `bench` step in `build.zig` that doesn't import the renderer.
- `zig build -Dtarget=x86_64-windows-gnu` — MinGW cross-compile from Linux. Works out of the box with `castholm/SDL`.
- `zig build -Dtarget=x86_64-windows-msvc` — requires MSVC + Windows 11 SDK installed on the host. First-class per castholm/SDL.
- Build on a Mac with Xcode installed. `castholm/SDL` requires macOS SDK paths.
- Cross-compile from Linux **is explicitly unsupported** by `castholm/SDL` (Apple SLA).
- `zig build -Dtarget=wasm32-emscripten` — but needs Emscripten SDK + castholm/SDL's special `system_include_path` option.
- Consider whether the 160x144 framebuffer + APU would actually benefit from WASM; probably defer per PROJECT.md.
- The breakout example by castholm is the canonical reference. https://github.com/castholm/zig-examples/tree/master/breakout
- The `translator.mod` import pattern is stable.

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
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->

## Conventions

Conventions not yet established. Will populate as patterns emerge during development.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->

## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->

## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, `.github/skills/`, or `.codex/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->

## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:

- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->

<!-- GSD:profile-start -->

## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
