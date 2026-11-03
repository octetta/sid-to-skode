//// # SID-to-Skode In-Browser Audio Converter & Synthesizer Web Studio
////
//// Runs client-side in the browser, converts Commodore 64 SID register dumps
//// into Skode 0.80.0 scripts, and allows instant playback directly in the Skred WASM audio engine.

import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lustre
import lustre/attribute.{class, href, id, rel, target, type_}
import lustre/effect.{type Effect}
import lustre/element.{type Element, text}
import lustre/element/html
import lustre/event
import sid_to_skode/converter
import sid_to_skode/dump_parser
import sid_to_skode/types.{
  type DumpSong, type FilterFrame, type Model, type Msg, type VoiceFrame,
  ConversionFailed, CopySkodeClicked, DownloadSkodeClicked, DumpTextReady,
  EngineStatusChanged, FileDropped, FilterFrame, LoadDemo, MasterVolumeChanged,
  Model, PanicClicked, PauseClicked, PlayClicked, PlaybackEnded,
  PlaybackStepChanged, RandomSidClicked, ResetClicked, ResumeClicked, SidFrame,
  StereoHeadphone, StereoModeChanged, StereoMono, StereoWide, StopClicked,
  TabSelected, VoiceFrame,
}

// ---------------------------------------------------------------------------
// JavaScript FFI Declarations
// ---------------------------------------------------------------------------

@external(javascript, "./skred_ffi.mjs", "initEngine")
fn js_init_engine(callback: fn(Bool) -> Nil) -> Nil

@external(javascript, "./skred_ffi.mjs", "registerFileDrop")
fn js_register_file_drop(callback: fn(String, String) -> Nil) -> Nil

@external(javascript, "./skred_ffi.mjs", "playSkode")
fn js_play_skode(script: String, steps: Int) -> Nil

@external(javascript, "./skred_ffi.mjs", "pausePlayback")
fn js_pause_playback() -> Nil

@external(javascript, "./skred_ffi.mjs", "resumePlayback")
fn js_resume_playback() -> Nil

@external(javascript, "./skred_ffi.mjs", "stopPlayback")
fn js_stop_playback() -> Nil

@external(javascript, "./skred_ffi.mjs", "panicEngine")
fn js_panic_engine() -> Nil

@external(javascript, "./skred_ffi.mjs", "setMasterVolume")
fn js_set_master_volume(db: Int) -> Nil

@external(javascript, "./skred_ffi.mjs", "sendCommand")
fn js_send_command(cmd: String) -> Nil

@external(javascript, "./skred_ffi.mjs", "registerPlaybackListener")
fn js_register_playback_listener(
  on_step: fn(Int, Int) -> Nil,
  on_end: fn() -> Nil,
) -> Nil

@external(javascript, "./skred_ffi.mjs", "loadDemoSid")
fn js_load_demo_sid(
  url: String,
  filename: String,
  title: String,
  author: String,
  on_success: fn(String, String, String, String) -> Nil,
  on_error: fn(String) -> Nil,
) -> Nil

@external(javascript, "./skred_ffi.mjs", "fetchRandomSid")
fn js_fetch_random_sid(
  on_success: fn(String, String, String, String) -> Nil,
  on_error: fn(String) -> Nil,
) -> Nil

@external(javascript, "./skred_ffi.mjs", "copyToClipboard")
fn js_copy_to_clipboard(content: String) -> Nil

@external(javascript, "./skred_ffi.mjs", "downloadFile")
fn js_download_file(filename: String, content: String) -> Nil

// ---------------------------------------------------------------------------
// Lustre Effects
// ---------------------------------------------------------------------------

fn init_engine_effect() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    js_init_engine(fn(success) { dispatch(EngineStatusChanged(success)) })
  })
}

fn register_file_drop_effect() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    js_register_file_drop(fn(filename, content) {
      dispatch(DumpTextReady(filename, content))
    })
  })
}

fn register_playback_listener_effect() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    js_register_playback_listener(
      fn(step, total) { dispatch(PlaybackStepChanged(step, total)) },
      fn() { dispatch(PlaybackEnded) },
    )
  })
}

fn play_effect(script: String, total_steps: Int) -> Effect(Msg) {
  effect.from(fn(_dispatch) { js_play_skode(script, total_steps) })
}

fn pause_effect() -> Effect(Msg) {
  effect.from(fn(_dispatch) { js_pause_playback() })
}

fn resume_effect() -> Effect(Msg) {
  effect.from(fn(_dispatch) { js_resume_playback() })
}

fn stop_effect() -> Effect(Msg) {
  effect.from(fn(_dispatch) { js_stop_playback() })
}

fn panic_effect() -> Effect(Msg) {
  effect.from(fn(_dispatch) { js_panic_engine() })
}

fn send_command_effect(cmd: String) -> Effect(Msg) {
  effect.from(fn(_dispatch) { js_send_command(cmd) })
}

fn set_master_volume_effect(db: Int) -> Effect(Msg) {
  effect.from(fn(_dispatch) { js_set_master_volume(db) })
}

fn copy_clipboard_effect(content: String) -> Effect(Msg) {
  effect.from(fn(_dispatch) { js_copy_to_clipboard(content) })
}

