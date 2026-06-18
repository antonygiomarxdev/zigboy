# Feature Research: Game Boy (DMG) Emulators

**Domain:** Console emulator (Game Boy DMG-01, 8-bit, 4.19 MHz)
**Researched:** 2026-06-18
**Confidence:** HIGH (for DMG feature landscape — backed by Pan Docs, SameBoy, Mooneye, Blargg, and a survey of competing emulators); MEDIUM (for prioritization, since "table stakes" is partly judgement)

## Feature Landscape

The Game Boy emulator feature surface is well-documented and surprisingly stable
across 25+ years of implementations. Pan Docs, the GBDev wiki, and the
Blargg/Mooneye test ROMs define a de-facto "completeness checklist." A 2026
DMG-only v1 can credibly cover ~80% of meaningful user-facing features without
CGB, SGB, or peripherals, because most cross-cutting complexity in modern
emulators lives in those three areas.

The 4 key upstream reference points used here:

1. **Pan Docs** (gbdev.io/pandocs) — hardware reference
2. **SameBoy** features page (sameboy.github.io/features) — gold-standard accuracy emulator
3. **BESS 1.0** save-state spec (LIJI32/SameBoy/BESS.md) — cross-emulator save state standard
4. **GoBoy README** (Humpheh/goboy) — explicit TODO list from a recent from-scratch emulator

### Table Stakes (Users Expect These)

