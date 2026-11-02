//// Interactive Commodore 64 SID to Skode Converter and Web Studio
//// Written in pure Gleam and Lustre.

import gleam/float
import gleam/int
import gleam/option.{None, Some}
import lustre
import lustre/attribute.{class, href, target, type_, value}
import lustre/effect.{type Effect}
import lustre/element.{type Element, text}
import lustre/element/html
import lustre/event
import sid_to_skode/converter
import sid_to_skode/dump_parser
import sid_to_skode/types.{
  type Model, type Msg, type StereoProfile, CopySkodeToClipboard,
  DeepSidSearchResults, DeepSidTrackDownloaded, DismissError,
  DownloadSkodeFile, EnginePlaybackEnded, EngineReady, EngineStepUpdated,
  LoadDeepSidTrack, Model, SearchDeepSid, StereoAmiga, StereoHeadphone,
  StereoMono, TabDeepSidBrowser, TabDumpView, TabSkodeSource, TabStudio,
  UserLoadedDump, UserSelectTab, UserSetStereo, UserSetVolume,
  UserTriggerPause, UserTriggerPlay, UserTriggerStop,
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

@external(javascript, "./skred_ffi.mjs", "setVolume")
fn js_set_volume(vol: Float) -> Nil

@external(javascript, "./skred_ffi.mjs", "setStereoProfile")
fn js_set_stereo_profile(mode: Int) -> Nil

@external(javascript, "./skred_ffi.mjs", "registerPlaybackListener")
fn js_register_playback_listener(
  on_step: fn(Int) -> Nil,
  on_end: fn() -> Nil,
) -> Nil

@external(javascript, "./skred_ffi.mjs", "fetchRandomDeepSid")
fn js_fetch_random_deep_sid(
  on_success: fn(String, String) -> Nil,
  on_error: fn(String) -> Nil,
) -> Nil

@external(javascript, "./skred_ffi.mjs", "copyToClipboard")
fn js_copy_to_clipboard(content: String) -> Nil

@external(javascript, "./skred_ffi.mjs", "downloadFile")
fn js_download_file(filename: String, content: String) -> Nil

// ---------------------------------------------------------------------------
// Main & Lustre Initialization
// ---------------------------------------------------------------------------

pub fn main() {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

fn init(_flags) -> #(Model, Effect(Msg)) {
  let model =
    Model(
      engine_ready: False,
      is_playing: False,
      is_paused: False,
      current_step: 0,
      total_steps: 0,
      master_volume_db: -6.0,
      stereo_profile: StereoHeadphone,
      active_tab: TabStudio,
      loaded_song: None,
      conversion: None,
      is_converting: False,
      error_message: None,
      raw_dump_text: "",
      deep_sid_query: "",
      deep_sid_results: [],
      is_searching: False,
    )

  let effect =
    effect.from(fn(dispatch) {
      js_init_engine(fn(_ready) { dispatch(EngineReady) })
      js_register_file_drop(fn(name, content) {
        dispatch(UserLoadedDump(name, content))
      })
      js_register_playback_listener(
        fn(step) { dispatch(EngineStepUpdated(step)) },
        fn() { dispatch(EnginePlaybackEnded) },
      )
    })

  #(model, effect)
}

// ---------------------------------------------------------------------------
// Update & State Transitions
// ---------------------------------------------------------------------------

fn stereo_to_int(mode: StereoProfile) -> Int {
  case mode {
    StereoHeadphone -> 0
    StereoAmiga -> 1
    StereoMono -> 2
  }
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    EngineReady -> #(Model(..model, engine_ready: True), effect.none())

    UserLoadedDump(name, content) -> {
      case dump_parser.parse_dump(content, name) {
        Ok(song) -> {
          let conversion = converter.convert_song(song, model.stereo_profile)
          #(
            Model(
              ..model,
              loaded_song: Some(song),
              conversion: Some(conversion),
              total_steps: conversion.step_count,
              raw_dump_text: content,
              error_message: None,
            ),
            effect.none(),
          )
        }
        Error(err) -> #(
          Model(..model, error_message: Some(err)),
          effect.none(),
        )
      }
    }

    UserTriggerPlay -> {
      case model.conversion {
        Some(conv) -> {
          case model.is_paused {
            True -> {
              js_resume_playback()
              #(Model(..model, is_playing: True, is_paused: False), effect.none())
            }
            False -> {
              js_play_skode(conv.skode_code, conv.step_count)
              #(Model(..model, is_playing: True, is_paused: False), effect.none())
            }
          }
        }
        None -> #(model, effect.none())
      }
    }

    UserTriggerPause -> {
      js_pause_playback()
      #(Model(..model, is_playing: False, is_paused: True), effect.none())
    }

    UserTriggerStop -> {
      js_stop_playback()
      #(
        Model(..model, is_playing: False, is_paused: False, current_step: 0),
        effect.none(),
      )
    }

    UserSetStereo(mode) -> {
      js_set_stereo_profile(stereo_to_int(mode))
      let next_conversion = case model.loaded_song {
        Some(song) -> Some(converter.convert_song(song, mode))
        None -> model.conversion
      }
      #(
        Model(..model, stereo_profile: mode, conversion: next_conversion),
        effect.none(),
      )
    }

    UserSetVolume(vol) -> {
      js_set_volume(vol)
      #(Model(..model, master_volume_db: vol), effect.none())
    }

    UserSelectTab(tab) -> #(Model(..model, active_tab: tab), effect.none())

    EngineStepUpdated(step) -> #(
      Model(..model, current_step: step),
      effect.none(),
    )

    EnginePlaybackEnded -> #(
      Model(..model, is_playing: False, is_paused: False, current_step: 0),
      effect.none(),
    )

    SearchDeepSid(_q) -> {
      let effect =
        effect.from(fn(dispatch) {
          js_fetch_random_deep_sid(
            fn(name, dump) { dispatch(UserLoadedDump(name, dump)) },
            fn(err) {
              dispatch(DeepSidSearchResults(Error(err)))
            },
          )
        })
      #(Model(..model, is_searching: True), effect)
    }

    DeepSidSearchResults(res) -> {
      case res {
        Ok(tracks) -> #(
          Model(..model, deep_sid_results: tracks, is_searching: False),
          effect.none(),
        )
        Error(err) -> #(
          Model(..model, error_message: Some(err), is_searching: False),
          effect.none(),
        )
      }
    }

    LoadDeepSidTrack(_track) -> #(model, effect.none())

    DeepSidTrackDownloaded(res) -> {
      case res {
        Ok(_) -> #(model, effect.none())
        Error(err) -> #(
          Model(..model, error_message: Some(err)),
          effect.none(),
        )
      }
    }

    CopySkodeToClipboard -> {
      case model.conversion {
        Some(conv) -> {
          js_copy_to_clipboard(conv.skode_code)
          #(model, effect.none())
        }
        None -> #(model, effect.none())
      }
    }

    DownloadSkodeFile -> {
      case model.conversion {
        Some(conv) -> {
          js_download_file(conv.title <> ".sk", conv.skode_code)
          #(model, effect.none())
        }
        None -> #(model, effect.none())
      }
    }

    DismissError -> #(Model(..model, error_message: None), effect.none())
  }
}