fn download_file_effect(filename: String, content: String) -> Effect(Msg) {
  effect.from(fn(_dispatch) { js_download_file(filename, content) })
}

fn load_demo_effect(
  url: String,
  filename: String,
  title: String,
  author: String,
) -> Effect(Msg) {
  effect.from(fn(dispatch) {
    js_load_demo_sid(
      url,
      filename,
      title,
      author,
      fn(name, content, _t, _a) { dispatch(DumpTextReady(name, content)) },
      fn(err) { dispatch(ConversionFailed(err)) },
    )
  })
}

fn random_sid_effect() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    js_fetch_random_sid(
      fn(name, content, _t, _a) { dispatch(DumpTextReady(name, content)) },
      fn(err) { dispatch(ConversionFailed(err)) },
    )
  })
}

// ---------------------------------------------------------------------------
// Model Initialization & Update
// ---------------------------------------------------------------------------

pub fn main() {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

pub fn init(_) -> #(Model, Effect(Msg)) {
  let model =
    Model(
      engine_ready: False,
      is_playing: False,
      is_paused: False,
      current_step: 0,
      active_song: None,
      conversion: None,
      is_converting: False,
      error_message: None,
      status_text: "Ready. Drag and drop any Commodore 64 .SID file or siddump output.",
      active_tab: "info",
      catalog_info: None,
      stereo_mode: StereoHeadphone,
      master_volume: -6,
      raw_dump_text: "",
    )

  let effects =
    effect.batch([
      init_engine_effect(),
      register_file_drop_effect(),
      register_playback_listener_effect(),
    ])

  #(model, effects)
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    EngineStatusChanged(ready) -> {
      let status = case ready {
        True -> "Skred 0.80.0 WASM engine ready."
        False -> "Failed to initialize Skred WASM audio engine."
      }
      #(Model(..model, engine_ready: ready, status_text: status), effect.none())
    }

    FileDropped(_filename, _data) -> {
      #(model, effect.none())
    }

    ConversionFailed(err) -> {
      #(
        Model(
          ..model,
          is_converting: False,
          error_message: Some(err),
          status_text: "SID conversion error: " <> err,
        ),
        stop_effect(),
      )
    }

    DumpTextReady(filename, content) -> {
      let stop_eff = case model.is_playing {
        True -> stop_effect()
        False -> effect.none()
      }
      case dump_parser.parse_dump(content, filename) {
        Error(err) -> {
          #(
            Model(
              ..model,
              is_converting: False,
              error_message: Some(err),
              status_text: "Dump parser error: " <> err,
            ),
            stop_eff,
          )
        }
        Ok(song) -> {
          case converter.convert_song(song, model.stereo_mode) {
            Error(err) -> {
              #(
                Model(
                  ..model,
                  is_converting: False,
                  active_song: Some(song),
                  error_message: Some(err),
                  status_text: "Conversion error: " <> err,
                ),
                stop_eff,
              )
            }
            Ok(conv) -> {
              let title = case string.trim(song.title) {
                "" -> filename
                t -> t
              }
              #(
                Model(
                  ..model,
                  is_converting: False,
                  active_song: Some(song),
                  conversion: Some(conv),
                  raw_dump_text: content,
                  is_playing: False,
                  is_paused: False,
                  current_step: 0,
                  error_message: None,
                  status_text: "Loaded \""
                    <> title
                    <> "\" by "
                    <> song.author
                    <> " ("
                    <> converter.format_duration(conv.duration_seconds)
                    <> ", "
                    <> int.to_string(song.frame_count)
                    <> " frames).",
                ),
                stop_eff,
              )
            }
          }
        }
      }
    }

    PlayClicked -> {
      case model.conversion {
        Some(conv) -> {
          #(
            Model(
              ..model,
              is_playing: True,
              is_paused: False,
              current_step: 0,
              status_text: "Playing in Skred WASM (50 Hz step clock)...",
            ),
            play_effect(conv.skode_text, conv.total_steps),
          )
        }
        None -> #(model, effect.none())
      }
    }

    PauseClicked -> {
      case model.is_playing {
        True -> #(
          Model(
            ..model,
            is_paused: True,
            status_text: "Playback paused at step "
              <> int.to_string(model.current_step + 1)
              <> ".",
          ),
          pause_effect(),
        )
        False -> #(model, effect.none())
      }
    }

    ResumeClicked -> {
      case model.is_playing {
        True -> #(
          Model(..model, is_paused: False, status_text: "Playback resumed."),
          resume_effect(),
        )
        False -> #(model, effect.none())
      }
    }

    StopClicked -> {
      #(
        Model(
          ..model,
          is_playing: False,
          is_paused: False,
          current_step: 0,
          status_text: "Playback stopped.",
        ),
        stop_effect(),
      )
    }

    PlaybackStepChanged(step, _total) -> {
      case model.is_playing {
        True -> #(Model(..model, current_step: step), effect.none())
        False -> #(model, effect.none())
      }
    }

    PlaybackEnded -> {
      #(
        Model(
          ..model,
          is_playing: False,
          is_paused: False,
          current_step: 0,
          status_text: "Playback finished.",
        ),
        effect.none(),
      )
    }

    PanicClicked -> {
      #(
        Model(
          ..model,
          is_playing: False,
          is_paused: False,
          current_step: 0,
          status_text: "Engine silenced (S-1).",
        ),
        panic_effect(),
      )
    }

    DownloadSkodeClicked -> {
      case model.conversion, model.active_song {
        Some(conv), Some(song) -> {
          let filename = clean_skode_filename(song.title)
          #(
            Model(..model, status_text: "Downloading " <> filename <> "..."),
            download_file_effect(filename, conv.skode_text),
          )
        }
        _, _ -> #(model, effect.none())
      }
    }

    CopySkodeClicked -> {
      case model.conversion {
        Some(conv) -> #(
          Model(..model, status_text: "Skode script copied to clipboard!"),
          copy_clipboard_effect(conv.skode_text),
        )
        None -> #(model, effect.none())
      }
    }

    ResetClicked -> {
      #(
        Model(
          ..model,
          active_song: None,
          conversion: None,
          is_playing: False,
          is_paused: False,
          current_step: 0,
          error_message: None,
          status_text: "Ready. Drag and drop any Commodore 64 .SID file or siddump output.",
          raw_dump_text: "",
        ),
        stop_effect(),
      )
    }

    TabSelected(tab) -> {
      #(Model(..model, active_tab: tab), effect.none())
    }

    LoadDemo(url, filename, title, author) -> {
      #(
        Model(
          ..model,
          is_playing: False,
          is_paused: False,
          current_step: 0,
          is_converting: True,
          status_text: "Loading demo "
            <> title
            <> " ("
            <> author
            <> ")...",
        ),
        effect.batch([
          stop_effect(),
          load_demo_effect(url, filename, title, author),
        ]),
      )
    }

    RandomSidClicked -> {
      #(
        Model(
          ..model,
          is_playing: False,
          is_paused: False,
          current_step: 0,
          is_converting: True,
          status_text: "Selecting random C64 SID tune...",
        ),
        effect.batch([stop_effect(), random_sid_effect()]),
      )
    }

    StereoModeChanged(new_mode) -> {
      let live_cmd = converter.build_live_stereo_command(new_mode)
      let mode_desc = case new_mode {
        StereoHeadphone -> "Stereo separation: 🎧 Headphone (75%)."
        StereoWide -> "Stereo separation: 🔊 Wide (100%)."
        StereoMono -> "Stereo separation: 📻 Mono (0%)."
      }
      let re_conv = case model.active_song {
        Some(song) -> {
          case converter.convert_song(song, new_mode) {
            Ok(c) -> Some(c)
            Error(_) -> model.conversion
          }
        }
        None -> model.conversion
      }
      #(
        Model(
          ..model,
          stereo_mode: new_mode,
          conversion: re_conv,
          status_text: mode_desc,
        ),
        send_command_effect(live_cmd),
      )
    }

    MasterVolumeChanged(vol) -> {
      let vol_str = case vol > 0 {
        True -> "+" <> int.to_string(vol)
        False -> int.to_string(vol)
      }
      #(
        Model(
          ..model,
          master_volume: vol,
          status_text: "Master volume: " <> vol_str <> " dB",
        ),
        set_master_volume_effect(vol),
      )
    }
  }
}