These are non-negotiable for a v1 emulator. Missing any one and the project
feels incomplete or broken to a knowledgeable user. The list intentionally
excludes features SameBoy ships that depend on CGB, SGB, or peripherals.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Load and parse `.gb` ROM header** | Every emulator must do this; users expect `zigboy rom.gb` to work | LOW | Parse bytes at `$0100-$014F`; extract title, mapper type, ROM/RAM sizes, header checksum |
| **Sharp LR35902 CPU core** | Without a working CPU, nothing runs | MEDIUM-HIGH | 244 base opcodes (incl. CB-prefixed); full flag model; correct instruction timing in M-cycles |
| **Memory bus with correct mirroring** | Foundation; games depend on Echo RAM=$E000-$FDFF ≡ WRAM=$C000-$DDFF | MEDIUM | Full address map per Pan Docs "Memory Map" |
| **PPU: background + window + sprites + OAM DMA** | Renders the screen; without it, no visible output | HIGH | Most complex subsystem; LCD mode 0-3 timing drives STAT interrupts |
| **LCD mode-based timing (STAT interrupts)** | Many games (Pinball Deluxe, Prehistorik Man) need mode-2/0/1 interrupts to behave correctly | MEDIUM | Tightly coupled to PPU; correctness gate for `dmg-acid` |
| **Timer/divider (DIV/TIMA/TMA/TAC)** | Engine of game logic; falling-edge TIMA → IRQ | LOW-MEDIUM | Edge-detection on TAC-selected bit of DIV, with falling-edge reload from TMA |
| **Joypad input (P1 register + 8 buttons)** | Games are unplayable without it | LOW | D-pad / A / B / Start / Select → polled via P1 bits 4-5 |
| **MBC1 mapper** | ~25% of commercial DMG library (Zelda, Tetris, etc.) | MEDIUM | ROM bank 0/1N, optional RAM 8/32 KiB; tricky edge cases (MBC1 mode flag) |
| **MBC3 mapper** | Pokémon Red/Blue/Yellow, many Capcom titles | MEDIUM | Plus optional RTC (clock); timer-accurate RTC is a HIGH complexity addition |
| **MBC5 mapper** | Late-era DMG library: Donkey Kong Country, Pokemon Crystal-Japan, most "modern" DMG | MEDIUM | Large ROM support (up to 8 MiB), 9-bit bank register (quirk: low bits latch separately) |
| **MBC2 mapper** | Some early titles (e.g., Kirby's Dream Land uses it on some versions); 512×4-bit built-in RAM | LOW-MEDIUM | Nibble addressing; has RAM enable quirk |
| **ROM-ONLY (no mapper)** | Several early titles (Tetris original EU release, etc.) | LOW | Just bank 0 fixed at $0000-$3FFF |
| **Battery-backed SRAM persistence (`.sav`)** | Without it, games like Pokémon (which require battery) lose saves on exit; users expect `zelda.gb` → `zelda.gb.sav` | LOW | File I/O; commit on exit + on a periodic timer (battery corruption risk) |
| **Desktop window rendering (SDL2)** | PROJECT.md requirement; users expect a window | LOW | SDL2 Window + Texture; pick a sane default scaling (e.g., 4× nearest-neighbor) |
| **Keyboard input → joypad mapping** | Without this the emulator is a tech demo | LOW | Hardcoded sensible defaults (arrows=D-pad, Z=A, X=B, Enter=Start, Space=Select) |
| **Frame pacing to ~60 FPS** | Without it the game runs at wrong speed or feels stuttery | LOW | SDL2 vsync OR simple `std.time.sleep`-based pacing |
| **Statically linked binary, no runtime deps** | PROJECT.md hard requirement; users expect `cp zigboy /usr/local/bin && zigboy foo.gb` to work | LOW | `zig build` with `ReleaseSmall` or `ReleaseFast`; bundle SDL2 statically |

### Differentiators (Competitive Advantage)

These features set ZigBoy apart from a baseline emulator. The list is filtered
to align with the PROJECT.md core value: **cycle-accurate, minimal binary,
fast startup, DMG-only, leveraging Zig.**

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **T-cycle accurate CPU + PPU timing** | Direct hit on PROJECT.md "cycle-accurate execution" core value; differentiates from BGB-tier timing | HIGH | Required for `dmg-acid` pass and for DMG-mode-only tests; enables Prehistorik Man and Demotronic-style tricks |
| **Pass Blargg's `dmg-acid` and `cpu_instrs`** | Table-stakes for an "accuracy" emulator; moat against "good enough" hobbyist emulators | HIGH | Listed in PROJECT.md as Active requirement — make sure this is a hard success criterion |
| **Pass Mooneye test suite (acceptance/)** | Standard accuracy benchmark in the GB-dev community; mentions "cycle-accurate" implicitly | MEDIUM-HIGH | Many tests assume `dmg-acid`-style timing; ~80% of tests are achievable by a well-built DMG emulator |
| **BESS 1.0 save state compatibility** | Lets users share state files with SameBoy/BGB; "free" multi-emulator UX; saves need a portable format | MEDIUM | Append BESS footer to internal save state blobs; minimal extra code if internal format exists |
| **MGB (Game Boy Pocket) model** | Tiny additional work for a more accurate boot register profile (B=$00, C=$13, etc.); useful for cycle-accurate tests | LOW | Choose MGB as default model — it's what `dmg-acid` and Mooneye target |
| **DMG-0 boot ROM model option** | Older DMG-0 has different F-flag behaviour; "emulates the differences between different hardware revisions" per SameBoy | LOW | Just a flag in CPU initialization; no real cost |
| **Headless mode / lib API** | Library users (frontends, scripts) can drive the emulator without a window; matches SameBoy's `lib` build target | MEDIUM | Separate `zigboy-core` library crate + optional `zigboy-cli` binary; only needs an `Emulator.stepFrame()` entry point |
| **CLI flags: model override, palette, boot ROM, save slot** | Power users expect a CLI; SameBoy has rich flags | LOW | Use `std.process.args()`; piggyback on positional ROM arg + optional flags |
| **Selectable DMG palette** | The original DMG is green-tinted, not gray; users expect a "green LCD" option | LOW | 4 standard palettes (green LCD, gray LCD, inverted) → baked into shader or 256-entry LUT |
| **Runtime stats overlay (FPS, frame counter, ROM title)** | SameBoy OSD; useful for developers | LOW | Toggleable in CLI; render via SDL2 texture blit on top of frame |
| **Deterministic frame buffer** | PROJECT.md hard requirement: same ROM + same input → same output bit-for-bit | MEDIUM | Demands no uninitialized reads; pattern-fill WRAM/HRAM at boot consistently (see Pan Docs "Console state after boot ROM hand-off") |
| **Single static binary < 5 MB** | PROJECT.md requirement; moat against SameBoy (~3 MB core but bundled with assets), mGBA (much larger) | LOW-MEDIUM | `ReleaseSmall` + `strip`; statically link SDL2; this is *trivially* a differentiator given the Zig stack |
| **Fast startup < 50 ms to first frame** | PROJECT.md "fast startup"; unusual for emulators; leveraged for scripting/CLI use | LOW | No async init; no big config files; no shader compilation stalls |
| **ROM metadata dump (--info CLI flag)** | Prints title, mapper, ROM/RAM sizes, header checksum; useful for ROM hacking and CI | LOW | Reuses existing header parser; zero new logic |
| **Scaled-up rendering without bilinear blur (nearest-neighbor integer scales)** | Many emulators smear pixels; users want crisp pixel art | LOW | Default scale=4× or 6× nearest-neighbor; optional scanline filter |
| **Multi-platform: Linux x86_64 → macOS ARM64 → Windows** | PROJECT.md roadmap; usually emulators are tier-1 on one platform | MEDIUM | SDL2 abstracts the platform; Zig cross-compiles; main cost is CI |
| **Cycle-accurate PPU mid-scanline effects** | Tied to overall accuracy story; required for tech demos (Prehistorik Man) and DMG-acid | HIGH | APU-aware STAT triggers (e.g., mode 3 trigger delay); LCD power-on delay; window Y-equals-LY quirk |

### Anti-Features (Commonly Requested, Often Problematic)

Features that seem good on paper but hurt the "small, fast, accurate, DMG-only"
thesis. Each one has a deliberate "instead" column.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| **Game Boy Color (CGB) support** | "Why not support both?" | Doubles PPU complexity (HDMA, BG attributes, palettes, double-speed mode), requires separate VRAM banks, separate CPU mode — every subsystem gets a fork. The 4× effort is well-documented (cinoop, Gearboy both slowed dramatically when adding CGB) | Ship DMG first; if a CGB v2 is ever built, fork or rewrite the PPU, not retrofit it. |
| **Super Game Boy (SGB) support** | "It's just a mapper!" | SGB is a *full SNES-side video processor* the Game Boy streams commands to. Emulation requires either an SNES emulator core or HLE. Per PROJECT.md, deferred indefinitely | Don't even consider v2 unless committing to an SNES side as well |
| **APU (Audio Processing Unit) emulation** | "Games are silent without it" | 4-channel APU with frame sequencer, sweep unit, length timers, wave RAM, NRx4 trigger quirks, and audio buffer management. Adds 10-15% core code surface, makes the binary bigger, and complicates the SDL2 integration significantly | Defer to v1.x per PROJECT.md; APU is a strict superset work and well-isolated from CPU/PPU timing |
| **Game Boy Printer, Camera, Infrared, Link Cable** | Cool peripherals | Each is a non-trivial separate subsystem: Printer needs a 4-shade dithering algorithm; Camera needs image sensor emulation; Link Cable needs peer connection. Zero overlap with DMG-only core | Out of scope per PROJECT.md; defer indefinitely |
| **Game Genie / GameShark cheat UI** | Users want to cheat | Adds a memory-write pipeline, an in-game menu, and a parser for a hex string format. Not aligned with "developer / reference" framing of PROJECT.md | Skip in v1; rely on regular RAM editing via future debugger (out of scope too) |
| **TAS / movie recording (`.gbm` / BKM format)** | Speedrun community wants this | Demands frame-perfect input recording AND deterministic per-frame execution. Easy to half-build, hard to ship correctly. Conflicts with fast startup and small binary | Defer; if ever built, leverage BESS as a starting point and design for deterministic stepping from day 1 |
| **Rewind (real-time state rollback)** | "I made a mistake" | Memory-hungry (state snapshot every N frames); trades off the small-RAM goal. Hard to integrate with BESS unless re-encoding | Defer; document that BESS save states can be used for coarse rewind |
| **In-game debugger / disassembler UI** | POWER-USER magnet | Huge scope (memory viewer, breakpoint manager, expression evaluator, watchpoints, call stack); this is essentially a separate application | Per PROJECT.md: "runtime stats only in v1; full debugger is a separate tool." Honour this strictly |
| **Mobile / WASM / iOS targets** | "Reach more users" | iOS forces Cocoa frontend (and Apple Sign-In); WASM forces Emscripten-level SDL2 plumbing; both inflate binary size and break the static-binary story | Defer per PROJECT.md; the core library CAN be designed to be embedding-friendly without committing to these builds |
| **Networking (NetPlay, Cloud saves)** | "Let me play online" | Requires deterministic frame stepping, state sync protocol, and a session layer. Massive complexity multiplier | Out of scope |
| **Realistic boot ROM (DMG 256 bytes)** | "Full accuracy needs the real boot ROM" | Boot ROMs are copyrighted. SameBoy includes open-source reimplementations. Distributing boot ROM dumps in your binary is a legal risk | Either bundle an open-source boot ROM (cost: small) or skip boot ROM entirely (let cartridge start at $0100 directly) |
| **Custom GLSL/Metal shaders** | "Let users pick CRT filters" | Requires OpenGL 3.2+ or Metal; inflates binary dependencies; destroys the "single static binary" story | Defer; nearest-neighbor scanline filter is the only thing v1 needs |
| **Skins / multi-game launcher / config GUI** | "Where are the menus?" | Adds 5-10 MB of UI code (Electron, Qt, or Dear ImGui). Defeats the small-binary goal | Stay CLI; runtime stats overlay is the only GUI |
| **Frame blending / motion blur** | "Smoother scrolling" | Hides bugs and breaks the "deterministic frame buffer" requirement | Defer; deterministic per-frame output is non-negotiable per PROJECT.md |
| **Save state in BESS but RTC for MBC3** | "Just persist the clock" | RTC adds *substantial* complexity (UNIX timestamp tie-in, latch behaviour). MBC3-RTC games are very few (Pokémon Gold/Silver are CGB). DMG-only essentially has no popular MBC3+RTC titles | Skip RTC in v1; revisit if v2 adds CGB |
| **Dynamic rate control / frame skipping** | "Speed boost on slow systems" | Breaks determinism (frame N may produce different outputs based on real-time pacing). Also pointless for DMG at 4 MHz | Not needed; DMG is a trivial workload for any modern CPU |
| **Bundling ROMs, BIOS, or assets** | "Just include a test ROM" | Copyrighted. No serious emulator bundles non-open-source ROMs | Download separately; ship a `tests/` script that fetches them |

## Feature Dependencies

```
Load ROM (.gb)
    └──requires──> Header parser
                       └──requires──> MBC dispatch table
                                          └──requires──> MBC1 / MBC3 / MBC5 / MBC2 / ROM-ONLY
                                                             └──requires──> Battery save (.sav)

Render frame
    └──requires──> CPU step (T-cycle accurate)
                       └──requires──> Memory bus
                                          └──requires──> PPU (with LCD mode timing)
                                                            └──requires──> OAM DMA
                                                                                  └──requires──> SDL2 window
                                                                                                     └──requires──> Frame pacing

Input
    └──requires──> Joypad poll (P1 register)
                       └──requires──> SDL2 keyboard event pump

Save / load state
    └──requires──> Emulator snapshot (whole machine)
                       └──enhances──> BESS 1.0 footer
                                           └──enhances──> Cross-emulator save state portability

Run test ROM (e.g., dmg-acid)
    └──requires──> Full CPU + PPU + bus accuracy
                       └──requires──> Headless mode
                                          └──requires──> Same machine-state API
```

### Dependency Notes

- **PPU requires CPU + memory bus:** the PPU reads from VRAM (bus) on every cycle, so it cannot be tested standalone. The bus must be functional first.
- **Save states require whole machine state:** the snapshot must include CPU registers, PPU internal mode counter, MBC bank registers, and battery RAM. BESS 1.0 specifies a portable structure for this.
- **Boot ROM is an optional dependency:** Skip the boot ROM and games still run (cartridge starts at $0100). For full accuracy, support the optional 256-byte DMG boot ROM dump.
- **APU is strictly independent of CPU/PPU correctness:** the project can ship DMG visual+input-only v1 and bolt APU on later without disturbing other subsystems.
- **Headless mode unlocks test ROM runners:** once you have `Emulator.stepFrame()` without a window, the `dmg-acid` test runner is straightforward to write as a separate small binary.
- **RTC conflicts with "small binary" goal:** RTC simulation requires Unix-timestamp-style time source and latch register behaviour. Skip in v1.
- **Save states conflict with "fast startup" goal:** save state load reads from disk. Keep the format small and unzipped. Document that cold-start ROM load is the fast path.

## MVP Definition

### Launch With (v1)

Minimum viable product — what's needed to validate the concept that
"ZigBoy is a hyper-fast, super-lightweight, cycle-accurate DMG emulator."

- [ ] **Load and parse `.gb` ROM header** — without this, the binary does nothing
- [ ] **Sharp LR35902 CPU core with M-cycle timing** — correctness foundation
- [ ] **Memory bus (ROM, VRAM, WRAM, HRAM, OAM, I/O, Echo RAM)** — glue layer
- [ ] **PPU (background, window, sprites, OAM DMA, mode-based STAT timing)** — the screen
- [ ] **Timer/divider (DIV/TIMA/TMA/TAC, falling-edge IRQ)** — game logic ticks
- [ ] **Joypad input via P1 register** — playability
- [ ] **MBC1, MBC3, MBC5, MBC2, ROM-ONLY mappers** — library coverage (~99% of commercial DMG)
- [ ] **Battery-backed SRAM persistence (`.sav`)** — saves survive exit
- [ ] **SDL2 desktop window with frame pacing** — actually display something
- [ ] **Keyboard → joypad mapping** — play
- [ ] **Blargg `cpu_instrs` and `dmg-acid` tests pass** — accuracy gate per PROJECT.md
- [ ] **Single static binary, no runtime deps, < 5 MB** — PROJECT.md requirement
- [ ] **Deterministic per-frame output** — PROJECT.md hard requirement

### Add After Validation (v1.x)

Features to add once the v1 core is stable and accuracy is confirmed. These
should be added in priority order based on community feedback.

- [ ] **BESS 1.0 save state support** — same-format save states as SameBoy; user demand is high
- [ ] **Save state load/save (any format)** — universal emulator feature; users expect it
- [ ] **Boot ROM support (DMG 256-byte, open-source dump or skip prompt)** — full accuracy
- [ ] **MGB (Game Boy Pocket) model selection** — small accuracy boost; matches test ROM targets
- [ ] **DMG-0 model option** — accuracy pedantry; needed for some boot ROM tests
- [ ] **DMG palette selection (green LCD, gray LCD, etc.)** — UX
- [ ] **Runtime stats overlay (FPS, frame counter)** — developer UX
- [ ] **CLI flags (`--info`, `--palette=`, `--model=dmg|mgb`, `--headless`, `--boot-rom=...`)** — power users
- [ ] **Mooneye test suite pass** — accuracy moat
- [ ] **macOS ARM64 and Windows builds** — PROJECT.md platform roadmap

### Future Consideration (v2+)

Features to defer until product-market fit is established or until APU/CGB
work begins. Each of these has its own research/architecture phase if ever done.

- [ ] **APU (audio) emulation** — substantial work, isolated subsystem
- [ ] **CGB support** — full v2 with separate PPU; possibly a separate project
- [ ] **SGB support** — only viable alongside an SNES core
- [ ] **Link cable / Game Boy Printer / Camera / Infrared** — peripheral complexity
- [ ] **Debugger / disassembler UI** — separate tool per PROJECT.md
- [ ] **TAS / movie recording** — needs deterministic stepping from day 1 if ever done
- [ ] **Rewind (state rollback)** — memory-hungry; orthogonal to the small-binary thesis
- [ ] **WASM build target** — viable after core is stable; needs Emscripten+SDL2 plumbing
- [ ] **Mobile targets (iOS / Android)** — requires native UI shell per platform
- [ ] **Cheat code UI (Game Genie / GameShark)** — out of "developer reference" framing
- [ ] **Frame blending / motion blur / CRT shaders** — would break determinism
- [ ] **Networking / NetPlay** — massive complexity
- [ ] **PCM12 / PCM34 register emulation** — niche; tech demo specific
- [ ] **Rumble support** — peripheral; rare in DMG

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| ROM header parser | HIGH | LOW | P1 |
| LR35902 CPU core | HIGH | MEDIUM-HIGH | P1 |
| Memory bus | HIGH | MEDIUM | P1 |
| PPU (background + window + sprites + OAM DMA) | HIGH | HIGH | P1 |
| LCD mode-based STAT timing | HIGH | MEDIUM | P1 |
| Timer/divider | HIGH | LOW-MEDIUM | P1 |
| Joypad input | HIGH | LOW | P1 |
| MBC1, MBC3, MBC5, MBC2, ROM-ONLY | HIGH | MEDIUM (each) | P1 |
| Battery `.sav` persistence | HIGH | LOW | P1 |
| SDL2 desktop window | HIGH | LOW | P1 |
| Keyboard mapping | HIGH | LOW | P1 |
| Frame pacing | HIGH | LOW | P1 |
| Static binary < 5 MB | MEDIUM (PROJECT.md) | LOW | P1 |
| Deterministic frame buffer | HIGH (PROJECT.md) | MEDIUM | P1 |
| Blargg `cpu_instrs` + `dmg-acid` | HIGH | HIGH (whole-core) | P1 |
| BESS 1.0 save state | MEDIUM | MEDIUM | P2 |
| Save state (any format) | MEDIUM | MEDIUM | P2 |
| Boot ROM (DMG 256-byte) | MEDIUM | LOW-MEDIUM | P2 |
| MGB / DMG-0 model selection | LOW | LOW | P2 |
| DMG palette selection | MEDIUM | LOW | P2 |
| Runtime stats overlay | MEDIUM | LOW | P2 |
| CLI flags (`--info`, `--headless`, etc.) | MEDIUM | LOW | P2 |
| Mooneye test suite pass | MEDIUM (moat) | MEDIUM | P2 |
| macOS / Windows builds | HIGH | MEDIUM | P2 |
| T-cycle PPU mid-scanline effects | MEDIUM (niche) | HIGH | P2 |
| Frame stepping / pause | MEDIUM | LOW | P2 |
| Reset button (R-key) | MEDIUM | LOW | P2 |
| APU (audio) | HIGH | HIGH | P3 (defer to v1.x) |
| BESS RTC block | LOW (no popular DMG RTC) | MEDIUM | P3 (defer) |
| CGB support | HIGH (different project) | VERY HIGH | v2+ |
| SGB / Link cable / Printer / Camera | LOW (each) | HIGH (each) | v2+ / out |
| Debugger UI | MEDIUM (developer magnet) | VERY HIGH | separate tool |
| TAS / movie recording | LOW (community-driven) | MEDIUM-HIGH | v2+ |
| Rewind | LOW (UX) | MEDIUM (RAM cost) | v2+ |
| Mobile / WASM | MEDIUM (reach) | MEDIUM-HIGH | v2+ |
| Cheat UI | LOW (off-brand) | MEDIUM | v2+ |
| Frame blending / shaders | LOW (off-brand) | MEDIUM (breaks determinism) | v2+ / out |
| Networking / NetPlay | LOW | VERY HIGH | out |

**Priority key:**
- P1: Must have for v1 launch
- P2: Should have, add once v1 is stable
- P3: Defer; revisit after APU / CGB / debugger decisions

## Competitor Feature Analysis

| Feature | SameBoy (C) | GoBoy (Go) | BGB (Windows) | mGBA (multi-platform) | **ZigBoy v1 (planned)** |
|---------|-------------|------------|----------------|------------------------|--------------------------|
| DMG accuracy | Excellent (passes dmg-acid, Mooneye, Blargg) | Good (passes Blargg cpu_instrs, instr_timing) | Excellent (reference) | Excellent | **Target: cycle-accurate, passes dmg-acid + cpu_instrs** |
| CGB/SGB | Yes / Yes | Yes / No | Yes / Yes | Yes / No | **No / No** (DMG-only) |
| Static binary | No (depends on SDL2 / Cocoa) | No (depends on pixel + OpenGL) | No (Windows-only installer) | No (large, many deps) | **Yes (< 5 MB statically linked)** |
| Binary size (SDL frontend) | ~3 MB core, ~6 MB with assets | ~10 MB (Go runtime) | ~5 MB exe (with assets) | ~6 MB | **< 5 MB target** |
| Fast startup | ~50 ms (Cocoa), ~200 ms (SDL) | ~500 ms (Go runtime) | ~300 ms | ~400 ms | **Target: < 50 ms** |
| Save states | Yes (BESS 1.0 + native) | TODO | Yes (BGB native) | Yes | **P2 (BESS 1.0)** |
| Battery save (`.sav`) | Yes | Yes | Yes | Yes | **Yes (P1)** |
| APU | Yes (96 KHz, sample-accurate) | Partial | Yes (96 KHz) | Yes | **Defer to v1.x** |
| Debugger | Yes (text-based, advanced) | Basic opcode log | Yes (best-in-class GUI) | Yes | **Out of scope (separate tool)** |
| Mappers | All known (incl. MBC6/7) | MBC1/3/5 partial | All known | All known | **MBC1/2/3/5 + ROM-ONLY (P1)** |
| Boot ROMs | Open-source bundled | No | No (uses system ROMs) | Optional | **Optional (P2)** |
| Cross-platform | macOS/Win/Linux/iOS/watchOS | Win/Mac/Linux | Windows only | Win/Mac/Linux/3DS/Switch | **Linux → macOS → Windows (P1/P2)** |
| Test ROM passes | All Blargg, all Mooneye, Wilbert Pol's | Blargg cpu_instrs, instr_timing | All known | All known | **Blargg cpu_instrs + dmg-acid (P1)** |
| Language | C (portable) | Go | C + Win32 | C | **Zig** |
| Lines of code (rough) | ~80K | ~6K | ~200K | ~150K | **Target: < 15K (small)** |

**Key observations:**
- The DMG-only niche is *very* small for emulators in 2026 — every major
  competitor also does CGB and (except mGBA) SGB. The "DMG-only" thesis is a
  defensible niche if the trade is "smallest, fastest, most accurate DMG core
  ever written in Zig."
- SameBoy is the strongest benchmark. The "pass all of Blargg, all of Mooneye,
  and Wilbert Pol's tests" bar is achievable for a DMG-only emulator.
- SameBoy already defines BESS 1.0 as the cross-emulator save state standard;
  ZigBoy adopting it is "free" interop.
- The `< 5 MB` static binary target is differentiated territory; SameBoy with
  its bundled assets is much larger.

## Sources

- [Pan Docs — Foreword and Table of Contents](https://gbdev.io/pandocs/) — domain reference (HIGH)
- [Pan Docs — The Cartridge Header](https://gbdev.io/pandocs/The_Cartridge_Header.html) — mapper type list, header layout (HIGH)
- [Pan Docs — Memory Bank Controllers (MBCs)](https://gbdev.io/pandocs/MBCs.html) — MBC dispatch semantics (HIGH)
- [Pan Docs — Power Up Sequence](https://gbdev.io/pandocs/Power_Up_Sequence.html) — DMG vs MGB register values at boot (HIGH)
- [Pan Docs — Reducing Power Consumption (HALT/STOP)](https://gbdev.io/pandocs/Reducing_Power_Consumption.html) — STOP instruction corner cases (HIGH)
- [SameBoy features page](https://sameboy.github.io/features/) — gold-standard accuracy emulator feature list (HIGH)
- [SameBoy BESS.md](https://github.com/LIJI32/SameBoy/blob/master/BESS.md) — Best Effort Save State 1.0 specification (HIGH)
- [SameBoy GitHub README](https://github.com/LIJI32/SameBoy) — additional accuracy and platform details (HIGH)
- [Humpheh/goboy GitHub README](https://github.com/Humpheh/goboy) — recent from-scratch emulator's explicit TODO list (MEDIUM — 2020, may be stale)
- [PROJECT.md](/home/ksante/dev/zigboy/.planning/PROJECT.md) — project requirements, out-of-scope, constraints (HIGH)

## Gaps to Address

- **Audio quality target unclear:** v1 has no APU, but the APU deferred-to-v1.x
  plan needs a quality bar. Should we target SameBoy's 96 KHz? Or match the
  Pan Docs' 91-cycle frame rate? Worth a separate architecture research when
  APU work begins.
- **Boot ROM strategy:** Open-source DMG boot ROM dumps exist (SameBoy ships
  one in the same repo under `BootROMs/dmg_boot.asm`). Legal status is murky;
  PROJECT.md doesn't address this. Recommend adding to PROJECT.md's
  constraints or a new `docs/legal.md` before v1 ships with boot ROM support.
- **Test ROM acquisition:** Both Blargg and Mooneye test ROMs are hosted on
  GitHub but require the user to fetch them. Should ZigBoy ship a `zig build
  test` task that fetches and runs them automatically? (CI-friendly.)
- **What about MMM01?** Pan Docs lists it but no commercial titles use it.
  Not in PROJECT.md's MBC list. Defer.
- **MBC6, MBC7, HuC1, HuC3, BANDAI TAMA5, Pocket Camera:** all listed in Pan
  Docs; zero relevant DMG-only commercial titles. None needed for v1.
- **Colour correction:** SameBoy has 6 colour correction settings. Out of
  scope for DMG (it's monochrome), but worth a callout: should ZigBoy apply
  any LCD phosphor warmth filter? Probably no for "minimal binary."

---
*Feature research for: ZigBoy — Game Boy (DMG) Emulator*
*Researched: 2026-06-18*
