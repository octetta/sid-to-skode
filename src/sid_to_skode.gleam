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
  type DigiSample, type DumpSong, type FilterFrame, type Model, type Msg,
  type SidFrame, type VoiceFrame, AuditionSample, ConversionFailed,
  CopySkodeClicked, DownloadSkodeClicked, DumpTextReady, EngineStatusChanged,
  FileDropped, FilterFrame, LoadDemo, MasterVolumeChanged, Model, PanicClicked,
  PauseClicked, PlayClicked, PlaybackEnded, PlaybackStepChanged, RandomSidClicked,
  ResetClicked, ResumeClicked, SeekStep, SidFrame, StereoCustom, StereoHeadphone,
  StereoModeChanged, StereoMono, StereoWide, StopClicked, TabSelected,
  ToggleDacCrunch, ToggleReplClicked, VoiceFrame, VoicePanChanged,
}

// ---------------------------------------------------------------------------
// JavaScript FFI Declarations
// ---------------------------------------------------------------------------

@external(javascript, "./skred_ffi.mjs", "initEngine")
fn js_init_engine(callback: fn(Bool, String) -> Nil) -> Nil

@external(javascript, "./skred_ffi.mjs", "registerFileDrop")
fn js_register_file_drop(
  callback: fn(String, String, String, String) -> Nil,
) -> Nil

@external(javascript, "./skred_ffi.mjs", "playSkode")
fn js_play_skode(script: String, steps: Int, start_step: Int) -> Nil

@external(javascript, "./skred_ffi.mjs", "ejectSong")
fn js_eject_song() -> Nil

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

@external(javascript, "./skred_ffi.mjs", "seekToStep")
fn js_seek_to_step(step: Int) -> Nil

@external(javascript, "./skred_ffi.mjs", "setDacCrunch")
fn js_set_dac_crunch(enabled: Bool) -> Nil

@external(javascript, "./skred_ffi.mjs", "auditionSample")
fn js_audition_sample(slot: Int, script: String, pan: Float) -> Nil

// ---------------------------------------------------------------------------
// Lustre Effects
// ---------------------------------------------------------------------------

fn audition_sample_effect(slot: Int, script: String, pan: Float) -> Effect(Msg) {
  effect.from(fn(_dispatch) { js_audition_sample(slot, script, pan) })
}

fn seek_effect(step: Int) -> Effect(Msg) {
  effect.from(fn(_dispatch) { js_seek_to_step(step) })
}

fn set_dac_crunch_effect(enabled: Bool) -> Effect(Msg) {
  effect.from(fn(_dispatch) { js_set_dac_crunch(enabled) })
}

fn init_engine_effect() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    js_init_engine(fn(success, version) {
      dispatch(EngineStatusChanged(success, version))
    })
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

fn play_effect(script: String, total_steps: Int, start_step: Int) -> Effect(Msg) {
  effect.from(fn(_dispatch) { js_play_skode(script, total_steps, start_step) })
}

fn eject_effect() -> Effect(Msg) {
  effect.from(fn(_dispatch) { js_eject_song() })
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
      engine_version: "0.82.0",
      is_playing: False,
      is_paused: False,
      current_step: 0,
      active_song: None,
      conversion: None,
      is_converting: False,
      error_message: None,
      status_text: "Ready. Drag and drop any Commodore 64 .SID file or siddump output.",
      active_tab: "voices",
      catalog_info: None,
      stereo_mode: StereoMono,
      voice_pan: #(0.0, 0.0, 0.0),
      sample_pan: 0.0,
      master_volume: -8,
      raw_dump_text: "",
      source_description: "",
      hvsc_path: None,
      dac_crunch: True,
    )

  let effects =
    effect.batch([
      init_engine_effect(),
      register_file_drop_effect(),
      register_playback_listener_effect(),
    ])

  #(model, effects)
}