fn clean_skode_filename(title: String) -> String {
  let clean =
    string.replace(title, " ", "_")
    |> string.replace("/", "_")
    |> string.replace("\\", "_")
    |> string.lowercase
  case string.trim(clean) {
    "" -> "tune.sk"
    t -> t <> ".sk"
  }
}

// ---------------------------------------------------------------------------
// Lustre Views
// ---------------------------------------------------------------------------

pub fn view(model: Model) -> Element(Msg) {
  html.div([class("app-shell")], [
    view_header(model),
    html.main([class("main-content")], [
      case model.active_song {
        None -> view_drop_zone(model)
        Some(song) -> view_dashboard(model, song)
      },
    ]),
    view_footer(model),
  ])
}

fn view_header(model: Model) -> Element(Msg) {
  html.header([class("app-header")], [
    html.div([class("brand")], [
      html.h1([], [text("SID TO SKODE")]),
      html.span([class("badge-version")], [text("v0.1.0")]),
      html.span([class("badge-engine")], [text("Skred v0.80.0")]),
    ]),
    html.div([class("header-controls")], [
      html.div([class("engine-status")], [
        html.span(
          [
            class(case model.engine_ready {
              True -> "status-dot status-ready"
              False -> "status-dot status-loading"
            }),
          ],
          [],
        ),
        html.span([class("status-label")], [
          text(case model.engine_ready {
            True -> "Audio Engine Ready"
            False -> "Loading WASM..."
          }),
        ]),
      ]),
      html.button(
        [class("btn btn-danger btn-sm"), event.on_click(PanicClicked)],
        [text("PANIC")],
      ),
    ]),
  ])
}

pub type DemoTune {
  DemoTune(icon: String, title: String, author: String, filename: String)
}