// ---------------------------------------------------------------------------
// View & Declarative UI
// ---------------------------------------------------------------------------

pub fn view(model: Model) -> Element(Msg) {
  html.div([class("app-container")], [
    view_header(),
    view_transport_bar(model),
    case model.error_message {
      Some(err) -> view_error_banner(err)
      None -> element.none()
    },
    view_tab_switcher(model),
    case model.active_tab {
      TabStudio -> view_studio(model)
      TabSkodeSource -> view_skode_source(model)
      TabDeepSidBrowser -> view_deep_sid_browser(model)
      TabDumpView -> view_dump_text(model)
    },
    view_footer(),
  ])
}

fn view_header() -> Element(Msg) {
  html.header([class("site-header")], [
    html.div([class("logo-title")], [
      html.h1([], [text("sid-to-skode")]),
      html.span([class("badge gleam-badge")], [text("Gleam")]),
      html.span([class("badge lustre-badge")], [text("Lustre")]),
      html.span([class("badge skred-badge")], [text("Skred 0.80.0")]),
      html.span([class("badge sid-badge")], [text("MOS 6581/8580")]),
    ]),
    html.p([class("subtitle")], [
      text(
        "Commodore 64 SID register dump converter, interactive web studio & real-time WebAssembly synthesis engine.",
      ),
    ]),
  ])
}