fn refresh_conversion_if_needed(model: Model) -> Model {
  case model.active_song {
    Some(song) -> {
      case
        converter.convert_song_full(
          song,
          model.stereo_mode,
          model.dac_crunch,
          model.sample_pan,
        )
      {
        Ok(conv) -> Model(..model, conversion: Some(conv))
        Error(_) -> model
      }
    }
    None -> model
  }
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    EngineStatusChanged(ready, version) -> {
      let status = case ready {
        True -> "Skred " <> version <> " WASM engine ready."
        False -> "Failed to initialize Skred WASM audio engine."
      }
      #(
        Model(..model, engine_ready: ready, engine_version: version, status_text: status),
        effect.none(),
      )
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
          case
            converter.convert_song_full(
              song,
              model.stereo_mode,
              model.dac_crunch,
              model.sample_pan,
            )
          {
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
      let current_model = case model.is_playing {
        False -> refresh_conversion_if_needed(model)
        True -> model
      }
      case current_model.conversion {
        Some(conv) -> {
          let step = current_model.current_step
          #(
            Model(
              ..current_model,
              is_playing: True,
              is_paused: False,
              status_text: "Playing in Skred WASM (50 Hz step clock)...",
            ),
            play_effect(conv.skode_text, conv.total_steps, step),
          )
        }
        None -> #(current_model, effect.none())
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
      let current_model = refresh_conversion_if_needed(model)
      case current_model.conversion, current_model.active_song {
        Some(conv), Some(song) -> {
          let filename = clean_skode_filename(song.title)
          #(
            Model(..current_model, status_text: "Downloading " <> filename <> "..."),
            download_file_effect(filename, conv.skode_text),
          )
        }
        _, _ -> #(current_model, effect.none())
      }
    }

    CopySkodeClicked -> {
      let current_model = refresh_conversion_if_needed(model)
      case current_model.conversion {
        Some(conv) -> #(
          Model(..current_model, status_text: "Skode script copied to clipboard!"),
          copy_clipboard_effect(conv.skode_text),
        )
        None -> #(current_model, effect.none())
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
        eject_effect(),
      )
    }

    ToggleReplClicked -> {
      #(model, toggle_repl_effect())
    }

    TabSelected(tab) -> {
      let current_model = case tab {
        "skode" -> refresh_conversion_if_needed(model)
        _ -> model
      }
      #(Model(..current_model, active_tab: tab), effect.none())
    }

    AuditionSample(slot) -> {
      let script_text = case model.conversion {
        Some(conv) -> conv.skode_text
        None -> ""
      }
      let status =
        "Auditioning digi sample w"
        <> int.to_string(slot)
        <> " on free Skred voice"
      #(
        Model(..model, status_text: status),
        audition_sample_effect(slot, script_text, model.sample_pan),
      )
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
      let #(p0, p1, p2) = case new_mode {
        StereoHeadphone -> #(-0.6, 0.6, 0.0)
        StereoWide -> #(-1.0, 1.0, 0.0)
        StereoMono -> #(0.0, 0.0, 0.0)
        StereoCustom(v0, v1, v2) -> #(v0, v1, v2)
      }
      let live_cmd = converter.build_live_stereo_command(new_mode)
      let mode_desc = case new_mode {
        StereoHeadphone ->
          "Stereo pan preset: 🎧 Headphone (-0.60 / +0.60 / Center)"
        StereoWide -> "Stereo pan preset: 🔊 Wide (-1.00 / +1.00 / Center)"
        StereoMono -> "Stereo pan preset: 📻 Authentic Mono (All centered)"
        StereoCustom(_, _, _) -> "Custom stereo voice panning active"
      }
      #(
        Model(
          ..model,
          stereo_mode: new_mode,
          voice_pan: #(p0, p1, p2),
          status_text: mode_desc,
        ),
        send_command_effect(live_cmd),
      )
    }

    VoicePanChanged(v, pan) -> {
      let clamped = float.clamp(pan, -1.0, 1.0)
      case v {
        3 -> {
          let cmd = converter.build_voice_pan_command(3, clamped)
          let status =
            "Digi Sample Voice pan: "
            <> format_pan_label(clamped)
            <> " ("
            <> converter.format_float(clamped, 2)
            <> ")"
          #(
            Model(
              ..model,
              sample_pan: clamped,
              status_text: status,
            ),
            send_command_effect(cmd),
          )
        }
        _ -> {
          let #(p0, p1, p2) = model.voice_pan
          let next_pans = case v {
            0 -> #(clamped, p1, p2)
            1 -> #(p0, clamped, p2)
            2 -> #(p0, p1, clamped)
            _ -> model.voice_pan
          }
          let next_mode = StereoCustom(next_pans.0, next_pans.1, next_pans.2)
          let cmd = converter.build_voice_pan_command(v, clamped)
          let status =
            "Voice "
            <> int.to_string(v + 1)
            <> " pan: "
            <> format_pan_label(clamped)
            <> " ("
            <> converter.format_float(clamped, 2)
            <> ")"
          #(
            Model(
              ..model,
              voice_pan: next_pans,
              stereo_mode: next_mode,
              status_text: status,
            ),
            send_command_effect(cmd),
          )
        }
      }
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

    ToggleDacCrunch -> {
      let next_dac = !model.dac_crunch
      let status = case next_dac {
        True -> "🎛️ MOS 6581 DAC Crunch: ON (bc 6 quantized)"
        False -> "🎛️ MOS 6581 DAC Crunch: OFF (clean 24-bit DSP)"
      }
      #(
        Model(
          ..model,
          dac_crunch: next_dac,
          status_text: status,
        ),
        set_dac_crunch_effect(next_dac),
      )
    }

    SeekStep(step) -> {
      let valid_step = case model.conversion {
        Some(conv) -> int.max(0, int.min(step, conv.total_steps - 1))
        None -> int.max(0, step)
      }
      #(
        Model(..model, current_step: valid_step),
        seek_effect(valid_step),
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
      html.span([class("badge-engine")], [text("Skred v" <> model.engine_version)]),
      html.span([class("brand-tagline")], [text("C64 to Skred Synthesizer")]),
    ]),
    html.div([class("header-controls")], [
      html.div(
        [
          class("engine-status"),
          attribute.title(case model.engine_ready {
            True -> "Skred " <> model.engine_version <> " Audio Engine Ready"
            False -> "Loading WASM Audio Engine..."
          }),
        ],
        [
          html.span(
            [
              class(case model.engine_ready {
                True -> "status-dot status-ready"
                False -> "status-dot status-loading"
              }),
            ],
            [],
          ),
        ],
      ),
      html.button(
        [
          class("btn btn-terminal btn-sm"),
          event.on_click(ToggleReplClicked),
          attribute.title("Toggle Skred Interactive REPL (Ctrl+~)"),
        ],
        [text(">_ REPL")],
      ),
      html.button(
        [
          class("btn btn-danger btn-sm"),
          event.on_click(PanicClicked),
          attribute.title("Emergency Audio Panic / Silence All"),
        ],
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
    "🥁",
    "Great Giana Sisters (Digi)",
    "Chris Hülsbeck",
    "great_giana_sisters.sid",
    "demos/great_giana_sisters.sid",
  ),
  DemoTune(
    "🎤",
    "To Be On Top (Digi)",
    "Chris Hülsbeck",
    "to_be_on_top.sid",
    "demos/to_be_on_top.sid",
  ),
  DemoTune(
    "🏎️",
    "Turbo Outrun (Digi)",
    "Jeroen Tel",
    "turbo_outrun.sid",
    "demos/turbo_outrun.sid",
  ),
  DemoTune(
    "🧱",
    "Arkanoid (Digi)",
    "Martin Galway",
    "arkanoid.sid",
    "demos/arkanoid.sid",
  ),
  DemoTune(
    "👻",
    "Ghostbusters II",
    "David Whittaker",
    "ghostbusters_ii.sid",
    "demos/ghostbusters_ii.sid",
  ),
  DemoTune(
    "🎖️",
    "Commando",
    "Rob Hubbard",
    "commando.sid",
    "demos/commando.sid",
  ),
  DemoTune(
    "🛩️",
    "Glider Rider",
    "David Whittaker",
    "glider_rider.sid",
    "demos/glider_rider.sid",
  ),
  DemoTune(
    "⚡",
    "Eliminator",
    "Jeroen Tel",
    "eliminator.sid",
    "demos/eliminator.sid",
  ),
  DemoTune(
    "🧙",
    "Flimbo's Quest",
    "Johannes Bjerregaard",
    "flimbos_quest.sid",
    "demos/flimbos_quest.sid",
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
          "MOS 6581 / 8580 SID chiptune conversion. Synthesizes dedicated Ksynth-modeled SID waveforms (w300 triangle, w301 saw, w302 pulse/PWM, w303 saw+tri, w304 saw+pulse, w6 live white noise), CZ phase-distortion PWM (c1,#), calibrated headroom, ring modulation & realtime biquad filters.",
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
            "Every converted SID frame maps directly to Skred synthesis opcodes:",
          ),
        ]),
      ]),
      html.pre([class("developer-code-preview")], [
        html.code([], [
          text(
            "# 1. Ksynth-Generated SID Waveforms:\nw300 -> Bandlimited Triangle (SID Tri, odd harmonics 1/h^2, alternating phase)\nw301 -> Bandlimited Sawtooth (SID Saw, 64 harmonics 1/h)\nw302 -> Bandlimited Square (SID Pulse, 50% square + CZ PWM)\nw303 -> Combined Saw+Triangle ($30 hybrid)\nw304 -> Combined Saw+Pulse ($60 hybrid)\nw6   -> Live White Noise (Continuous Hardware RNG, zero cyclic comb-filter buzz)\n\n# 2. CZ Phase-Distortion PWM:\nc1,-0.5 -> Narrow Pulse (25% Duty)\nc1,0.0  -> Square Wave (50% Duty)\nc1,0.5  -> Wide Pulse (75% Duty)\n\n# 3. Dynamic Biquad Filtering:\nj1 k1200 q1.5 -> Resonant Low-Pass at 1.2 kHz\nj2 k400  q0.7 -> High-Pass at 400 Hz\nj3 k800  q3.0 -> Band-Pass centered at 800 Hz",
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
        "Produces authentic Skode scripts ready for instant playback in Skred WASM or download for CLI usage.",
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
    view_tabs_navigation(model, song),
    view_tab_content(model, song),
  ])
}

fn view_transport_bar(model: Model, song: DumpSong) -> Element(Msg) {
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
  let song_strip =
    html.div([class("song-header-strip")], [
      html.div([class("song-header-main")], [
        html.span([class("song-header-icon")], [text("🎵")]),
        html.span([class("song-header-title")], [text(clean_title)]),
        html.span([class("song-header-author")], [text("by " <> clean_author)]),
      ]),
      html.div([class("song-header-meta")], [
        html.span([class("meta-chip mono")], [
          text(int.to_string(song.frame_count) <> " frames"),
        ]),
        html.span([class("meta-chip mono")], [text("PAL 50Hz")]),
        html.span([class("meta-chip mono")], [text(duration_str)]),
        case list.is_empty(song.digi_samples) {
          True -> html.span([], [])
          False ->
            html.span([class("meta-chip meta-chip-gold mono")], [
              text(
                "🥁 "
                <> int.to_string(list.length(song.digi_samples))
                <> " PCM Digis",
              ),
            ])
        },
      ]),
    ])

  let play_pause_btn = case model.is_playing {
    False ->
      html.button(
        [
          class("btn btn-success btn-transport"),
          event.on_click(PlayClicked),
          attribute.disabled(model.conversion == None),
          attribute.title("Start playback in Skred WASM"),
        ],
        [text("▶ Play")],
      )
    True -> {
      case model.is_paused {
        False ->
          html.button(
            [
              class("btn btn-warning btn-transport"),
              event.on_click(PauseClicked),
              attribute.title("Pause playback (Z2)"),
            ],
            [text("⏸ Pause")],
          )
        True ->
          html.button(
            [
              class("btn btn-success btn-transport pulse-paused"),
              event.on_click(ResumeClicked),
              attribute.title("Resume playback (Z3)"),
            ],
            [text("▶ Resume")],
          )
      }
    }
  }

  let stop_btn = case model.is_playing {
    True ->
      html.button(
        [
          class("btn btn-danger btn-transport"),
          event.on_click(StopClicked),
          attribute.title("Stop playback (Z0; S-1)"),
        ],
        [text("⏹ Stop")],
      )
    False ->
      html.button(
        [
          class("btn btn-secondary btn-transport"),
          attribute.disabled(True),
          attribute.title("Playback stopped"),
        ],
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
          html.input([
            type_("range"),
            attribute.min("0"),
            attribute.max(int.to_string(int.max(1, total_rows - 1))),
            attribute.step("1"),
            attribute.value(int.to_string(cur_step)),
            attribute.title(
              "Click or drag to jump anywhere in the SID tune (Frame #"
              <> int.to_string(cur_step + 1)
              <> ")",
            ),
            class("playback-progress-slider"),
            event.on_input(fn(val_str) {
              case int.parse(val_str) {
                Ok(step) -> SeekStep(step)
                Error(_) -> SeekStep(0)
              }
            }),
          ]),
        ]),
      ])
    }
    None -> html.div([], [])
  }

  html.div([class("transport-container")], [
    song_strip,
    html.div([class("transport-bar")], [
      html.div([class("transport-buttons")], [
        play_pause_btn,
        stop_btn,
        html.button(
          [
            class("btn btn-outline btn-transport"),
            event.on_click(DownloadSkodeClicked),
            attribute.disabled(model.conversion == None),
            attribute.title("Download compiled Skode script (.sk)"),
          ],
          [text("💾 .SK")],
        ),
        html.button(
          [
            class("btn btn-outline btn-transport"),
            event.on_click(RandomSidClicked),
            attribute.disabled(model.is_converting),
            attribute.title("Load random SID tune from HVSC online"),
          ],
          [text("🎲 Random")],
        ),
        html.button(
          [
            class("btn btn-outline btn-transport"),
            event.on_click(ResetClicked),
            attribute.title("Eject tune and choose another file"),
          ],
          [text("⟲ New")],
        ),
      ]),
      html.div([class("transport-controls-right")], [
        view_dac_crunch_toggle(model),
        view_volume_slider(model),
        view_stereo_selector(model),
      ]),
    ]),
    progress_section,
  ])
}