const featured_demos: List(DemoTune) = [
  DemoTune("🎖️", "Commando", "Rob Hubbard", "commando.sid"),
  DemoTune("🏃", "Monty on the Run", "Rob Hubbard", "monty_on_the_run.sid"),
  DemoTune("🚀", "Sanxion", "Rob Hubbard", "sanxion.sid"),
  DemoTune("🔺", "Delta", "Rob Hubbard", "delta.sid"),
  DemoTune("🥋", "Int. Karate", "Rob Hubbard", "international_karate.sid"),
  DemoTune("🍰", "Comic Bakery", "Martin Galway", "comic_bakery.sid"),
  DemoTune("🧱", "Arkanoid", "Martin Galway", "arkanoid.sid"),
  DemoTune("🔮", "Wizball", "Martin Galway", "wizball.sid"),
  DemoTune("🤖", "Cybernoid", "Jeroen Tel", "cybernoid.sid"),
  DemoTune("🍄", "Giana Sisters", "Chris Hülsbeck", "great_giana_sisters.sid"),
  DemoTune("🥷", "Last Ninja 2", "Matt Gray", "last_ninja_2.sid"),
]

fn view_drop_zone(model: Model) -> Element(Msg) {
  html.div([class("welcome-container")], [
    html.div([class("drop-box"), id("drop-zone")], [
      html.div([class("drop-icon")], [text("🎛️")]),
      html.h2([class("drop-title")], [
        text("Drop your Commodore 64 .SID file or siddump output here"),
      ]),
      html.p([class("drop-subtitle")], [
        text(
          "MOS 6581 / 8580 SID chiptune conversion. Synthesizes real Skred waveforms (w1 pulse, w3 saw, w4 triangle, w5 noise), CZ phase-distortion PWM (c1,#), hardware ADSR envelopes, ring modulation (XM) & realtime biquad filters.",
        ),
      ]),
      html.div([class("file-select-wrapper")], [
        html.label([class("btn btn-primary btn-lg")], [
          text("Select .SID / .DUMP File"),
          html.input([
            type_("file"),
            id("file-input"),
            attribute.accept([".sid", ".SID", ".dump", ".txt"]),
            class("hidden-file-input"),
          ]),
        ]),
      ]),
      html.div([class("demo-section")], [
        html.span([class("demo-label")], [
          text("Or try an instant demo SID tune:"),
        ]),
        html.div(
          [class("demo-buttons")],
          list.append(
            list.map(featured_demos, fn(demo) {
              let url = "demos/" <> demo.filename
              html.button(
                [
                  class("btn btn-secondary btn-sm"),
                  event.on_click(LoadDemo(url, demo.filename, demo.title, demo.author)),
                  attribute.disabled(model.is_converting),
                ],
                [text(demo.icon <> " " <> demo.title <> " (" <> demo.author <> ")")],
              )
            }),
            [
              html.button(
                [
                  class("btn btn-modarchive btn-sm"),
                  event.on_click(RandomSidClicked),
                  attribute.disabled(model.is_converting),
                ],
                [text("🎲 Random SID Tune (17 Classics)")],
              ),
            ],
          ),
        ),
      ]),
    ]),
    html.div([class("public-sources-card")], [
      html.div([class("sources-header")], [
        html.h3([class("sources-title")], [
          text("Need Commodore 64 SID files to convert?"),
        ]),
        html.p([class("sources-subtitle")], [
          text(
            "Explore thousands of legendary Commodore 64 soundtracks from these public archives:",
          ),
        ]),
      ]),
      html.div([class("sources-grid")], [
        html.a(
          [
            class("source-card"),
            href("https://deepsid.chordian.net/"),
            target("_blank"),
            rel("noopener noreferrer"),
          ],
          [
            html.div([class("source-badge")], [text("Web Player & DB")]),
            html.h4([class("source-name")], [text("DeepSID ↗")]),
            html.p([class("source-desc")], [
              text(
                "Modern online player for the High Voltage SID Collection with search, ratings, and composer profiles.",
              ),
            ]),
          ],
        ),
        html.a(
          [
            class("source-card"),
            href("https://hvsc.c64.org/"),
            target("_blank"),
            rel("noopener noreferrer"),
          ],
          [
            html.div([class("source-badge")], [text("Official Archive")]),
            html.h4([class("source-name")], [
              text("High Voltage SID Collection (HVSC) ↗"),
            ]),
            html.p([class("source-desc")], [
              text(
                "The definitive repository of Commodore 64 music containing over 55,000 SID files.",
              ),
            ]),
          ],
        ),
        html.a(
          [
            class("source-card"),
            href("http://www.c64music.co.uk/"),
            target("_blank"),
            rel("noopener noreferrer"),
          ],
          [
            html.div([class("source-badge")], [text("Historic Collection")]),
            html.h4([class("source-name")], [text("Compute's Gazette SID ↗")]),
            html.p([class("source-desc")], [
              text(
                "Historical collection of Commodore 64 tunes published in Compute's Gazette magazine.",
              ),
            ]),
          ],
        ),
      ]),
    ]),
    html.div([class("developer-embed-card")], [
      html.div([class("developer-card-header")], [
        html.div([class("developer-badge")], [text("SYNTHESIS REFERENCE")]),
        html.h3([class("developer-title")], [
          text("Skred Synthesizer SID Waveform & Filter Mapping"),
        ]),
        html.p([class("developer-subtitle")], [
          text(
            "Every converted SID frame maps directly to Skred 0.80.0 synthesis opcodes:",
          ),
        ]),
      ]),
      html.pre([class("developer-code-preview")], [
        html.code([], [
          text(
            "# 1. Bandlimited Analog Waves:\nw15 -> Bandlimited Sawtooth (SID Saw)\nw16 -> Bandlimited Square (SID Pulse)\nw18 -> Bandlimited Triangle (SID Tri)\nw6  -> Knuth MMIX LCG White Noise (SID Noise)\n\n# 2. CZ Phase-Distortion PWM:\nc1,-0.5 -> Narrow Pulse (25% Duty)\nc1,0.0  -> Square Wave (50% Duty)\nc1,0.5  -> Wide Pulse (75% Duty)\n\n# 3. Dynamic Biquad Filtering:\nJ1 K1200 Q1.5 -> Resonant Low-Pass at 1.2 kHz\nJ2 K400  Q0.7 -> High-Pass at 400 Hz\nJ3 K800  Q3.0 -> Band-Pass centered at 800 Hz",
          ),
        ]),
      ]),
    ]),
    html.div([class("features-grid")], [
      feature_card(
        "⚡ 100% In-Browser",
        "Runs 6502 machine code in-browser via WebAssembly to generate register dumps in milliseconds with zero server upload.",
      ),
      feature_card(
        "🎛️ Exact Timing & Delta Compression",
        "M 125 96 locks sequencer to 50.0 Hz PAL frame rate. Steps only emit changed parameters for maximum efficiency.",
      ),
      feature_card(
        "📦 Clean Skode Script",
        "Produces authentic Skode 0.80.0 scripts ready for instant playback in Skred WASM or download for CLI usage.",
      ),
    ]),
    html.div([class("welcome-author-bar")], [
      html.span([], [
        text("Created by "),
        html.a(
          [
            class("author-inline-link"),
            href("https://josephestewart.com"),
            target("_blank"),
            rel("noopener noreferrer"),
          ],
          [text("Joseph Stewart (CV)")],
        ),
        text(" · "),
        html.a(
          [
            class("author-inline-link"),
            href("https://www.youtube.com/@octetta"),
            target("_blank"),
            rel("noopener noreferrer"),
          ],
          [text("YouTube (@octetta) ↗")],
        ),
        text(" · Made with ❤️ in "),
        html.a(
          [
            class("author-inline-link gleam-inline"),
            href("https://gleam.run"),
            target("_blank"),
            rel("noopener noreferrer"),
          ],
          [text("Gleam")],
        ),
        text(" & "),
        html.a(
          [
            class("author-inline-link lustre-inline"),
            href("https://lustre.build"),
            target("_blank"),
            rel("noopener noreferrer"),
          ],
          [text("Lustre")],
        ),
      ]),
    ]),
  ])
}