fn view_transport_bar(model: Model) -> Element(Msg) {
  html.section([class("transport-bar card")], [
    html.div([class("controls-group")], [
      case model.is_playing {
        True ->
          html.button([class("btn btn-pause"), event.on_click(UserTriggerPause)], [
            text("⏸ Pause"),
          ])
        False ->
          html.button(
            [
              class("btn btn-play"),
              attribute.disabled(!model.engine_ready || option.is_none(model.conversion)),
              event.on_click(UserTriggerPlay),
            ],
            [text("▶ Play")],
          )
      },
      html.button(
        [
          class("btn btn-stop"),
          attribute.disabled(!model.is_playing && !model.is_paused),
          event.on_click(UserTriggerStop),
        ],
        [text("⏹ Stop")],
      ),
      html.button(
        [
          class("btn btn-random"),
          event.on_click(SearchDeepSid("random")),
          attribute.disabled(model.is_searching),
        ],
        [
          case model.is_searching {
            True -> text("⏳ Downloading from DeepSID...")
            False -> text("🎲 Random from DeepSID")
          },
        ],
      ),
    ]),
    html.div([class("volume-group")], [
      html.label([], [text("Volume: " <> float.to_string(model.master_volume_db) <> " dB")]),
      html.input([
        type_("range"),
        attribute.min("-40"),
        attribute.max("6"),
        attribute.step("1"),
        value(float.to_string(model.master_volume_db)),
        event.on_input(fn(v) {
          case float.parse(v) {
            Ok(f) -> UserSetVolume(f)
            Error(_) -> UserSetVolume(-6.0)
          }
        }),
      ]),
    ]),
    html.div([class("stereo-group")], [
      html.label([], [text("Stereo: ")]),
      html.button(
        [
          class(case model.stereo_profile {
            StereoHeadphone -> "btn-opt active"
            _ -> "btn-opt"
          }),
          event.on_click(UserSetStereo(StereoHeadphone)),
        ],
        [text("🎧 Headphone (75%)")],
      ),
      html.button(
        [
          class(case model.stereo_profile {
            StereoAmiga -> "btn-opt active"
            _ -> "btn-opt"
          }),
          event.on_click(UserSetStereo(StereoAmiga)),
        ],
        [text("🔊 Wide (100%)")],
      ),
      html.button(
        [
          class(case model.stereo_profile {
            StereoMono -> "btn-opt active"
            _ -> "btn-opt"
          }),
          event.on_click(UserSetStereo(StereoMono)),
        ],
        [text("📻 Mono")],
      ),
    ]),
  ])
}

fn view_error_banner(err: String) -> Element(Msg) {
  html.div([class("banner banner-error")], [
    html.span([], [text("⚠️ " <> err)]),
    html.button([class("btn-close"), event.on_click(DismissError)], [text("✕")]),
  ])
}

fn view_tab_switcher(model: Model) -> Element(Msg) {
  html.nav([class("tab-bar")], [
    html.button(
      [
        class(case model.active_tab {
          TabStudio -> "tab active"
          _ -> "tab"
        }),
        event.on_click(UserSelectTab(TabStudio)),
      ],
      [text("🎛 Studio Voice Rack")],
    ),
    html.button(
      [
        class(case model.active_tab {
          TabSkodeSource -> "tab active"
          _ -> "tab"
        }),
        event.on_click(UserSelectTab(TabSkodeSource)),
      ],
      [text("📝 Skode Script (.sk)")],
    ),
    html.button(
      [
        class(case model.active_tab {
          TabDumpView -> "tab active"
          _ -> "tab"
        }),
        event.on_click(UserSelectTab(TabDumpView)),
      ],
      [text("📜 SID Dump Output")],
    ),
  ])
}

fn view_studio(model: Model) -> Element(Msg) {
  case model.loaded_song {
    None ->
      html.div([class("dropzone-container card")], [
        html.div([class("dropzone")], [
          html.h3([], [text("Drag & Drop Any .sid or .dump File Here")]),
          html.p([], [
            text(
              "Or click '🎲 Random from DeepSID' in the transport bar to fetch an iconic C64 tune directly from the High Voltage SID Collection!",
            ),
          ]),
          html.div([class("demo-buttons")], [
            html.button(
              [
                class("btn btn-demo"),
                event.on_click(UserLoadedDump("Commando (5s)", commando_sample_snippet)),
              ],
              [text("Load Commando (5s Demo)")],
            ),
          ]),
        ]),
      ])
    Some(song) -> {
      html.div([class("studio-rack")], [
        html.div([class("track-info card")], [
          html.h2([], [text("🎶 " <> song.title)]),
          html.div([class("meta-grid")], [
            html.div([], [text("Frames: " <> int.to_string(song.frame_count))]),
            html.div([], [text("Rate: 50.0 Hz (PAL)")]),
            html.div([], [
              text(
                "Duration: ~"
                <> float.to_string(int.to_float(song.frame_count) *. 0.02)
                <> "s",
              ),
            ]),
            html.div([], [text("Voices: 3 SID Oscillators")]),
          ]),
        ]),
        html.div([class("voices-grid")], [
          view_voice_card(0, "Voice 1 (Left / Carrier)", "v0"),
          view_voice_card(1, "Voice 2 (Right / Lead)", "v1"),
          view_voice_card(2, "Voice 3 (Center / Bass & Filter)", "v2"),
        ]),
      ])
    }
  }
}

