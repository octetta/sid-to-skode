# sid-to-skode

[![Gleam](https://img.shields.io/badge/language-Gleam-ffaff3.svg)](https://gleam.run/)
[![Lustre](https://img.shields.io/badge/frontend-Lustre-ff69b4.svg)](https://hexdocs.pm/lustre/)
[![Audio Engine](https://img.shields.io/badge/synth-Skred_0.80.0-38bdf8.svg)](https://github.com/octetta/pulp)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

High-fidelity Commodore 64 MOS 6581 / 8580 SID converter, interactive in-browser audio studio, and real-time playback engine for the **Skred 0.80.0** synthesizer and **Skode** live-coding sequencer.

Available both as a **100% client-side web application** with in-browser 6502 CPU execution, WebAssembly playback, and DeepSID integration, as well as a standalone **native CLI** runner written in pure Gleam.

---

## Table of Contents

- [Welcome & Overview](#welcome--overview)
- [Architecture: Functional Core, WebAssembly Shell](#architecture-functional-core-webassembly-shell)
- [How SID Registers Map to Skred](#how-sid-registers-map-to-skred)
  - [1. Frequency Tuning (`f#`)](#1-frequency-tuning-f)
  - [2. Pulse Width Modulation (PWM) via CZ Phase Distortion (`c1,#`)](#2-pulse-width-modulation-pwm-via-cz-phase-distortion-c1)
  - [3. Band-Limited Waveforms & Dual Noise Engine](#3-band-limited-waveforms--dual-noise-engine)
  - [4. ADSR Envelope Generators (`t`)](#4-adsr-envelope-generators-t)
  - [5. Ring Modulation (`XM`)](#5-ring-modulation-xm)
  - [6. Multi-Mode Biquad Filters (`j`, `k`, `q`)](#6-multi-mode-biquad-filters-j-k-q)
- [Web Application Studio](#web-application-studio)
  - [In-Browser 6502 Emulation via `siddump_wasm`](#in-browser-6502-emulation-via-siddump_wasm)
  - [DeepSID & High Voltage SID Collection (HVSC) Integration](#deepsid--high-voltage-sid-collection-hvsc-integration)
  - [Real-Time Stereo Separation](#real-time-stereo-separation)
- [Standalone CLI (`cli.gleam`)](#standalone-cli-cligleam)
- [Development & Makefile Targets](#development--makefile-targets)
- [License](#license)

---

## Welcome & Overview

`sid-to-skode` bridges the legendary Commodore 64 soundchip (MOS 6581 and 8580) with modern functional live-coding synthesis.

Instead of playing back pre-rendered WAV recordings or relying on heavy software plugins, `sid-to-skode`:
1. Executes original `.sid` files frame-by-frame (typically 50 Hz PAL / 20 ms ticks) through an in-browser 6502 CPU emulator or parses raw `siddump` text tables.
2. Performs delta-compression in pure Gleam to eliminate redundant writes.
3. Translates raw 16-bit pitch, 12-bit pulse width, ADSR envelopes, ring modulation, and filters into human-readable Skode live-coding patterns (`y0 [ ... ] x0`).
4. Synthesizes the result in real time via the **Skred 0.80.0 WebAssembly sound engine** (`github.com/octetta/pulp`).

---

## Architecture: Functional Core, WebAssembly Shell

```text
┌────────────────────────────────────────────────────────┐
│                   Imperative Shell                     │
│  - Web Audio Context (Skred 0.80.0 WASM Audio Engine)  │
│  - In-Browser 6502 SID Execution (siddump_wasm)        │
│  - DeepSID REST API Client (HVSC Cloud Catalog)        │
│  - Drag-and-Drop File System Handlers                  │
└──────────────────────────┬─────────────────────────────┘
                           │ Passes Dump Text & Events
                           ▼
┌────────────────────────────────────────────────────────┐
│                   Functional Core (Gleam)              │
│  - types.gleam       (Strict typed domain model)       │
│  - dump_parser.gleam (Pure text parser for dumps)      │
│  - converter.gleam   (Delta-compression & Skode emit)  │
│  - update / view     (Lustre Elm Architecture UI)      │
└────────────────────────────────────────────────────────┘
```

---

## How SID Registers Map to Skred

### 1. Frequency Tuning (`f#`)
The Commodore 64 calculates pitch using a 16-bit register ($F_{reg}$) driven by the master PAL clock ($985,248.4\text{ Hz}$):

$$f_{\text{Hz}} = F_{reg} \times \frac{985248.4}{16777216.0} \approx F_{reg} \times 0.0587285\text{ Hz}$$

Skred accepts arbitrary floating-point frequencies via `f#` (e.g. `f440.11`, `f2636.20`), ensuring pitch slides, detune, and arpeggios are microtonally accurate.

### 2. Pulse Width Modulation (PWM) via CZ Phase Distortion (`c1,#`)
The SID pulse wave features a 12-bit Pulse Width register ($0$ to $4095$), where $2048$ ($0\text{x}800$) is a 50% square wave.

Skred provides Casio CZ-inspired phase distortion (`c1,d`), where parameter $d \in [-1.0, 1.0]$ moves the waveform inflection breakpoint. By setting:

$$d = \frac{\text{PW} - 2048}{2048.0}$$

Skred's band-limited square wave (`w16`) reproduces 12-bit PWM sweeps without aliasing.

### 3. Band-Limited Waveforms & Dual Noise Engine
- **Sawtooth** $\rightarrow$ `w15` (32-harmonic band-limited DWGS Saw).
- **Square / Pulse** $\rightarrow$ `w16` (Band-limited DWGS Square) with `c1,d`.
- **Triangle** $\rightarrow$ `w18` (DWGS Triangle).
- **Noise** $\rightarrow$ Handled by Skred's dual noise architecture:
  - `w5` (`WAVE_TABLE_NOISE`): 4096-sample looped pseudo-random wavetable that pitch-shifts with `f#`, mimicking the repetitive tonal rattle of the low-frequency SID LFSR.
  - `w6` (`WAVE_TABLE_NOISE_ALT`): Knuth MMIX 64-bit LCG white noise computed fresh per sample for crisp hi-hats, snares, and breathy noise sweeps.

### 4. ADSR Envelope Generators (`t`)
SID envelope timing maps to seconds via lookup constants:
- **Attack (0–15):** $2\text{ ms}$ to $8\text{ seconds}$.
- **Decay & Release (0–15):** $6\text{ ms}$ to $24\text{ seconds}$.
- **Sustain (0–15):** Normalized linear level ($0.0$ to $1.0$).

Translated into Skred amplitude ADSR: `t <attack>,<decay>,<sustain>,<release>` triggered via `l1` and released with `l0`.

### 5. Ring Modulation (`XM`)
SID ring modulation between Voice 1 and Voice 3, Voice 2 and Voice 1, and Voice 3 and Voice 2 maps directly to Skred's cross-oscillator ring modulation:
- Voice 1: `v0 XM 2`
- Voice 2: `v1 XM 0`
- Voice 3: `v2 XM 1`

### 6. Multi-Mode Biquad Filters (`j`, `k`, `q`)
The SID 11-bit Cutoff ($30\text{ Hz} - 12\text{ kHz}$) and 4-bit Resonance map to Skred biquad filters:
- Cutoff: `k <hz>`
- Resonance: `q <0.707 - 7.0>`
- Filter Types: `j1` (Low-pass), `j2` (High-pass), `j3` (Band-pass), `j4` (Notch).

---

## Web Application Studio

The web application runs 100% client-side with zero server dependencies:
- **Instant Drag-and-Drop**: Drop any `.sid` or `.dump` file onto the window.
- **In-Browser 6502 WASM Execution**: When a `.sid` file is dropped, `siddump_wasm` executes the 6502 assembly and outputs the frame dump in milliseconds.
- **DeepSID Integration**: Click **🎲 Random from DeepSID** to download an iconic tune directly from the High Voltage SID Collection (>50,000 tunes).
- **Real-Time Stereo Separation Modes**:
  - `🎧 75% Headphone`: Natural binaural listening (`p -0.6` / `p 0.6` / `p 0.0`).
  - `🔊 Wide 100%`: Amiga/hard-panned experience (`p -1.0` / `p 1.0` / `p 0.0`).
  - `📻 Mono 0%`: Centered mono mixdown (`p 0.0`).
- **Live Skode Inspector**: Real-time view of generated `main.sk` with one-click clipboard copy and file export.

---

## Standalone CLI (`cli.gleam`)

Batch convert `.dump` files directly from your terminal:

```bash
# Convert a dump to Skode script
node -e 'import("./build/dev/javascript/sid_to_skode/cli.mjs").then(m => m.main())' demos/commando.dump -o commando.sk
```

---

## Development & Makefile Targets

```bash
make help       # View all Makefile targets
make deps       # Download Gleam and npm dependencies
make check      # Verify Gleam types and compilation
make test       # Run Gleam unit test suite
make build      # Compile Gleam and bundle production web app into dist/
make dev        # Start Vite development server on port 3000
make preview    # Preview production build on port 3000
```

---

## License

MIT License. Designed and developed with reverence for the Commodore 64 demoscene and functional audio programming.