fn feature_card(title: String, desc: String) -> Element(Msg) {
  html.div([class("feature-card")], [
    html.h3([], [text(title)]),
    html.p([], [text(desc)]),
  ])
}

fn view_dashboard(model: Model, song: DumpSong) -> Element(Msg) {
  html.div([class("dashboard-container")], [
    view_transport_bar(model, song),
    view_metadata_bar(model, song),
    view_tabs_navigation(model),
    view_tab_content(model, song),
  ])
}

fn view_transport_bar(model: Model, _song: DumpSong) -> Element(Msg) {
  let play_pause_btn = case model.is_playing {
    False ->
      html.button(
        [
          class("btn btn-success btn-lg"),
          event.on_click(PlayClicked),
          attribute.disabled(model.conversion == None),
        ],
        [text("▶ Play in Skred")],
      )
    True -> {
      case model.is_paused {
        False ->
          html.button(
            [class("btn btn-warning btn-lg"), event.on_click(PauseClicked)],
            [text("⏸ Pause")],
          )
        True ->
          html.button(
            [
              class("btn btn-success btn-lg pulse-paused"),
              event.on_click(ResumeClicked),
            ],
            [text("▶ Resume")],
          )
      }
    }
  }

  let stop_btn = case model.is_playing {
    True ->
      html.button(
        [class("btn btn-danger btn-lg"), event.on_click(StopClicked)],
        [text("⏹ Stop")],
      )
    False ->
      html.button(
        [class("btn btn-secondary btn-lg"), attribute.disabled(True)],
        [text("⏹ Stop")],
      )
  }

  let progress_section = case model.conversion {
    Some(conv) -> {
      let total_rows = conv.total_steps
      let cur_step = case model.is_playing {
        True -> int.min(model.current_step, total_rows - 1)
        False -> 0
      }
      let elapsed_sec = case model.is_playing {
        True -> {
          case dict.get(conv.step_times, cur_step) {
            Ok(t) -> t
            Error(_) -> conv.duration_seconds
          }
        }
        False -> 0.0
      }
      let pct = case conv.duration_seconds >. 0.0 && model.is_playing {
        True -> {
          float.min(
            100.0,
            float.max(0.0, elapsed_sec /. conv.duration_seconds *. 100.0),
          )
        }
        False -> 0.0
      }

      let status_badge = case model.is_playing {
        False ->
          html.span([class("playback-status-badge badge-stopped")], [
            text("STOPPED"),
          ])
        True ->
          case model.is_paused {
            True ->
              html.span([class("playback-status-badge badge-paused")], [
                text("PAUSED"),
              ])
            False ->
              html.span([class("playback-status-badge badge-playing")], [
                text("PLAYING"),
              ])
          }
      }

      html.div([class("playback-tracker")], [
        html.div([class("playback-info-row")], [
          html.div([class("step-counter")], [
            status_badge,
            html.span([class("step-numbers")], [
              text(
                "Step "
                <> case model.is_playing {
                  True -> int.to_string(cur_step + 1)
                  False -> "0"
                }
                <> " / "
                <> int.to_string(total_rows),
              ),
            ]),
          ]),
          html.div([class("time-counter")], [
            text(
              converter.format_duration(elapsed_sec)
              <> " / "
              <> converter.format_duration(conv.duration_seconds),
            ),
          ]),
        ]),
        html.div([class("playback-progress-track")], [
          html.div(
            [
              class(case model.is_playing && !model.is_paused {
                True -> "playback-progress-fill is-active"
                False -> "playback-progress-fill"
              }),
              attribute.style("width", converter.format_float(pct, 1) <> "%"),
            ],
            [],
          ),
        ]),
      ])
    }
    None -> html.div([], [])
  }

  html.div([class("transport-container")], [
    html.div([class("transport-bar")], [
      html.div([class("transport-buttons")], [
        play_pause_btn,
        stop_btn,
        html.button(
          [
            class("btn btn-primary btn-lg"),
            event.on_click(DownloadSkodeClicked),
            attribute.disabled(model.conversion == None),
          ],
          [text("💾 Download .SK")],
        ),
        html.button(
          [
            class("btn btn-modarchive btn-lg"),
            event.on_click(RandomSidClicked),
            attribute.disabled(model.is_converting),
          ],
          [text("🎲 Random SID")],
        ),
        html.button(
          [class("btn btn-secondary btn-lg"), event.on_click(ResetClicked)],
          [text("⟲ New File")],
        ),
      ]),
      html.div([class("transport-controls-right")], [
        view_volume_slider(model),
        view_stereo_selector(model),
      ]),
    ]),
    progress_section,
  ])
}