fn view_voice_card(_idx: Int, label: String, v_cmd: String) -> Element(Msg) {
  html.div([class("voice-card card")], [
    html.div([class("voice-card-header")], [
      html.h3([], [text(label)]),
      html.span([class("badge")], [text(v_cmd)]),
    ]),
    html.div([class("voice-features")], [
      html.div([class("param-row")], [
        html.span([class("param-name")], [text("Waveform:")]),
        html.span([class("param-val")], [text("DWGS w15/w16/w18 & Noise")]),
      ]),
      html.div([class("param-row")], [
        html.span([class("param-name")], [text("Modulation:")]),
        html.span([class("param-val")], [text("PWM (CZ c1) & Ring Mod (XM)")]),
      ]),
      html.div([class("param-row")], [
        html.span([class("param-name")], [text("Filter:")]),
        html.span([class("param-val")], [text("Multi-mode LP/HP/BP (j1..j4)")]),
      ]),
    ]),
  ])
}

fn view_skode_source(model: Model) -> Element(Msg) {
  case model.conversion {
    None ->
      html.div([class("card empty-state")], [
        text("No tune loaded. Load a SID dump to view generated Skode code."),
      ])
    Some(conv) ->
      html.div([class("code-view-container card")], [
        html.div([class("code-header")], [
          html.span([], [text("Generated main.sk (" <> int.to_string(conv.step_count) <> " steps)")]),
          html.div([class("code-actions")], [
            html.button([class("btn btn-sm"), event.on_click(CopySkodeToClipboard)], [
              text("📋 Copy"),
            ]),
            html.button([class("btn btn-sm"), event.on_click(DownloadSkodeFile)], [
              text("💾 Download .sk"),
            ]),
          ]),
        ]),
        html.textarea(
          [class("code-editor"), attribute.readonly(True), attribute.rows(24)],
          conv.skode_code,
        ),
      ])
  }
}

fn view_dump_text(model: Model) -> Element(Msg) {
  html.div([class("card dump-view")], [
    html.h3([], [text("siddump Frame Table")]),
    html.pre([class("dump-pre")], [text(model.raw_dump_text)]),
  ])
}

fn view_deep_sid_browser(_model: Model) -> Element(Msg) {
  html.div([class("card")], [
    html.h3([], [text("Explore High Voltage SID Collection")]),
    html.p([], [
      text(
        "Search tunes by composer or title. Requires DeepSID CORS access.",
      ),
    ]),
  ])
}

fn view_footer() -> Element(Msg) {
  html.footer([class("site-footer")], [
    html.p([], [
      text("sid-to-skode · Built with "),
      html.a([href("https://gleam.run/"), target("_blank")], [text("Gleam")]),
      text(", "),
      html.a([href("https://hexdocs.pm/lustre/"), target("_blank")], [text("Lustre")]),
      text(", and "),
      html.a([href("https://github.com/octetta/pulp"), target("_blank")], [text("Skred")]),
      text(" by Joseph Stewart ("),
      html.a([href("https://github.com/octetta"), target("_blank")], [text("octetta")]),
      text(")."),
    ]),
  ])
}

