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
import lustre/attribute.{class, href, id, rel, target, title, type_}
import lustre/effect.{type Effect}
import lustre/element.{type Element, none, text}
import lustre/element/html
import lustre/event
import sid_to_skode/converter
import sid_to_skode/dump_parser
import sid_to_skode/types.{
  type DumpSong, type FilterFrame, type Model, type Msg, type SidFrame,
  type VoiceFrame, ConversionFailed, CopySkodeClicked, DownloadSkodeClicked,
  DumpTextReady, EngineStatusChanged, FileDropped, FilterFrame, LoadDemo,
  MasterVolumeChanged, Model, PanicClicked, PauseClicked, PlayClicked,
  PlaybackEnded, PlaybackStepChanged, RandomSidClicked, ResetClicked,
  ResumeClicked, SidFrame, StereoHeadphone, StereoModeChanged, StereoMono,
  StereoWide, StopClicked, TabSelected, ToggleReplClicked, VoiceFrame,
}

// ---------------------------------------------------------------------------
// JavaScript FFI Declarations
// ---------------------------------------------------------------------------

@external(javascript, "./skred_ffi.mjs", "initEngine")
fn js_init_engine(callback: fn(Bool) -> Nil) -> Nil

@external(javascript, "./skred_ffi.mjs", "registerFileDrop")
fn js_register_file_drop(
  callback: fn(String, String, String, String) -> Nil,
) -> Nil

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

@external(javascript, "./skred_ffi.mjs", "toggleRepl")
fn js_toggle_repl() -> Nil

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
  on_success: fn(String, String, String, String, String, String) -> Nil,
  on_error: fn(String) -> Nil,
) -> Nil

@external(javascript, "./skred_ffi.mjs", "fetchRandomSid")
fn js_fetch_random_sid(
  on_success: fn(String, String, String, String, String, String) -> Nil,
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
    js_register_file_drop(fn(filename, content, source_desc, hvsc_path) {
      dispatch(DumpTextReady(filename, content, source_desc, hvsc_path))
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

fn toggle_repl_effect() -> Effect(Msg) {
  effect.from(fn(_dispatch) { js_toggle_repl() })
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
      fn(name, content, _t, _a, src, path) {
        dispatch(DumpTextReady(name, content, src, path))
      },
      fn(err) { dispatch(ConversionFailed(err)) },
    )
  })
}

fn random_sid_effect() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    js_fetch_random_sid(
      fn(name, content, _t, _a, src, path) {
        dispatch(DumpTextReady(name, content, src, path))
      },
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
      stereo_mode: StereoMono,
      master_volume: -8,
      raw_dump_text: "",
      source_description: "",
      hvsc_path: None,
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

    DumpTextReady(filename, content, source_desc, hvsc_path_str) -> {
      let stop_eff = case model.is_playing {
        True -> stop_effect()
        False -> effect.none()
      }
      let opt_hvsc = case string.trim(hvsc_path_str) {
        "" -> None
        p -> Some(p)
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
                  source_description: source_desc,
                  hvsc_path: opt_hvsc,
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
                    <> " frames) from "
                    <> source_desc
                    <> ".",
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
          source_description: "",
          hvsc_path: None,
        ),
        stop_effect(),
      )
    }

    ToggleReplClicked -> {
      #(model, toggle_repl_effect())
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
          status_text: "🌐 Fetching "
            <> title
            <> " ("
            <> author
            <> ") from HVSC archive...",
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
          status_text: "🌐 Fetching random SID tune online from HVSC archive (https://hvsc.c64.org)...",
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
      #(
        Model(..model, stereo_mode: new_mode, status_text: mode_desc),
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
      html.span([class("badge-analog")], [
        text("⚡ Analog Waves: w15 / w16 / w18"),
      ]),
      html.span([class("badge-stereo")], [text("📻 Authentic Mono")]),
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
        [
          class("btn btn-terminal btn-sm"),
          event.on_click(ToggleReplClicked),
          title("Toggle Skred Interactive REPL (Ctrl+~)"),
        ],
        [text(">_ REPL (Ctrl+~)")],
      ),
      html.button(
        [class("btn btn-danger btn-sm"), event.on_click(PanicClicked)],
        [text("PANIC")],
      ),
    ]),
  ])
}

pub type DemoTune {
  DemoTune(
    icon: String,
    title: String,
    author: String,
    filename: String,
    path: String,
  )
}