fn view_volume_slider(model: Model) -> Element(Msg) {
  let vol_icon = case model.master_volume {
    v if v <= -30 -> "🔈"
    v if v <= -12 -> "🔉"
    _ -> "🔊"
  }
  let vol_str = case model.master_volume > 0 {
    True -> "+" <> int.to_string(model.master_volume) <> " dB"
    False -> int.to_string(model.master_volume) <> " dB"
  }

  html.div([class("volume-control-group")], [
    html.span([class("volume-icon")], [text(vol_icon)]),
    html.span([class("volume-label")], [text("VOL")]),
    html.input([
      type_("range"),
      attribute.min("-40"),
      attribute.max("6"),
      attribute.step("1"),
      attribute.value(int.to_string(model.master_volume)),
      attribute.title("Master volume (" <> vol_str <> ") - Skode V command"),
      class("volume-slider"),
      event.on_input(fn(val_str) {
        case int.parse(val_str) {
          Ok(v) -> MasterVolumeChanged(v)
          Error(_) -> MasterVolumeChanged(-6)
        }
      }),
    ]),
    html.span([class("volume-value-badge")], [text(vol_str)]),
  ])
}

fn view_stereo_selector(model: Model) -> Element(Msg) {
  html.div([class("stereo-control-group")], [
    html.span([class("stereo-label")], [text("STEREO")]),
    html.div([class("segmented-control")], [
      html.button(
        [
          class(case model.stereo_mode {
            StereoHeadphone -> "segment-btn active"
            _ -> "segment-btn"
          }),
          event.on_click(StereoModeChanged(StereoHeadphone)),
          attribute.title(
            "Headphone separation (75%) - Prevents ear fatigue on headphones/earbuds",
          ),
        ],
        [text("🎧 75%")],
      ),
      html.button(
        [
          class(case model.stereo_mode {
            StereoWide -> "segment-btn active"
            _ -> "segment-btn"
          }),
          event.on_click(StereoModeChanged(StereoWide)),
          attribute.title("Wide separation (100% L-R-C)"),
        ],
        [text("🔊 Wide 100%")],
      ),
      html.button(
        [
          class(case model.stereo_mode {
            StereoMono -> "segment-btn active"
            _ -> "segment-btn"
          }),
          event.on_click(StereoModeChanged(StereoMono)),
          attribute.title("Mono (0%) - Centers all 3 voices"),
        ],
        [text("📻 Mono")],
      ),
    ]),
  ])
}

fn view_metadata_bar(model: Model, song: DumpSong) -> Element(Msg) {
  let clean_title = case string.trim(song.title) {
    "" -> "(Untitled)"
    t -> t
  }
  let clean_author = case string.trim(song.author) {
    "" -> "Unknown"
    a -> a
  }
  let duration_str = case model.conversion {
    Some(conv) -> converter.format_duration(conv.duration_seconds)
    None -> "--:--"
  }

  html.div([class("metadata-bar")], [
    html.div([class("meta-item meta-title-item")], [
      html.span([class("meta-label")], [text("TITLE")]),
      html.span([class("meta-val highlight-title")], [text(clean_title)]),
    ]),
    html.div([class("meta-item")], [
      html.span([class("meta-label")], [text("AUTHOR")]),
      html.span([class("meta-val")], [text(clean_author)]),
    ]),
    html.div([class("meta-item")], [
      html.span([class("meta-label")], [text("CLOCK")]),
      html.span([class("meta-val mono")], [text("50.0 Hz (PAL C64)")]),
    ]),
    html.div([class("meta-item")], [
      html.span([class("meta-label")], [text("FRAMES")]),
      html.span([class("meta-val mono")], [
        text(int.to_string(song.frame_count)),
      ]),
    ]),
    html.div([class("meta-item")], [
      html.span([class("meta-label")], [text("DURATION")]),
      html.span([class("meta-val mono")], [text(duration_str)]),
    ]),
  ])
}