const commando_sample_snippet: String = "| Frame | Freq Note/Abs WF ADSR Pul | Freq Note/Abs WF ADSR Pul | Freq Note/Abs WF ADSR Pul | FCut RC Typ V |
+-------+---------------------------+---------------------------+---------------------------+---------------+
|     0 | 0116  ... ..  00 0000 0B8 | 0116  ... ..  00 0000 000 | 0000  ... ..  00 0000 068 | 0000 00 Off F |
|     1 | AF58  E-7 D8  15 0DFB 180 | 2141  B-4 BB  43 0FC4 200 | 03A9  A-1 95  41 099F 168 | .... .. ... . |
|     2 | ....  ... ..  80 .... ... | ....  ... ..  80 .... ... | ....  ... ..  .. .... 17E | .... .. ... . |
|     3 | 0303 (F#1 92) .. .... ... | ....  ... ..  .. .... ... | ....  ... ..  .. .... 194 | .... .. ... . |
|     4 | AF58 (E-7 D8) 14 .... ... | ....  ... ..  42 0000 ... | ....  ... ..  .. .... 1AA | .... .. ... . |
|     5 | 0303 (F#1 92) .. .... ... | ....  ... ..  .. .... ... | ....  ... ..  .. .... 1C0 | .... .. ... . |
|     6 | AF58 (E-7 D8) .. .... ... | ....  ... ..  .. .... ... | ....  ... ..  .. .... 1D6 | .... .. ... . |
|     7 | 0305 (F#1 92) .. .... ... | 4315  B-5 C7  43 0FC4 ... | ....  ... ..  .. .... 1EC | .... .. ... . |
|     8 | AF58 (E-7 D8) .. .... ... | ....  ... ..  80 .... ... | ....  ... ..  .. .... 102 | .... .. ... . |
|     9 | 0305 (F#1 92) .. .... ... | ....  ... ..  .. .... ... | ....  ... ..  .. .... 118 | .... .. ... . |
|    10 | AF58 (E-7 D8) .. 0000 ... | ....  ... ..  42 0000 ... | ....  ... ..  .. .... 12E | .... .. ... . |
|    11 | 0305 (F#1 92) .. .... ... | ....  ... ..  .. .... ... | ....  ... ..  .. .... 144 | .... .. ... . |
|    12 | AF58 (E-7 D8) .. .... ... | ....  ... ..  .. .... ... | ....  ... ..  .. .... 15A | .... .. ... . |
|    13 | 7518  A-6 D1  15 0DFB ... | 4315  B-5 C7  43 0FC4 ... | ....  ... ..  .. .... 170 | .... .. ... . |
|    14 | ....  ... ..  80 .... ... | ....  ... ..  80 .... ... | ....  ... ..  .. .... 186 | .... .. ... . |
|    15 | EA30 (A-7 DD) .. .... ... | ....  ... ..  .. .... ... | ....  ... ..  .. .... 19C | .... .. ... . |
|    16 | 7518 (A-6 D1) 14 .... ... | ....  ... ..  42 0000 ... | ....  ... ..  40 0000 1B2 | .... .. ... . |
|    17 | EA30 (A-7 DD) .. .... ... | ....  ... ..  .. .... ... | ....  ... ..  .. .... 1C8 | .... .. ... . |
|    18 | 7518 (A-6 D1) .. .... ... | ....  ... ..  .. .... ... | ....  ... ..  .. .... 1DE | .... .. ... . |
|    19 | EA30 (A-7 DD) .. .... ... | 4315  B-5 C7  43 0FC4 ... | 0751  A-2 A1  41 099F ... | .... .. ... . |
|    20 | 7518 (A-6 D1) .. .... ... | ....  ... ..  80 .... ... | ....  ... ..  .. .... 1F4 | .... .. ... . |
|    21 | EA30 (A-7 DD) .. .... ... | ....  ... ..  .. .... ... | ....  ... ..  .. .... 10A | .... .. ... . |
|    22 | 7518 (A-6 D1) .. 0000 ... | ....  ... ..  42 0000 ... | ....  ... ..  40 0000 120 | .... .. ... . |
|    23 | EA30 (A-7 DD) .. .... ... | ....  ... ..  .. .... ... | ....  ... ..  .. .... 136 | .... .. ... . |
|    24 | 7518 (A-6 D1) .. .... ... | ....  ... ..  .. .... ... | ....  ... ..  .. .... 14C | .... .. ... . |
|    25 | 1D46  A-4 B9  41 064B ... | 15EB  E-4 B4  41 064B 180 | 0F82  A#3 AE  81 0A09 200 | .... .. ... . |
|    26 | ....  ... ..  80 .... ... | ....  ... ..  80 .... ... | ....  ... ..  80 .... ... | .... .. ... . |
|    27 | 3A8C (A-5 C5) .. .... ... | 2BD6 (E-5 C0) .. .... ... | 1F04 (A#4 BA) .. .... ... | .... .. ... . |
|    28 | 1D46 (A-4 B9) 40 .... ... | 15EB (E-4 B4) 40 .... ... | 0F82 (A#3 AE) .. .... ... | .... .. ... . |
|    29 | 3A8C (A-5 C5) .. .... ... | 2BD6 (E-5 C0) .. .... ... | 1F04 (A#4 BA) .. .... ... | .... .. ... . |
|    30 | 1D46 (A-4 B9) .. .... ... | 15EB (E-4 B4) .. .... ... | 0F82 (A#3 AE) .. .... ... | .... .. ... . |
"