const featured_demos: List(DemoTune) = [
  DemoTune(
    "🎖️",
    "Commando",
    "Rob Hubbard",
    "commando.sid",
    "MUSICIANS/H/Hubbard_Rob/Commando.sid",
  ),
  DemoTune(
    "🏃",
    "Monty on the Run",
    "Rob Hubbard",
    "monty_on_the_run.sid",
    "MUSICIANS/H/Hubbard_Rob/Monty_on_the_Run.sid",
  ),
  DemoTune(
    "🚀",
    "Sanxion",
    "Rob Hubbard",
    "sanxion.sid",
    "MUSICIANS/H/Hubbard_Rob/Sanxion.sid",
  ),
  DemoTune(
    "🔺",
    "Delta",
    "Rob Hubbard",
    "delta.sid",
    "MUSICIANS/H/Hubbard_Rob/Delta.sid",
  ),
  DemoTune(
    "🥋",
    "Int. Karate",
    "Rob Hubbard",
    "international_karate.sid",
    "MUSICIANS/H/Hubbard_Rob/International_Karate.sid",
  ),
  DemoTune(
    "🍰",
    "Comic Bakery",
    "Martin Galway",
    "comic_bakery.sid",
    "MUSICIANS/G/Galway_Martin/Comic_Bakery.sid",
  ),
  DemoTune(
    "🧱",
    "Arkanoid",
    "Martin Galway",
    "arkanoid.sid",
    "MUSICIANS/G/Galway_Martin/Arkanoid.sid",
  ),
  DemoTune(
    "🔮",
    "Wizball",
    "Martin Galway",
    "wizball.sid",
    "MUSICIANS/G/Galway_Martin/Wizball.sid",
  ),
  DemoTune(
    "🤖",
    "Cybernoid",
    "Jeroen Tel",
    "cybernoid.sid",
    "MUSICIANS/T/Tel_Jeroen/Cybernoid.sid",
  ),
  DemoTune(
    "🍄",
    "Giana Sisters",
    "Chris Hülsbeck",
    "great_giana_sisters.sid",
    "MUSICIANS/H/Huelsbeck_Chris/Great_Giana_Sisters.sid",
  ),
  DemoTune(
    "🥷",
    "Last Ninja 2",
    "Matt Gray",
    "last_ninja_2.sid",
    "MUSICIANS/G/Gray_Matt/Last_Ninja_2.sid",
  ),
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
          "MOS 6581 / 8580 SID chiptune conversion. Synthesizes Skred's analog-modeled waveforms (w15 analog saw, w16 analog square/PWM, w18 analog triangle, w5 noise), CZ phase-distortion PWM (c1,#), calibrated headroom, ring modulation (XM) & realtime biquad filters.",
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
          text("Or stream on the fly from the online HVSC collection:"),
        ]),
        html.div(
          [class("demo-buttons")],
          list.append(
            list.map(featured_demos, fn(demo) {
              let url = demo.path
              html.button(
                [
                  class("btn btn-secondary btn-sm"),
                  event.on_click(LoadDemo(
                    url,
                    demo.filename,
                    demo.title,
                    demo.author,
                  )),
                  attribute.disabled(model.is_converting),
                ],
                [
                  text(
                    demo.icon <> " " <> demo.title <> " (" <> demo.author <> ")",
                  ),
                ],
              )
            }),
            [
              html.button(
                [
                  class("btn btn-modarchive btn-sm"),
                  event.on_click(RandomSidClicked),
                  attribute.disabled(model.is_converting),
                ],
                [text("🎲 Random SID Tune (Online from HVSC Archive)")],
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
  let source_display = case model.source_description {
    "" -> "🌐 HVSC Online Archive"
    s -> s
  }

  let hvsc_items = case model.hvsc_path {
    Some(path) -> [
      html.div([class("meta-item meta-item-hvsc")], [
        html.span([class("meta-label")], [text("PUBLIC ARCHIVE")]),
        html.a(
          [
            class("meta-link-hvsc"),
            href("https://deepsid.chordian.net/?file=/" <> path),
            target("_blank"),
            rel("noopener noreferrer"),
            title("Open tune on DeepSID chordian player"),
          ],
          [text("🌐 DeepSID ↗")],
        ),
        html.a(
          [
            class("meta-link-direct"),
            href("https://hvsc.brona.dk/HVSC/C64Music/" <> path),
            target("_blank"),
            rel("noopener noreferrer"),
            title("Download original .SID file from HVSC"),
          ],
          [text("📥 .SID ↗")],
        ),
      ]),
    ]
    None -> []
  }

  let base_items = [
    html.div([class("meta-item meta-title-item")], [
      html.span([class("meta-label")], [text("TITLE")]),
      html.span([class("meta-val highlight-title")], [text(clean_title)]),
    ]),
    html.div([class("meta-item")], [
      html.span([class("meta-label")], [text("AUTHOR")]),
      html.span([class("meta-val")], [text(clean_author)]),
    ]),
    html.div([class("meta-item")], [
      html.span([class("meta-label")], [text("OSCILLATORS")]),
      html.span([class("meta-val highlight-analog")], [
        text("Analog (w15/w16/w18/w5)"),
      ]),
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
    html.div([class("meta-item meta-source-item")], [
      html.span([class("meta-label")], [text("ARCHIVE SOURCE")]),
      html.span([class("meta-val highlight-source")], [text(source_display)]),
    ]),
  ]

  html.div([class("metadata-bar")], list.append(base_items, hvsc_items))
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

fn view_tab_info(model: Model, song: DumpSong) -> Element(Msg) {
  let source_display = case model.source_description {
    "" -> "High Voltage SID Collection (HVSC) — https://hvsc.c64.org"
    s -> s
  }

  let archive_card = case model.hvsc_path {
    Some(path) -> [
      html.div([class("song-info-card")], [
        html.h3([class("card-title")], [
          text("🌐 Public Web Source & DeepSID Player"),
        ]),
        html.div([class("info-grid")], [
          html.div([class("info-row")], [
            html.span([class("info-key")], [text("HVSC Relative Path")]),
            html.span([class("info-val mono")], [text(path)]),
          ]),
          html.div([class("info-row")], [
            html.span([class("info-key")], [text("DeepSID Online Player")]),
            html.a(
              [
                class("meta-link-hvsc"),
                href("https://deepsid.chordian.net/?file=/" <> path),
                target("_blank"),
                rel("noopener noreferrer"),
              ],
              [text("https://deepsid.chordian.net/?file=/" <> path <> " ↗")],
            ),
          ]),
          html.div([class("info-row")], [
            html.span([class("info-key")], [text("Original .SID Download")]),
            html.a(
              [
                class("meta-link-direct"),
                href("https://hvsc.brona.dk/HVSC/C64Music/" <> path),
                target("_blank"),
                rel("noopener noreferrer"),
              ],
              [text("Download " <> path <> " (HVSC Mirror) ↗")],
            ),
          ]),
        ]),
      ]),
    ]
    None -> []
  }

  let base_cards = [
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
        info_row("Archive Source", source_display),
      ]),
    ]),
    html.div([class("song-info-card")], [
      html.h3([class("card-title")], [
        text("⚡ Skred Bandlimited Analog Waveforms & Headroom"),
      ]),
      html.p([class("card-body-text")], [
        text(
          "To authentically reproduce the warmth, harmonic richness, and punch of the Commodore 64 MOS SID (6581/8580), sid-to-skode routes voices directly to Skred's bandlimited analog-modeled oscillator core:\n\n• w15 -> Bandlimited Analog Sawtooth (SID Saw)\n• w16 -> Bandlimited Analog Square / Pulse with CZ phase-distortion PWM (c1,#)\n• w18 -> Bandlimited Analog Triangle (SID Tri)\n• w5  -> SID White Noise Generator\n\nGain Staging & Headroom: Voice amplitudes are calibrated with -8 dBFS per-voice nominal headroom (V -8 dB master) so that multi-oscillator summing and high-resonance biquad filter sweeps (j/k/q) never clip or produce ear-fatiguing distortion.",
        ),
      ]),
    ]),
    html.div([class("song-info-card")], [
      html.h3([class("card-title")], [
        text("🌐 Public Web Archive (HVSC) Direct Streaming"),
      ]),
      html.p([class("card-body-text")], [
        text(
          "Random SID tunes and featured classics are pulled on the fly directly over HTTP from the High Voltage SID Collection mirror (https://hvsc.brona.dk/HVSC/C64Music/). Songs are emulated client-side in the browser via an embedded siddump WebAssembly module without pre-downloading or storing dumps on your machine, playing for their full natural song duration without artificial caps.",
        ),
      ]),
    ]),
  ]

  html.div([class("info-tab-layout")], list.append(archive_card, base_cards))
}

fn info_row(label: String, val: String) -> Element(Msg) {
  html.div([class("info-row")], [
    html.span([class("info-key")], [text(label)]),
    html.span([class("info-val")], [text(val)]),
  ])
}

fn hex4(n: Int) -> String {
  let s = int.to_base16(n)
  case string.length(s) {
    1 -> "000" <> s
    2 -> "00" <> s
    3 -> "0" <> s
    _ -> s
  }
}

fn hex2(n: Int) -> String {
  let s = int.to_base16(n)
  case string.length(s) {
    1 -> "0" <> s
    _ -> s
  }
}

fn view_tab_voices(model: Model, song: DumpSong) -> Element(Msg) {
  let step_idx = case model.is_playing {
    True -> int.min(model.current_step, song.frame_count - 1)
    False -> 0
  }

  let frame = case dict.get(song.frame_dict, step_idx) {
    Ok(f) -> f
    Error(_) ->
      SidFrame(
        step_idx,
        default_voice_frame(),
        default_voice_frame(),
        default_voice_frame(),
        default_filter_frame(),
      )
  }

  html.div([class("voices-tab-layout")], [
    view_register_strip(step_idx, song.frame_count, frame),
    html.div([class("voices-grid")], [
      view_voice_channel_card(0, "Voice 1", "$D400-$D406", frame.v1),
      view_voice_channel_card(1, "Voice 2", "$D407-$D40D", frame.v2),
      view_voice_channel_card(2, "Voice 3", "$D40E-$D414", frame.v3),
    ]),
    view_filter_card(frame.filter),
  ])
}

fn view_register_strip(step: Int, total: Int, frame: SidFrame) -> Element(Msg) {
  let v1 = frame.v1
  let v2 = frame.v2
  let v3 = frame.v3
  let flt = frame.filter

  html.div([class("sid-reg-strip card")], [
    html.div([class("reg-strip-header")], [
      html.div([class("reg-strip-title")], [
        html.span([class("reg-title-icon")], [text("⚡")]),
        html.span([class("reg-title-text")], [
          text("LIVE SID REGISTER ACTIVITY"),
        ]),
        html.span([class("reg-step-badge mono")], [
          text(
            "Frame #"
            <> int.to_string(step + 1)
            <> " / "
            <> int.to_string(total),
          ),
        ]),
      ]),
      html.span([class("reg-pal-badge mono")], [
        text("50.0 Hz PAL · 20.0ms tick"),
      ]),
    ]),
    html.div([class("reg-blocks-row mono")], [
      reg_block("V1 $D400", [
        reg_val("Freq", "$" <> hex4(v1.freq), v1.freq_changed),
        reg_val("PW", "$" <> hex4(v1.pulse_width), v1.pulse_changed),
        reg_val("Ctrl", "$" <> hex2(v1.waveform_byte), v1.wave_changed),
        reg_val("ADSR", "$" <> hex4(v1.adsr), v1.adsr_changed),
      ]),
      reg_block("V2 $D407", [
        reg_val("Freq", "$" <> hex4(v2.freq), v2.freq_changed),
        reg_val("PW", "$" <> hex4(v2.pulse_width), v2.pulse_changed),
        reg_val("Ctrl", "$" <> hex2(v2.waveform_byte), v2.wave_changed),
        reg_val("ADSR", "$" <> hex4(v2.adsr), v2.adsr_changed),
      ]),
      reg_block("V3 $D40E", [
        reg_val("Freq", "$" <> hex4(v3.freq), v3.freq_changed),
        reg_val("PW", "$" <> hex4(v3.pulse_width), v3.pulse_changed),
        reg_val("Ctrl", "$" <> hex2(v3.waveform_byte), v3.wave_changed),
        reg_val("ADSR", "$" <> hex4(v3.adsr), v3.adsr_changed),
      ]),
      reg_block("FLT $D415", [
        reg_val("Cutoff", "$" <> hex4(flt.cutoff), flt.cutoff_changed),
        reg_val("Res/R", "$" <> hex2(flt.res_routing), flt.ctrl_changed),
        reg_val(
          "Mode/Vol",
          "$" <> hex2(flt.volume),
          flt.vol_changed || flt.mode_changed,
        ),
      ]),
    ]),
  ])
}

fn reg_block(label: String, items: List(Element(Msg))) -> Element(Msg) {
  html.div([class("reg-block")], [
    html.div([class("reg-block-header")], [text(label)]),
    html.div([class("reg-block-items")], items),
  ])
}

fn reg_val(name: String, val: String, changed: Bool) -> Element(Msg) {
  html.div(
    [
      class(case changed {
        True -> "reg-cell reg-cell-changed"
        False -> "reg-cell"
      }),
    ],
    [
      html.span([class("reg-cell-name")], [text(name)]),
      html.span([class("reg-cell-val")], [text(val)]),
      case changed {
        True ->
          html.span(
            [
              class("reg-delta-dot"),
              title("Register modified on this frame"),
            ],
            [text("Δ")],
          )
        False -> none()
      },
    ],
  )
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
  addr_range: String,
  vf: VoiceFrame,
) -> Element(Msg) {
  let hz = converter.freq_to_hz(vf.freq)
  let hz_str = converter.format_float(hz, 1) <> " Hz"
  let wave_desc = case vf.waveform_byte {
    b if b >= 128 -> "Noise (w5)"
    b if b >= 64 -> "Analog Square / PWM (w16)"
    b if b >= 32 -> "Analog Sawtooth (w15)"
    b if b >= 16 -> "Analog Triangle (w18)"
    _ -> "Rest / Off"
  }
  let duty_pct =
    converter.format_float(int.to_float(vf.pulse_width) /. 40.95, 1) <> "%"

  html.div([class("voice-card")], [
    html.div([class("voice-card-header")], [
      html.div([class("voice-title-group")], [
        html.h4([class("voice-title")], [text(label)]),
        html.span([class("voice-addr-badge mono")], [text(addr_range)]),
      ]),
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
      spec_item_with_delta(
        "Note / Freq",
        vf.note_name <> " (" <> hz_str <> ") · $" <> hex4(vf.freq),
        vf.freq_changed,
      ),
      spec_item_with_delta(
        "Waveform",
        wave_desc <> " · $" <> hex2(vf.waveform_byte),
        vf.wave_changed,
      ),
      spec_item_with_delta(
        "Pulse Width",
        duty_pct <> " · $" <> hex4(vf.pulse_width),
        vf.pulse_changed,
      ),
      spec_item_with_delta(
        "ADSR",
        int.to_string(vf.attack)
          <> "/"
          <> int.to_string(vf.decay)
          <> "/"
          <> int.to_string(vf.sustain)
          <> "/"
          <> int.to_string(vf.release)
          <> " · $"
          <> hex4(vf.adsr),
        vf.adsr_changed,
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

fn spec_item_with_delta(
  label: String,
  val: String,
  changed: Bool,
) -> Element(Msg) {
  html.div(
    [
      class(case changed {
        True -> "spec-item spec-item-changed"
        False -> "spec-item"
      }),
    ],
    [
      html.div([class("spec-label-row")], [
        html.span([class("spec-label")], [text(label)]),
        case changed {
          True -> html.span([class("delta-badge")], [text("Δ WRITE")])
          False -> none()
        },
      ]),
      html.span([class("spec-val mono")], [text(val)]),
    ],
  )
}

fn view_filter_card(ff: FilterFrame) -> Element(Msg) {
  let cutoff_hz = converter.cutoff_to_hz(ff.cutoff)
  let q_res = converter.res_to_q(ff.resonance)

  html.div([class("filter-card")], [
    html.div([class("filter-header")], [
      html.div([class("filter-title-group")], [
        html.h4([class("filter-title")], [
          text("Biquad Filter & Routing (Track 3)"),
        ]),
        html.span([class("filter-addr-badge mono")], [text("$D415-$D418")]),
      ]),
      html.span([class("badge-engine")], [text("Mode: " <> ff.mode_str)]),
    ]),
    html.div([class("filter-specs-grid")], [
      spec_item_with_delta(
        "Cutoff (k)",
        converter.format_float(cutoff_hz, 1) <> " Hz · $" <> hex4(ff.cutoff),
        ff.cutoff_changed,
      ),
      spec_item_with_delta(
        "Resonance (q)",
        "Q "
          <> converter.format_float(q_res, 2)
          <> " (reg "
          <> int.to_string(ff.resonance)
          <> ")",
        ff.ctrl_changed,
      ),
      spec_item_with_delta(
        "Channel Routing",
        case ff.route_v1, ff.route_v2, ff.route_v3 {
          True, True, True -> "Voices 1, 2, 3 filtered"
          True, True, False -> "Voices 1, 2 filtered"
          True, False, False -> "Voice 1 filtered"
          False, True, False -> "Voice 2 filtered"
          False, False, True -> "Voice 3 filtered"
          _, _, _ -> "None (Bypassed)"
        },
        ff.ctrl_changed,
      ),
      spec_item_with_delta(
        "Master SID Vol",
        int.to_string(ff.volume) <> " / 15",
        ff.vol_changed,
      ),
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