fn view_tabs_navigation(model: Model) -> Element(Msg) {
  html.nav([class("tabs-nav")], [
    html.button(
      [
        class(case model.active_tab {
          "info" -> "tab-btn active"
          _ -> "tab-btn"
        }),
        event.on_click(TabSelected("info")),
      ],
      [text("ℹ️ Tune Info")],
    ),
    html.button(
      [
        class(case model.active_tab {
          "voices" -> "tab-btn active"
          _ -> "tab-btn"
        }),
        event.on_click(TabSelected("voices")),
      ],
      [text("🎛️ SID Voices & Filter")],
    ),
    html.button(
      [
        class(case model.active_tab {
          "skode" -> "tab-btn active"
          _ -> "tab-btn"
        }),
        event.on_click(TabSelected("skode")),
      ],
      [text("📜 Skode Script (.sk)")],
    ),
    html.button(
      [
        class(case model.active_tab {
          "dump" -> "tab-btn active"
          _ -> "tab-btn"
        }),
        event.on_click(TabSelected("dump")),
      ],
      [text("📑 Raw SID Dump")],
    ),
  ])
}

fn view_tab_content(model: Model, song: DumpSong) -> Element(Msg) {
  html.div([class("tab-content-panel")], [
    case model.active_tab {
      "info" -> view_tab_info(model, song)
      "voices" -> view_tab_voices(model, song)
      "skode" -> view_tab_skode(model)
      "dump" -> view_tab_dump(model)
      _ -> view_tab_info(model, song)
    },
  ])
}

fn view_tab_info(_model: Model, song: DumpSong) -> Element(Msg) {
  html.div([class("info-tab-layout")], [
    html.div([class("song-info-card")], [
      html.h3([class("card-title")], [text("Commodore 64 Sound Details")]),
      html.div([class("info-grid")], [
        info_row("Title", song.title),
        info_row("Author", song.author),
        info_row("Released / Copyright", song.copyright),
        info_row("Frame Rate", "50.0 Hz (PAL, 20.0 ms per step)"),
        info_row("Total Frames", int.to_string(song.frame_count)),
        info_row(
          "Master Tempo",
          "M 125 96  (125 * 96 / 240 = 50.0 Hz step frequency)",
        ),
      ]),
    ]),
    html.div([class("song-info-card")], [
      html.h3([class("card-title")], [text("MOS SID Synthesis Architecture")]),
      html.p([class("card-body-text")], [
        text(
          "The Commodore 64 SID chip (MOS 6581/8580) features 3 independent hardware voices, each with programmable waveforms, pulse-width modulation, resonant multimode filtering, and ADSR envelope generators. sid-to-skode unrolls and delta-compresses each frame directly into 4 parallel Skode patterns (y0, y1, y2 for voices, y3 for filter automation) driving Skred's bandlimited analog oscillators.",
        ),
      ]),
    ]),
  ])
}

fn info_row(label: String, val: String) -> Element(Msg) {
  html.div([class("info-row")], [
    html.span([class("info-key")], [text(label)]),
    html.span([class("info-val")], [text(val)]),
  ])
}

fn view_tab_voices(model: Model, song: DumpSong) -> Element(Msg) {
  let step_idx = case model.is_playing {
    True -> int.min(model.current_step, song.frame_count - 1)
    False -> 0
  }

  let frame = case list.drop(song.frames, step_idx) {
    [f, ..] -> f
    [] ->
      SidFrame(
        step_idx,
        default_voice_frame(),
        default_voice_frame(),
        default_voice_frame(),
        default_filter_frame(),
      )
  }

  html.div([class("voices-tab-layout")], [
    html.div([class("voices-grid")], [
      view_voice_channel_card(0, "Voice 1", frame.v1),
      view_voice_channel_card(1, "Voice 2", frame.v2),
      view_voice_channel_card(2, "Voice 3", frame.v3),
    ]),
    view_filter_card(frame.filter),
  ])
}

fn default_voice_frame() -> VoiceFrame {
  VoiceFrame(
    freq: 0,
    note_name: "---",
    semitone: 0,
    waveform_byte: 0,
    gate: False,
    sync: False,
    ring_mod: False,
    test_bit: False,
    adsr: 0,
    attack: 0,
    decay: 0,
    sustain: 0,
    release: 0,
    pulse_width: 2048,
    freq_changed: False,
    wave_changed: False,
    adsr_changed: False,
    pulse_changed: False,
  )
}

fn default_filter_frame() -> FilterFrame {
  FilterFrame(
    cutoff: 0,
    res_routing: 0,
    resonance: 0,
    route_v1: False,
    route_v2: False,
    route_v3: False,
    route_ext: False,
    mode_str: "Off",
    volume: 15,
    cutoff_changed: False,
    ctrl_changed: False,
    mode_changed: False,
    vol_changed: False,
  )
}