fn view_dac_crunch_toggle(model: Model) -> Element(Msg) {
  html.button(
    [
      class(case model.dac_crunch {
        True -> "btn btn-sm btn-dac-crunch active"
        False -> "btn btn-sm btn-dac-crunch"
      }),
      event.on_click(ToggleDacCrunch),
      attribute.title(case model.dac_crunch {
        True -> "MOS 6581 DAC Crunch: ON (bc 6). Click to toggle clean 24-bit DSP."
        False -> "MOS 6581 DAC Crunch: OFF (bc 0). Click to toggle 6-bit DAC crunch."
      }),
    ],
    [
      text(case model.dac_crunch {
        True -> "🎛️ DAC: 6-Bit"
        False -> "🎛️ DAC: Clean"
      }),
    ],
  )
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

fn format_pan_label(pan: Float) -> String {
  let rounded = float.round(pan *. 100.0)
  case rounded {
    0 -> "Center"
    r if r < 0 -> int.to_string(-r) <> "% Left"
    r -> int.to_string(r) <> "% Right"
  }
}

fn view_stereo_selector(model: Model) -> Element(Msg) {
  let #(p0, p1, p2) = model.voice_pan
  let has_digi = case model.active_song {
    Some(song) -> !list.is_empty(song.digi_samples)
    None -> False
  }
  html.div([class("stereo-control-group")], [
    html.div([class("stereo-presets-row")], [
      html.span([class("stereo-label")], [text("PANNING")]),
      html.div([class("segmented-control")], [
        html.button(
          [
            class(case model.stereo_mode {
              StereoMono -> "segment-btn active"
              _ -> "segment-btn"
            }),
            event.on_click(StereoModeChanged(StereoMono)),
            attribute.title("Authentic Mono (0.0 / 0.0 / 0.0)"),
          ],
          [text("📻 Mono")],
        ),
        html.button(
          [
            class(case model.stereo_mode {
              StereoHeadphone -> "segment-btn active"
              _ -> "segment-btn"
            }),
            event.on_click(StereoModeChanged(StereoHeadphone)),
            attribute.title("Headphone separation (-0.60 / +0.60 / Center)"),
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
            attribute.title("Wide separation (-1.00 / +1.00 / Center)"),
          ],
          [text("🔊 Wide")],
        ),
      ]),
    ]),
    html.div([class("voice-pan-sliders")], case has_digi {
      True -> [
        view_voice_pan_slider(0, "V1", p0),
        view_voice_pan_slider(1, "V2", p1),
        view_voice_pan_slider(2, "V3", p2),
        view_voice_pan_slider(3, "Digi", model.sample_pan),
      ]
      False -> [
        view_voice_pan_slider(0, "V1", p0),
        view_voice_pan_slider(1, "V2", p1),
        view_voice_pan_slider(2, "V3", p2),
      ]
    }),
  ])
}

fn view_voice_pan_slider(
  voice_idx: Int,
  label: String,
  pan: Float,
) -> Element(Msg) {
  html.div([class("pan-slider-item")], [
    html.span([class("pan-slider-label")], [text(label)]),
    html.input([
      type_("range"),
      attribute.min("-1.0"),
      attribute.max("1.0"),
      attribute.step("0.05"),
      attribute.value(converter.format_float(pan, 2)),
      class("pan-range-input"),
      attribute.title(
        label
        <> ": "
        <> format_pan_label(pan)
        <> " (v"
        <> int.to_string(voice_idx)
        <> " p"
        <> converter.format_float(pan, 2)
        <> ")",
      ),
      event.on_input(fn(val) {
        case float.parse(val) {
          Ok(f) -> VoicePanChanged(voice_idx, f)
          Error(_) -> VoicePanChanged(voice_idx, 0.0)
        }
      }),
    ]),
    html.span([class("pan-slider-val mono")], [
      text(converter.format_float(pan, 2)),
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
        text("Ksynth SID (w300..w304/w6)"),
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
      html.span(
        [
          class("meta-val highlight-source"),
          attribute.title(source_display),
        ],
        [text(source_display)],
      ),
    ]),
  ]

  let digi_badges = case song.digi_samples {
    [] -> []
    samples -> {
      let slots_str =
        list.map(samples, fn(s) { "w" <> int.to_string(s.slot) })
        |> string.join(", ")
      [
        html.div([class("meta-item meta-item-digi")], [
          html.span([class("meta-label")], [text("DIGI SAMPLES")]),
          html.span([class("meta-val highlight-gold mono")], [
            text("🥁 " <> slots_str),
          ]),
        ]),
      ]
    }
  }

  html.div(
    [class("metadata-bar")],
    list.flatten([base_items, digi_badges, hvsc_items]),
  )
}

fn view_tabs_navigation(model: Model, song: DumpSong) -> Element(Msg) {
  let has_digi = !list.is_empty(song.digi_samples)
  let digi_tab = case has_digi {
    True -> [
      html.button(
        [
          class(case model.active_tab {
            "samples" -> "tab-btn active tab-btn-digi"
            _ -> "tab-btn tab-btn-digi"
          }),
          event.on_click(TabSelected("samples")),
          attribute.title(
            "Audition Captured C64 PCM Digi Samples ("
            <> int.to_string(list.length(song.digi_samples))
            <> ") on Free Skred Voices",
          ),
        ],
        [
          text(
            "🥁 Digi Samples ("
            <> int.to_string(list.length(song.digi_samples))
            <> ")",
          ),
        ],
      ),
    ]
    False -> []
  }

  html.nav(
    [class("tabs-nav")],
    list.flatten([
      [
        html.button(
          [
            class(case model.active_tab {
              "voices" -> "tab-btn active"
              _ -> "tab-btn"
            }),
            event.on_click(TabSelected("voices")),
            attribute.title(
              "Live SID Oscillators, ADSR Envelopes, Waveforms & Biquad Filter",
            ),
          ],
          [text("🎛️ SID Registers & Voices")],
        ),
      ],
      digi_tab,
      [
        html.button(
          [
            class(case model.active_tab {
              "info" -> "tab-btn active"
              _ -> "tab-btn"
            }),
            event.on_click(TabSelected("info")),
            attribute.title("Tune Metadata, Authorship & Synthesis Architecture"),
          ],
          [text("ℹ️ Tune Info")],
        ),
        html.button(
          [
            class(case model.active_tab {
              "skode" -> "tab-btn active"
              _ -> "tab-btn"
            }),
            event.on_click(TabSelected("skode")),
            attribute.title("Compiled Skode (.sk) Source Script"),
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
            attribute.title("Raw 50Hz SID Register Dump Text"),
          ],
          [text("📑 Raw SID Dump")],
        ),
      ],
    ]),
  )
}

fn view_tab_content(model: Model, song: DumpSong) -> Element(Msg) {
  html.div([class("tab-content-panel")], [
    case model.active_tab {
      "voices" -> view_tab_voices(model, song)
      "samples" -> view_tab_samples(model, song)
      "info" -> view_tab_info(model, song)
      "skode" -> view_tab_skode(model)
      "dump" -> view_tab_dump(model)
      _ -> view_tab_voices(model, song)
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

  let digi_card = case list.is_empty(song.digi_samples) {
    True -> []
    False -> [
      html.div([class("song-info-card digi-info-card")], [
        html.h3([class("card-title highlight-gold")], [
          text("🥁 Captured C64 PCM Digi Samples (Inline Skode Wavetables)"),
        ]),
        html.p([class("card-body-text")], [
          text(
            "This Commodore 64 tune features 4-bit nibble PCM sample playback (percussion / speech) driven by custom 6502 playroutines. During conversion, sid-to-skode detected zero-page sample vector updates ($04 sample pointer and $02 end boundary) and automatically extracted the raw sample bytes from C64 RAM. The nibbles are decoded, DC-centered, normalized to bipolar floating-point, and compiled directly as inline Skode wavetables (( ... ) /d <slot>,<rate>) inside the header. You can audition each sample below — preview triggers run on free Skred voices (v4–v7) without affecting the song!",
          ),
        ]),
        html.div([class("digi-samples-table-wrap")], [
          html.table([class("digi-samples-table mono")], [
            html.thead([], [
              html.tr([], [
                html.th([], [text("Slot")]),
                html.th([], [text("Wavetable")]),
                html.th([], [text("Length")]),
                html.th([], [text("Sample Rate")]),
                html.th([], [text("Duration")]),
                html.th([], [text("Song Hits")]),
                html.th([], [text("Audition")]),
              ]),
            ]),
            html.tbody(
              [],
              list.map(song.digi_samples, fn(s) {
                let trigger_count =
                  list.filter(song.digi_events, fn(ev) { ev.slot == s.slot })
                  |> list.length
                let duration_ms =
                  int.to_float(s.length)
                  *. 1000.0
                  /. s.rate
                html.tr([], [
                  html.td([class("highlight-cyan")], [
                    text("#" <> int.to_string(s.slot)),
                  ]),
                  html.td([class("highlight-yellow font-bold")], [
                    text("w" <> int.to_string(s.slot)),
                  ]),
                  html.td([], [text(int.to_string(s.length) <> " samples")]),
                  html.td([], [
                    text(converter.format_float(s.rate, 0) <> " Hz"),
                  ]),
                  html.td([], [
                    text(converter.format_float(duration_ms, 1) <> " ms"),
                  ]),
                  html.td([class("highlight-green")], [
                    text(int.to_string(trigger_count) <> " hits"),
                  ]),
                  html.td([], [
                    html.button(
                      [
                        class("btn btn-sm btn-audition-sm"),
                        event.on_click(AuditionSample(s.slot)),
                        attribute.title(
                          "Audition w"
                          <> int.to_string(s.slot)
                          <> " on free Skred voice",
                        ),
                      ],
                      [text("▶ Audition")],
                    ),
                  ]),
                ])
              }),
            ),
          ]),
        ]),
      ]),
    ]
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
        text("⚡ Dedicated Ksynth SID Waveform Model & Calibrated Headroom"),
      ]),
      html.p([class("card-body-text")], [
        text(
          "To authentically reproduce the warmth, harmonic richness, and punch of the Commodore 64 MOS SID (6581/8580), sid-to-skode executes inline Ksynth vector synthesis scripts inside the generated .sk file to build bandlimited oscillator wavetables:\n\n• w300 -> SID Bandlimited Triangle (true alternating odd harmonics 1/h^2)\n• w301 -> SID Bandlimited Sawtooth (64 harmonics 1/h)\n• w302 -> SID Bandlimited Square / Pulse with CZ phase-distortion PWM (c1,#)\n• w303 -> SID Combined Saw+Triangle ($30 hybrid)\n• w304 -> SID Combined Saw+Pulse ($60 hybrid)\n• w6   -> Live White Noise (Continuous Hardware Audio RNG, zero cyclic comb-filter buzz)\n\nGain Staging & Headroom: Voice amplitudes are calibrated with -8 dBFS per-voice nominal headroom (V -8 dB master) so that multi-oscillator summing and high-resonance biquad filter sweeps (j/k/q) never clip or produce ear-fatiguing distortion.",
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

  html.div(
    [class("info-tab-layout")],
    list.flatten([
      [view_metadata_bar(model, song)],
      archive_card,
      digi_card,
      base_cards,
    ]),
  )
}

fn sample_evenly(items: List(Float), count: Int) -> List(Float) {
  let len = list.length(items)
  case len <= count {
    True -> items
    False -> {
      let step = int.max(1, len / count)
      list.index_map(items, fn(x, i) { #(i, x) })
      |> list.filter(fn(pair) { pair.0 % step == 0 })
      |> list.take(count)
      |> list.map(fn(pair) { pair.1 })
    }
  }
}

fn view_mini_waveform(samples: List(Float)) -> Element(Msg) {
  let downsampled = sample_evenly(samples, 32)
  let bars =
    list.map(downsampled, fn(v) {
      let abs_val = float.min(1.0, float.max(0.1, float.absolute_value(v)))
      let pct = converter.format_float(abs_val *. 100.0, 0) <> "%"
      html.div([class("sample-wave-bar"), attribute.style("height", pct)], [])
    })
  html.div([class("sample-mini-waveform")], bars)
}

fn view_tab_samples(_model: Model, song: DumpSong) -> Element(Msg) {
  let sample_count = list.length(song.digi_samples)
  html.div([class("samples-tab-layout")], [
    html.div([class("song-info-card digi-info-card")], [
      html.div([class("samples-tab-header-row")], [
        html.div([class("samples-tab-title-group")], [
          html.h3([class("card-title highlight-gold")], [
            text(
              "🥁 Captured C64 PCM Digi Samples ("
              <> int.to_string(sample_count)
              <> ")",
            ),
          ]),
          html.span([class("samples-routing-badge")], [
            text("⚡ Free Voice Routing (v4–v7) · Isolated from Song"),
          ]),
        ]),
      ]),
      html.p([class("card-body-text")], [
        text(
          "This Commodore 64 tune features 4-bit nibble PCM sample playback (percussion / speech) driven by custom 6502 playroutines. During conversion, sid-to-skode detected zero-page sample vector updates ($04 sample pointer and $02 end boundary) and automatically extracted the raw sample bytes from C64 RAM. The nibbles are decoded, DC-centered, normalized to bipolar floating-point, and compiled directly as inline Skode wavetables (( ... ) /d <slot>,<rate>) inside the header. You can audition them with the buttons below — preview triggers run on free Skred voices (v4–v7) without affecting the song playback!",
        ),
      ]),
    ]),
    html.div(
      [class("samples-cards-grid")],
      list.map(song.digi_samples, fn(s) { view_sample_card(s, song) }),
    ),
  ])
}

fn view_sample_card(s: DigiSample, song: DumpSong) -> Element(Msg) {
  let trigger_count =
    list.filter(song.digi_events, fn(ev) { ev.slot == s.slot })
    |> list.length
  let duration_ms =
    int.to_float(s.length)
    *. 1000.0
    /. s.rate

  html.div([class("sample-audition-card")], [
    html.div([class("sample-card-top")], [
      html.div([class("sample-card-identity")], [
        html.span([class("sample-slot-badge highlight-yellow")], [
          text("w" <> int.to_string(s.slot)),
        ]),
        html.span([class("sample-slot-num mono")], [
          text("Slot #" <> int.to_string(s.slot)),
        ]),
      ]),
      html.button(
        [
          class("btn btn-success btn-audition"),
          event.on_click(AuditionSample(s.slot)),
          attribute.title(
            "Audition w"
            <> int.to_string(s.slot)
            <> " on free Skred voice (no song interference)",
          ),
        ],
        [text("▶ Audition w" <> int.to_string(s.slot))],
      ),
    ]),
    view_mini_waveform(s.samples),
    html.div([class("sample-card-specs")], [
      html.div([class("sample-spec-item")], [
        html.span([class("sample-spec-key")], [text("LENGTH")]),
        html.span([class("sample-spec-val mono")], [
          text(int.to_string(s.length) <> " samples"),
        ]),
      ]),
      html.div([class("sample-spec-item")], [
        html.span([class("sample-spec-key")], [text("SAMPLE RATE")]),
        html.span([class("sample-spec-val mono")], [
          text(converter.format_float(s.rate, 0) <> " Hz"),
        ]),
      ]),
      html.div([class("sample-spec-item")], [
        html.span([class("sample-spec-key")], [text("DURATION")]),
        html.span([class("sample-spec-val mono")], [
          text(converter.format_float(duration_ms, 1) <> " ms"),
        ]),
      ]),
      html.div([class("sample-spec-item")], [
        html.span([class("sample-spec-key")], [text("SONG HITS")]),
        html.span([class("sample-spec-val mono highlight-green")], [
          text(int.to_string(trigger_count) <> " hits"),
        ]),
      ]),
      html.div([class("sample-spec-item")], [
        html.span([class("sample-spec-key")], [text("ROUTING")]),
        html.span([class("sample-spec-val mono highlight-cyan")], [
          text("Free Voice v4–v7"),
        ]),
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
    view_register_strip(step_idx, song.frame_count, frame, song),
  ])
}

fn view_register_strip(
  step: Int,
  total: Int,
  frame: SidFrame,
  song: DumpSong,
) -> Element(Msg) {
  let v1 = frame.v1
  let v2 = frame.v2
  let v3 = frame.v3
  let flt = frame.filter

  let digi_block = case list.is_empty(song.digi_samples) {
    True -> []
    False -> {
      let #(hit_text, hit_changed) = case dict.get(song.digi_events_map, step) {
        Ok(slot) -> #("w" <> int.to_string(slot) <> " HIT", True)
        Error(_) -> #("Idle", False)
      }
      let sample_count = int.to_string(list.length(song.digi_samples))
      [
        reg_block("Digi $04 PCM", [
          reg_val("Status", hit_text, hit_changed),
          reg_val("Pool", sample_count <> " samples", False),
          reg_val("Rate", "6842 Hz", False),
          reg_val("Voice", "v3 (Track 3)", False),
        ]),
      ]
    }
  }

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
    html.div(
      [class("reg-blocks-row mono")],
      list.append(
        [
          reg_block(voice_reg_header("V1", "$D400", v1), [
            reg_val("Freq", "$" <> hex4(v1.freq), v1.freq_changed),
            reg_val("PW", "$" <> hex4(v1.pulse_width), v1.pulse_changed),
            reg_val("Ctrl", "$" <> hex2(v1.waveform_byte), v1.wave_changed),
            reg_val("ADSR", "$" <> hex4(v1.adsr), v1.adsr_changed),
          ]),
          reg_block(voice_reg_header("V2", "$D407", v2), [
            reg_val("Freq", "$" <> hex4(v2.freq), v2.freq_changed),
            reg_val("PW", "$" <> hex4(v2.pulse_width), v2.pulse_changed),
            reg_val("Ctrl", "$" <> hex2(v2.waveform_byte), v2.wave_changed),
            reg_val("ADSR", "$" <> hex4(v2.adsr), v2.adsr_changed),
          ]),
          reg_block(voice_reg_header("V3", "$D40E", v3), [
            reg_val("Freq", "$" <> hex4(v3.freq), v3.freq_changed),
            reg_val("PW", "$" <> hex4(v3.pulse_width), v3.pulse_changed),
            reg_val("Ctrl", "$" <> hex2(v3.waveform_byte), v3.wave_changed),
            reg_val("ADSR", "$" <> hex4(v3.adsr), v3.adsr_changed),
          ]),
          reg_block(filter_reg_header(flt), [
            reg_val("Cutoff", "$" <> hex4(flt.cutoff), flt.cutoff_changed),
            reg_val("Res/R", "$" <> hex2(flt.res_routing), flt.ctrl_changed),
            reg_val(
              "Mode/Vol",
              "$" <> hex2(flt.volume),
              flt.vol_changed || flt.mode_changed,
            ),
          ]),
        ],
        digi_block,
      ),
    ),
  ])
}

fn voice_reg_header(v_name: String, addr: String, vf: VoiceFrame) -> String {
  let is_tri = int.bitwise_and(vf.waveform_byte, 0x10) != 0
  let is_saw = int.bitwise_and(vf.waveform_byte, 0x20) != 0
  let is_pulse = int.bitwise_and(vf.waveform_byte, 0x40) != 0
  let is_noise = int.bitwise_and(vf.waveform_byte, 0x80) != 0

  let wave_str = case is_noise, is_saw, is_pulse, is_tri {
    True, _, _, _ -> "Noise"
    _, True, True, True -> "Tri+Saw+Pulse"
    _, True, True, False -> "Saw+Pulse"
    _, False, True, True -> "Tri+Pulse"
    _, True, False, True -> "Saw+Tri"
    _, True, False, False -> "Saw"
    _, False, True, False -> "Pulse"
    _, False, False, True -> "Tri"
    _, False, False, False -> "Off"
  }
  let gate_str = case vf.gate {
    True -> " [GATE]"
    False -> ""
  }
  v_name
  <> " "
  <> addr
  <> " · "
  <> vf.note_name
  <> " ("
  <> wave_str
  <> ")"
  <> gate_str
}

fn filter_reg_header(flt: FilterFrame) -> String {
  let route_str = case flt.route_v1, flt.route_v2, flt.route_v3 {
    True, True, True -> " (V1+V2+V3)"
    True, True, False -> " (V1+V2)"
    True, False, True -> " (V1+V3)"
    False, True, True -> " (V2+V3)"
    True, False, False -> " (V1)"
    False, True, False -> " (V2)"
    False, False, True -> " (V3)"
    _, _, _ -> ""
  }
  "FLT $D415 · " <> flt.mode_str <> route_str
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
    gate_triggered: False,
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

fn truncate_preview_lines(full_text: String, max_lines: Int) -> String {
  let lines = string.split(full_text, "\n")
  let count = list.length(lines)
  case count > max_lines {
    True -> {
      let preview =
        lines
        |> list.take(max_lines)
        |> string.join("\n")
      preview
      <> "\n\n# ... [Showing first "
      <> int.to_string(max_lines)
      <> " lines of "
      <> int.to_string(count)
      <> ". Use 'Copy Script' or 'Download .SK' for the complete file]"
    }
    False -> full_text
  }
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
          html.code([], [text(truncate_preview_lines(conv.skode_text, 400))]),
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
      html.code([], [text(truncate_preview_lines(model.raw_dump_text, 400))]),
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
