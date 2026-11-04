# sid-to-skode

[![Version](https://img.shields.io/badge/version-v0.1.0-blue.svg)](gleam.toml)
[![Gleam](https://img.shields.io/badge/language-Gleam-ffaff3.svg)](https://gleam.run/)
[![Lustre](https://img.shields.io/badge/frontend-Lustre-ff69b4.svg)](https://hexdocs.pm/lustre/)
[![Audio Engine](https://img.shields.io/badge/synth-Skred_0.80.0-38bdf8.svg)](https://github.com/octetta/pulp)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

High-fidelity Commodore 64 MOS 6581 / 8580 SID converter, interactive in-browser audio studio, and real-time playback engine for the **Skred 0.80.0** synthesizer and **Skode** live-coding sequencer.

Available both as a **100% client-side web application** with in-browser 6502 CPU execution, WebAssembly playback, and High Voltage SID Collection streaming, as well as a standalone **native CLI** runner written in pure Gleam.

🌐 **Interactive Web Studio:** [octetta.github.io/sid-to-skode](https://octetta.github.io/sid-to-skode/)  
📦 **Skred Audio Engine:** [github.com/octetta/pulp](https://github.com/octetta/pulp)  
👤 **Author:** Joseph Stewart ([josephestewart.com](https://josephestewart.com)) · [YouTube: @octetta](https://youtube.com/@octetta)

---

## Table of Contents

- [Welcome & Philosophy](#welcome--philosophy)
  - [An Earnest Gleam & Lustre Learning Exercise](#an-earnest-gleam--lustre-learning-exercise)
  - [Towards "Noisy Web Apps" (CodeBEAM 2026 Haarlem Workshop)](#towards-noisy-web-apps-codebeam-2026-haarlem-workshop)
- [How It Works: Functional Core & WebAssembly Shell](#how-it-works-functional-core--webassembly-shell)
  - [In-Browser 6502 Emulation via `siddump_wasm`](#in-browser-6502-emulation-via-siddump_wasm)
  - [Where `siddump_wasm` Came From](#where-siddump_wasm-came-from)
- [How SID Registers Map to Skred](#how-sid-registers-map-to-skred)
  - [1. Frequency Tuning (`f#`)](#1-frequency-tuning-f)
  - [2. Pulse Width Modulation (PWM) via CZ Phase Distortion (`c1,#`)](#2-pulse-width-modulation-pwm-via-cz-phase-distortion-c1)
  - [3. Band-Limited Analog Waveforms (`w15`, `w16`, `w18`, `w5`)](#3-band-limited-analog-waveforms-w15-w16-w18-w5)
  - [4. ADSR Envelope Generators (`t`)](#4-adsr-envelope-generators-t)
  - [5. Cross-Oscillator Ring Modulation (`XM`)](#5-cross-oscillator-ring-modulation-xm)
  - [6. Realtime Biquad Filter Automation (`j`, `k`, `q`)](#6-realtime-biquad-filter-automation-j-k-q)
  - [7. Calibrated Headroom & Authentic Mono Default](#7-calibrated-headroom--authentic-mono-default)
  - [8. C64 PCM Digi Sample Extraction Magic (`w310+`, `/D`, `( ... ) /d`, `f440`)](#8-c64-pcm-digi-sample-extraction-magic-w310-d----d-f440)
- [Web Studio Features](#web-studio-features)
  - [Featured Offline Demos: Hubbard & Hülsbeck](#featured-offline-demos-hubbard--hülsbeck)
  - [100% Client-Side Public Archive Streaming (No Pre-Download Bloat)](#100-client-side-public-archive-streaming-no-pre-download-bloat)
  - [Live SID Register Activity Monitor & Delta Inspector](#live-sid-register-activity-monitor--delta-inspector)
  - [Dedicated Digi Sample Voice Panning & Interactive Cards](#dedicated-digi-sample-voice-panning--interactive-cards)
  - [Interactive Skred Terminal REPL (`Ctrl+~`)](#interactive-skred-terminal-repl-ctrl)
  - [Mobile & Touch-Friendly Interface](#mobile--touch-friendly-interface)
  - [Direct DeepSID & HVSC Mirror Links](#direct-deepsid--hvsc-mirror-links)
- [Standalone CLI (`cli.gleam`)](#standalone-cli-cligleam)
- [Development, Continuous Deployment & GitHub Pages](#development-continuous-deployment--github-pages)
- [Credits & Acknowledgements](#credits--acknowledgements)
- [License](#license)

---

## Welcome & Philosophy

### An Earnest Gleam & Lustre Learning Exercise

`sid-to-skode` was conceived out of love and reverence for the Commodore 64 demoscene, chip music history, and the expressive clarity of modern functional programming in [Gleam](https://gleam.run/) and [Lustre](https://hexdocs.pm/lustre/).

This project is an earnest learning exercise: a deliberate, playful experiment in applying pure functional data modeling, strict type safety, and The Elm Architecture to the messy, quirk-filled world of retro audio emulation. It was vibe-coded with love, curiosity, and deep respect for the pioneers of computer music.

There is real joy in watching an original `.sid` tune composed in 1985—packed into a few kilobytes of MOS 6502 machine code—load into a modern browser tab, run frame-by-frame through WebAssembly, translate through pure Gleam types, and stream into a modern bandlimited synthesizer with zero server infrastructure.

### Towards "Noisy Web Apps" (CodeBEAM 2026 Haarlem Workshop)

During the **CodeBEAM 2026 Haarlem Workshop**, Joseph Stewart made a heartfelt appeal: **the web is too quiet**. For three decades, web applications have evolved into visually polished, responsive, and data-dense interfaces—yet they remain largely silent, sterile, and sonically inert.

`sid-to-skode` (along with its sibling `mod-to-skode`) serves as a practical, open-source proof of concept for **"noisy web apps"**:
- Demonstrating that the **Skred audio engine** (`github.com/octetta/pulp`) can be seamlessly embedded into web browsers as a low-latency, multi-threaded WebAssembly audio synthesizer.
- Showing that sound in web apps does not need to be pre-baked, static audio files; it can be generated, modulated, filtered, and live-coded on the fly using functional state machines.
- Proving that BEAM-inspired reactive paradigms (Gleam and Lustre) handle rapid audio step synchronization (50 Hz PAL frame clocks) smoothly and reliably alongside interactive user interfaces without glitching or dropping frames.

---

## How It Works: Functional Core & WebAssembly Shell

```text
┌────────────────────────────────────────────────────────────────────────┐
│                   Imperative Shell (JavaScript & WASM)                  │
│  - Web Audio Context & Skred 0.80.0 multi-threaded synthesizer core    │
│  - In-browser 6502 CPU execution via siddump_wasm (no backend servers)  │
│  - On-the-fly public HVSC fetching via GitHub raw / jsDelivr mirrors   │
│  - Interactive Skred REPL console drawer (Ctrl+~ / Backquote)          │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ Frames & Events
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                   Functional Core (Pure Gleam & Lustre)                │
│  - types.gleam       (Strict typed domain: voices, filters, frames)    │
│  - dump_parser.gleam (Pure text parser with O(1) indexed frame maps)   │
│  - converter.gleam   (Delta compression & authentic Skode emitter)     │
│  - update / view     (The Elm Architecture: pure UI state machine)     │
└────────────────────────────────────────────────────────────────────────┘
```

### In-Browser 6502 Emulation via `siddump_wasm`

When a `.sid` file is dropped or fetched from the public archive:
1. The raw binary is loaded into an in-memory virtual filesystem.
2. `siddump_wasm` executes the file's native 6502 assembly init and play routines for the target duration (e.g. 50 Hz PAL / 20 ms per step).
3. Every write to the 29 SID hardware registers ($D400–$D41C) is recorded into a structured text stream.
4. Pure Gleam code parses this stream, performs delta-compression to eliminate redundant writes, and compiles the result into a clean Skode live-coding script (`main.sk`) running in the **Skred 0.80.0** WebAssembly engine.

### Where `siddump_wasm` Came From

The WebAssembly utility `siddump_wasm` was compiled from **`siddump.c`**, an open-source tool originally authored by **Lasse Öörni** (loorni / Cadaver of Covert Bitops, http://cadaver.github.io / http://covertbitops.c64.org).

Lasse Öörni is a giant of the Commodore 64 development community, renowned for creating the BOFH / Metal Warrior series, the `siddump` register analyzer, and `sidreloc`. By compiling his battle-tested C codebase to WebAssembly using Emscripten, `sid-to-skode` enables cycle-accurate 6502 SID execution client-side inside the browser sandbox without requiring native tools or local installations.

---

## How SID Registers Map to Skred

### 1. Frequency Tuning (`f#`)
The Commodore 64 calculates pitch using a 16-bit register ($F_{reg}$) driven by the master PAL clock ($985,248.4\text{ Hz}$):

$$f_{\text{Hz}} = F_{reg} \times \frac{985248.4}{16777216.0} \approx F_{reg} \times 0.0587285\text{ Hz}$$

Skred accepts floating-point frequencies directly via `f#` (e.g. `f440.11`, `f2636.20`), ensuring pitch slides, detune, vibrato, and portamentos match original C64 hardware.

### 2. Pulse Width Modulation (PWM) via CZ Phase Distortion (`c1,#`)
The SID pulse wave features a 12-bit Pulse Width register ($0$ to $4095$), where $2048$ ($0\text{x}800$) represents a symmetrical 50% square wave.

Skred maps this to Casio CZ-style phase distortion (`c1,d`), where $d \in [-0.98, 0.98]$ dynamically shifts the waveform inflection point:

$$d = \frac{\text{PW} - 2048}{2048.0}$$

Combined with Skred's bandlimited square wave (`w16`), 12-bit PWM sweeps are reproduced with analog warmth and zero digital aliasing.

### 3. Band-Limited Analog Waveforms (`w15`, `w16`, `w18`, `w5`)
- **Sawtooth** $\rightarrow$ `w15`: Bandlimited Analog Sawtooth (32-harmonic DWGS core).
- **Square / Pulse** $\rightarrow$ `w16`: Bandlimited Analog Square with real-time `c1,d` phase-distortion PWM.
- **Triangle** $\rightarrow$ `w18`: Bandlimited Analog Triangle.
- **Noise** $\rightarrow$ `w5`: Pseudo-random tonal noise generator matching the low-frequency LFSR characteristics of the MOS 6581/8580.

### 4. ADSR Envelope Generators (`t`)
SID envelope timings map logarithmically to seconds:
- **Attack (0–15):** $2\text{ ms}$ to $8.0\text{ seconds}$.
- **Decay & Release (0–15):** $6\text{ ms}$ to $24.0\text{ seconds}$.
- **Sustain (0–15):** Normalized linear level from $0.0$ to $1.0$.

Emitted in Skode as: `t <attack>,<decay>,<sustain>,<release>` triggered via gate ON (`l1`) and released with gate OFF (`l0`).

### 5. Cross-Oscillator Ring Modulation (`XM`)
SID ring modulation maps directly to Skred's cross-voice modulation routing:
- Voice 1 modulated by Voice 3: `v0 XM 2`
- Voice 2 modulated by Voice 1: `v1 XM 0`
- Voice 3 modulated by Voice 2: `v2 XM 1`

### 6. Realtime Biquad Filter Automation (`j`, `k`, `q`)
The SID 11-bit Cutoff ($30\text{ Hz} - 12\text{ kHz}$) and 4-bit Resonance map to Skred's lowercase realtime filter automation:
- Mode: `j1` (Low-pass), `j2` (High-pass), `j3` (Band-pass), `j4` (Notch), `j0` (Bypass).
- Cutoff Frequency: `k <hz>` (e.g. `k1200` for 1.2 kHz).
- Resonance: `q <0.707 - 7.0>` (calibrated Q factor).

### 7. Calibrated Headroom & Authentic Mono Default
- **Calibrated Gain Staging:** Individual voice nominal levels are calibrated to `-8 dBFS` per voice (`a-8`), and master volume defaults to `V -8 dB`. This headroom ensures that multi-oscillator summing and resonant filter sweeps never clip or induce digital harshness.
- **Authentic Mono Default:** The Commodore 64 had a single RCA audio output. In `sid-to-skode`, the default stereo profile is centered **📻 Authentic Mono** (`p 0.0`), with optional switches for **🎧 Headphone (75%)** and **🔊 Wide (100%)**.

### 8. C64 PCM Digi Sample Extraction Magic (`w310+`, `/D`, `( ... ) /d`, `f440`)
In the golden age of Commodore 64 composition, composers like Chris Hülsbeck (*The Great Giana Sisters*), Jeroen Tel, and Martin Galway pioneered 4-bit sample playback ("digis") by streaming 4-bit nibbles directly into the SID master volume register ($D418) or via custom timer IRQ routines:
- **Direct 6502 Memory Extraction:** `siddump_wasm` monitors 6502 zero-page writes during emulation. When playroutines initialize sample pointers at `$04` and end pointers at `$02`, the extractor intercepts the address range, unpacks 4-bit nibbles from C64 RAM, DC-centers them around zero, and normalizes them into signed floating-point audio ($-1.0 \dots +1.0$).
- **Inline Self-Contained Wavetables:** Rather than requiring external sample files, extracted PCM data is compiled directly as inline Skode wavetable arrays `( <floats...> ) /d <slot>,<rate>` inside the script header, mapped to wavetable slots `w310`, `w311`, `w312`, etc. Skred automatically resizes sampler memory with `/D 4096`.
- **Unity Pitch Playback (`f440`):** In Skred's one-shot sampler core, phase increment is computed as $(g / 440.0) \times (\text{rate} / \text{samplerate})$. Triggering `v3 w<slot>,1,1 f440 l1` plays samples at their exact recorded frequency ($6842\text{ Hz}$).
- **Acoustic Volume Balancing:** During idle periods in digi tunes, register `$D418` rests at quiescent DC bias `7` (or `8`), which represents full nominal amplitude for synth voices. `sid-to-skode` maps this resting bias to $-8\text{ dBFS}$, balancing Voice 3 percussion hits with Voices 0–2 synth lines with zero overpowering jumps.
- **Dedicated Panning Automation:** Voice 3 includes its own real-time stereo pan slider (`v3 p#`), allowing drum samples to be centered or panned freely alongside synthetic leads and bass.

---

## Web Studio Features

### Featured Offline Demos: Hubbard & Hülsbeck
Two iconic C64 tracks are bundled locally for instant, zero-network offline demonstration:
- **Rob Hubbard – Commando:** Pure 3-voice SID synthesis masterpiece with lightning-fast arpeggios, PWM bass, and filtered noise percussion.
- **Chris Hülsbeck – The Great Giana Sisters:** The definitive demonstration of C64 4-bit PCM digi percussion (Kick `w310`, Snare `w311`, Hihat `w312`) synthesized and sequenced alongside classic analog SID voices.

### 100% Client-Side Public Archive Streaming (No Pre-Download Bloat)
Rather than pre-downloading and storing megabytes of dump text files in the repository, `sid-to-skode` pulls `.sid` files directly on demand over HTTP from public High Voltage SID Collection mirrors (via GitHub raw and jsDelivr CDN endpoints with global CORS support). Songs play for their natural duration without artificial 90-second caps.

### Live SID Register Activity Monitor & Delta Inspector
The **🎛️ SID Voices & Filter** tab features a live hardware register strip that reflects every MOS 6581/8580 register write in real time:
- `$D400-$D406`: Voice 1 (Frequency, Pulse Width, Waveform Control, ADSR).
- `$D407-$D40D`: Voice 2.
- `$D40E-$D414`: Voice 3.
- `$D415-$D418`: Filter Cutoff, Resonance, Voice Routing, and Mode/Volume.
- Live **$\Delta$ WRITE** badges and pulse highlights glow on the exact frame a hardware register changes, making chiptune sound design visible.
- Dedicated **Digi $04 PCM** block lights up whenever a drum sample trigger hits in the playroutine.

### Dedicated Digi Sample Voice Panning & Interactive Cards
When a digi-enabled tune is detected:
- **Dedicated Panning Slider:** A 4th slider (`Digi`) automatically appears in the stereo control toolbar, sending live `v3 p<pan>` commands to Skred.
- **PCM Digi Sample Card:** An interactive breakdown in the **ℹ️ Tune Info** tab details every captured wavetable (`w310`, `w311`, `w312`), sample lengths, sampling rates in Hz, playback duration in milliseconds, and total trigger counts throughout the song.

### Interactive Skred Terminal REPL (`Ctrl+~`)
Press `Ctrl+~` (or `Ctrl+\`` / `Escape` to close), or tap `>_ REPL` in the header:
- **Command Line History:** Navigate previous commands with `ArrowUp` and `ArrowDown`, persisted across browser sessions via `localStorage`.
- **WASM Live Capture:** Standard output and error diagnostics from the Skred engine stream straight to the console.
- **No Collision with Skode Atoms:** Meta-commands are safely prefixed with `-`:
  - `-help` / `-?`: Display full command cheat sheet.
  - `-clear` / `-cls`: Clear the console output.
  - `-panic`: Silences all voices immediately (`S-1; Y-1; stop`).
  - `-status`: View engine runtime health and history counts.
- **Quick Action Chips:** Tap one-click chips (`play`, `stop`, `v0 A440 ON`, `V -8`, `Lowpass 1.2k`).

### Mobile & Touch-Friendly Interface
Optimized for mobile platforms (iOS Safari, Android Chrome, tablets):
- Minimum 44px touch targets on all interactive controls.
- Responsive, flexible grid layout that automatically adjusts cards and metadata rows on narrow screens without horizontal clipping.
- Terminal REPL drawer responsive height (75vh on mobile) with 16px input font to prevent mobile browsers from unwanted auto-zooming.

### Direct DeepSID & HVSC Mirror Links
Whenever any featured classic or random online SID is loaded, direct links appear in the metadata bar:
- `🌐 DeepSID ↗`: Opens the tune directly in Chordian's DeepSID web player.
- `📥 .SID ↗`: Direct download of the original `.sid` file from the High Voltage SID Collection mirror.

### Clean Initial State & Shareable Deep Links (`?url=...`)
- **Clean Startup:** The web studio starts in a clean, quiet state with zero audio files auto-loaded on launch.
- **Deep Linking:** Launch directly into any public SID or DeepSID tune by appending `?url=...` to the URL:
  - DeepSID link: `https://octetta.github.io/sid-to-skode/?url=https://deepsid.chordian.net/?file=/MUSICIANS/W/Whittaker_David/Glider_Rider.sid`
  - HVSC path: `https://octetta.github.io/sid-to-skode/?url=/MUSICIANS/W/Whittaker_David/Glider_Rider.sid`
  - Featured title: `https://octetta.github.io/sid-to-skode/?url=commando`
- **Shareable URL Synchronization:** As you switch songs, the browser address bar dynamically syncs to `?url=...` for instant one-click sharing.

---

## Standalone CLI (`cli.gleam`)

Batch convert `.dump` files directly from your terminal:

```bash
# Convert a dump to a Skode script
node -e 'import("./build/dev/javascript/sid_to_skode/cli.mjs").then(m => m.main())' demos/commando.dump -o commando.sk
```

---

## Development, Continuous Deployment & GitHub Pages

### Quick Start
```bash
make help       # View all Makefile targets
make deps       # Download Gleam and npm dependencies
make check      # Verify Gleam types and compilation
make test       # Run Gleam unit test suite
make build      # Compile Gleam and bundle production web app into dist/
make dev        # Start Vite dev server on port 3000 and open in Firefox
make preview    # Preview production build on port 3000
```

### GitHub Pages Deployment
The web studio is automatically built and deployed to GitHub Pages at [octetta.github.io/sid-to-skode](https://octetta.github.io/sid-to-skode/) via GitHub Actions (`.github/workflows/deploy.yml`):
- Triggers on every push to `main` or manual `workflow_dispatch`.
- Verifies Gleam formatting, tests, and compilation.
- Builds the production bundle with Vite into `dist/`.
- Deploys with `coi-serviceworker.js` to enable cross-origin isolation (`SharedArrayBuffer`) seamlessly on GitHub Pages.

---

## Credits & Acknowledgements

`sid-to-skode` stands on the shoulders of the retro computing, demoscene, and functional programming communities:

- **Lasse Öörni** (loorni / Cadaver / Covert Bitops): Author of `siddump` (the 6502 CPU register analysis engine from which `siddump_wasm` was compiled) and legendary demoscene programmer.
- **Dag Lem**: Creator of `reSID`, the pioneering reverse-engineered MOS 6581/8580 software emulation library that made cycle-accurate SID analysis possible.
- **High Voltage SID Collection (HVSC) Maintainers**: The worldwide preservation crew behind [hvsc.c64.org](https://hvsc.c64.org), curating and archiving over 50,000 Commodore 64 music files since 1996.
- **Jens-Christian Huus** (Chordian): Creator of [DeepSID](https://deepsid.chordian.net), the definitive online C64 music listening experience.
- **Louis Pilfold** and the [Gleam](https://gleam.run/) community for designing a delightful, type-safe functional language that compiles to clean JavaScript.
- **Hayleigh Thompson** and the [Lustre](https://hexdocs.pm/lustre/) team for providing an elegant, robust Elm-architecture UI framework for Gleam.
- **The Commodore 64 Composer Legends**: Rob Hubbard, Martin Galway, Jeroen Tel, Chris Hülsbeck, Ben Daglish, Matt Gray, David Whittaker, Johannes Bjerregaard, Tim Follin, Fred Gray, Reyn Ouwehand, and all the composers who pushed a 3-voice chip to legendary heights.

---

## License

MIT License. Developed with love, reverence, and gratitude for functional audio programming and the 8-bit demoscene.