fn view_voice_channel_card(
  c: Int,
  label: String,
  vf: VoiceFrame,
) -> Element(Msg) {
  let hz = converter.freq_to_hz(vf.freq)
  let hz_str = converter.format_float(hz, 1) <> " Hz"
  let wave_desc = case vf.waveform_byte {
    b if b >= 128 -> "Noise (w6 Knuth LCG)"
    b if b >= 64 -> "Square/PWM (w16)"
    b if b >= 32 -> "Sawtooth (w15)"
    b if b >= 16 -> "Triangle (w18)"
    _ -> "Rest / Off"
  }
  let duty_pct =
    converter.format_float(int.to_float(vf.pulse_width) /. 40.95, 1) <> "%"

  html.div([class("voice-card")], [
    html.div([class("voice-card-header")], [
      html.h4([class("voice-title")], [text(label)]),
      html.span(
        [
          class(case vf.gate {
            True -> "gate-badge gate-on"
            False -> "gate-badge gate-off"
          }),
        ],
        [
          text(case vf.gate {
            True -> "GATE ON"
            False -> "GATE OFF"
          }),
        ],
      ),
    ]),
    html.div([class("voice-specs-grid")], [
      spec_item("Note / Freq", vf.note_name <> " (" <> hz_str <> ")"),
      spec_item("Waveform", wave_desc),
      spec_item("Pulse Width", duty_pct),
      spec_item(
        "ADSR (sec)",
        int.to_string(vf.attack)
          <> " / "
          <> int.to_string(vf.decay)
          <> " / "
          <> int.to_string(vf.sustain)
          <> " / "
          <> int.to_string(vf.release),
      ),
      spec_item("Modulation", case vf.ring_mod, vf.sync {
        True, True -> "RingMod + HardSync"
        True, False -> "RingMod active"
        False, True -> "HardSync active"
        False, False -> "None"
      }),
      spec_item(
        "Track / Voice",
        "y" <> int.to_string(c) <> " -> v" <> int.to_string(c),
      ),
    ]),
  ])
}

fn spec_item(label: String, val: String) -> Element(Msg) {
  html.div([class("spec-item")], [
    html.span([class("spec-label")], [text(label)]),
    html.span([class("spec-val mono")], [text(val)]),
  ])
}

fn view_filter_card(ff: FilterFrame) -> Element(Msg) {
  let cutoff_hz = converter.cutoff_to_hz(ff.cutoff)
  let q_res = converter.res_to_q(ff.resonance)

  html.div([class("filter-card")], [
    html.div([class("filter-header")], [
      html.h4([class("filter-title")], [
        text("Biquad Filter & Routing (Track 3)"),
      ]),
      html.span([class("badge-engine")], [text("Mode: " <> ff.mode_str)]),
    ]),
    html.div([class("filter-specs-grid")], [
      spec_item(
        "Cutoff Frequency",
        converter.format_float(cutoff_hz, 1) <> " Hz",
      ),
      spec_item("Resonance (Q)", converter.format_float(q_res, 2)),
      spec_item("Routed Voices", case ff.route_v1, ff.route_v2, ff.route_v3 {
        True, True, True -> "Voice 1, Voice 2, Voice 3"
        True, True, False -> "Voice 1, Voice 2"
        True, False, False -> "Voice 1"
        False, True, False -> "Voice 2"
        False, False, True -> "Voice 3"
        _, _, _ -> "None (Bypassed)"
      }),
      spec_item("Master Volume", int.to_string(ff.volume) <> " / 15"),
    ]),
  ])
}

fn view_tab_skode(model: Model) -> Element(Msg) {
  case model.conversion {
    Some(conv) -> {
      html.div([class("skode-viewer-card")], [
        html.div([class("viewer-action-bar")], [
          html.span([class("viewer-filename")], [text("main.sk")]),
          html.div([class("viewer-buttons")], [
            html.button(
              [
                class("btn btn-secondary btn-sm"),
                event.on_click(CopySkodeClicked),
              ],
              [text("📋 Copy Script")],
            ),
            html.button(
              [
                class("btn btn-primary btn-sm"),
                event.on_click(DownloadSkodeClicked),
              ],
              [text("💾 Download .SK")],
            ),
          ]),
        ]),
        html.pre([class("code-preview-block")], [
          html.code([], [text(conv.skode_text)]),
        ]),
      ])
    }
    None ->
      html.div([class("empty-panel-text")], [
        text("No Skode script converted yet."),
      ])
  }
}

fn view_tab_dump(model: Model) -> Element(Msg) {
  html.div([class("skode-viewer-card")], [
    html.div([class("viewer-action-bar")], [
      html.span([class("viewer-filename")], [text("siddump.txt")]),
    ]),
    html.pre([class("code-preview-block")], [
      html.code([], [text(model.raw_dump_text)]),
    ]),
  ])
}

fn view_footer(model: Model) -> Element(Msg) {
  html.footer([class("app-footer")], [
    html.div([class("footer-status")], [
      html.span([class("footer-bullet")], [text("●")]),
      html.span([class("footer-text")], [text(model.status_text)]),
    ]),
  ])
}
