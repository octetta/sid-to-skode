import * as $float from "../gleam_stdlib/gleam/float.mjs";
import * as $int from "../gleam_stdlib/gleam/int.mjs";
import * as $option from "../gleam_stdlib/gleam/option.mjs";
import { Some, Option$None$const } from "../gleam_stdlib/gleam/option.mjs";
import * as $lustre from "../lustre/lustre.mjs";
import * as $attribute from "../lustre/lustre/attribute.mjs";
import { class$, href, target, type_, value } from "../lustre/lustre/attribute.mjs";
import * as $effect from "../lustre/lustre/effect.mjs";
import * as $element from "../lustre/lustre/element.mjs";
import { text } from "../lustre/lustre/element.mjs";
import * as $html from "../lustre/lustre/element/html.mjs";
import * as $event from "../lustre/lustre/event.mjs";
import {
  Ok,
  Error,
  List$Empty$const as $List$Empty$const,
  prepend as listPrepend,
  makeError,
} from "./gleam.mjs";
import * as $converter from "./sid_to_skode/converter.mjs";
import * as $dump_parser from "./sid_to_skode/dump_parser.mjs";
import * as $types from "./sid_to_skode/types.mjs";
import {
  CopySkodeToClipboard,
  DeepSidSearchResults,
  DeepSidTrackDownloaded,
  DownloadSkodeFile,
  EnginePlaybackEnded,
  EngineReady,
  EngineStepUpdated,
  LoadDeepSidTrack,
  Model,
  SearchDeepSid,
  StereoAmiga,
  StereoHeadphone,
  StereoMono,
  TabDeepSidBrowser,
  TabDumpView,
  TabSkodeSource,
  TabStudio,
  UserLoadedDump,
  UserSelectTab,
  UserSetStereo,
  UserSetVolume,
  UserTriggerPause,
  UserTriggerPlay,
  UserTriggerStop,
  ActiveTab$TabDumpView$const,
  ActiveTab$TabSkodeSource$const,
  ActiveTab$TabStudio$const,
  Msg$CopySkodeToClipboard$const,
  Msg$DismissError$const,
  Msg$DownloadSkodeFile$const,
  Msg$EnginePlaybackEnded$const,
  Msg$EngineReady$const,
  Msg$UserTriggerPause$const,
  Msg$UserTriggerPlay$const,
  Msg$UserTriggerStop$const,
  StereoProfile$StereoAmiga$const,
  StereoProfile$StereoHeadphone$const,
  StereoProfile$StereoMono$const,
} from "./sid_to_skode/types.mjs";
import {
  initEngine as js_init_engine,
  registerFileDrop as js_register_file_drop,
  playSkode as js_play_skode,
  pausePlayback as js_pause_playback,
  resumePlayback as js_resume_playback,
  stopPlayback as js_stop_playback,
  setVolume as js_set_volume,
  setStereoProfile as js_set_stereo_profile,
  registerPlaybackListener as js_register_playback_listener,
  fetchRandomDeepSid as js_fetch_random_deep_sid,
  copyToClipboard as js_copy_to_clipboard,
  downloadFile as js_download_file,
} from "./skred_ffi.mjs";

const FILEPATH = "src/sid_to_skode.gleam";

const commando_sample_snippet = "| Frame | Freq Note/Abs WF ADSR Pul | Freq Note/Abs WF ADSR Pul | Freq Note/Abs WF ADSR Pul | FCut RC Typ V |\n+-------+---------------------------+---------------------------+---------------------------+---------------+\n|     0 | 0116  ... ..  00 0000 0B8 | 0116  ... ..  00 0000 000 | 0000  ... ..  00 0000 068 | 0000 00 Off F |\n|     1 | AF58  E-7 D8  15 0DFB 180 | 2141  B-4 BB  43 0FC4 200 | 03A9  A-1 95  41 099F 168 | .... .. ... . |\n|     2 | ....  ... ..  80 .... ... | ....  ... ..  80 .... ... | ....  ... ..  .. .... 17E | .... .. ... . |\n|     3 | 0303 (F#1 92) .. .... ... | ....  ... ..  .. .... ... | ....  ... ..  .. .... 194 | .... .. ... . |\n|     4 | AF58 (E-7 D8) 14 .... ... | ....  ... ..  42 0000 ... | ....  ... ..  .. .... 1AA | .... .. ... . |\n|     5 | 0303 (F#1 92) .. .... ... | ....  ... ..  .. .... ... | ....  ... ..  .. .... 1C0 | .... .. ... . |\n|     6 | AF58 (E-7 D8) .. .... ... | ....  ... ..  .. .... ... | ....  ... ..  .. .... 1D6 | .... .. ... . |\n|     7 | 0305 (F#1 92) .. .... ... | 4315  B-5 C7  43 0FC4 ... | ....  ... ..  .. .... 1EC | .... .. ... . |\n|     8 | AF58 (E-7 D8) .. .... ... | ....  ... ..  80 .... ... | ....  ... ..  .. .... 102 | .... .. ... . |\n|     9 | 0305 (F#1 92) .. .... ... | ....  ... ..  .. .... ... | ....  ... ..  .. .... 118 | .... .. ... . |\n|    10 | AF58 (E-7 D8) .. 0000 ... | ....  ... ..  42 0000 ... | ....  ... ..  .. .... 12E | .... .. ... . |\n|    11 | 0305 (F#1 92) .. .... ... | ....  ... ..  .. .... ... | ....  ... ..  .. .... 144 | .... .. ... . |\n|    12 | AF58 (E-7 D8) .. .... ... | ....  ... ..  .. .... ... | ....  ... ..  .. .... 15A | .... .. ... . |\n|    13 | 7518  A-6 D1  15 0DFB ... | 4315  B-5 C7  43 0FC4 ... | ....  ... ..  .. .... 170 | .... .. ... . |\n|    14 | ....  ... ..  80 .... ... | ....  ... ..  80 .... ... | ....  ... ..  .. .... 186 | .... .. ... . |\n|    15 | EA30 (A-7 DD) .. .... ... | ....  ... ..  .. .... ... | ....  ... ..  .. .... 19C | .... .. ... . |\n|    16 | 7518 (A-6 D1) 14 .... ... | ....  ... ..  42 0000 ... | ....  ... ..  40 0000 1B2 | .... .. ... . |\n|    17 | EA30 (A-7 DD) .. .... ... | ....  ... ..  .. .... ... | ....  ... ..  .. .... 1C8 | .... .. ... . |\n|    18 | 7518 (A-6 D1) .. .... ... | ....  ... ..  .. .... ... | ....  ... ..  .. .... 1DE | .... .. ... . |\n|    19 | EA30 (A-7 DD) .. .... ... | 4315  B-5 C7  43 0FC4 ... | 0751  A-2 A1  41 099F ... | .... .. ... . |\n|    20 | 7518 (A-6 D1) .. .... ... | ....  ... ..  80 .... ... | ....  ... ..  .. .... 1F4 | .... .. ... . |\n|    21 | EA30 (A-7 DD) .. .... ... | ....  ... ..  .. .... ... | ....  ... ..  .. .... 10A | .... .. ... . |\n|    22 | 7518 (A-6 D1) .. 0000 ... | ....  ... ..  42 0000 ... | ....  ... ..  40 0000 120 | .... .. ... . |\n|    23 | EA30 (A-7 DD) .. .... ... | ....  ... ..  .. .... ... | ....  ... ..  .. .... 136 | .... .. ... . |\n|    24 | 7518 (A-6 D1) .. .... ... | ....  ... ..  .. .... ... | ....  ... ..  .. .... 14C | .... .. ... . |\n|    25 | 1D46  A-4 B9  41 064B ... | 15EB  E-4 B4  41 064B 180 | 0F82  A#3 AE  81 0A09 200 | .... .. ... . |\n|    26 | ....  ... ..  80 .... ... | ....  ... ..  80 .... ... | ....  ... ..  80 .... ... | .... .. ... . |\n|    27 | 3A8C (A-5 C5) .. .... ... | 2BD6 (E-5 C0) .. .... ... | 1F04 (A#4 BA) .. .... ... | .... .. ... . |\n|    28 | 1D46 (A-4 B9) 40 .... ... | 15EB (E-4 B4) 40 .... ... | 0F82 (A#3 AE) .. .... ... | .... .. ... . |\n|    29 | 3A8C (A-5 C5) .. .... ... | 2BD6 (E-5 C0) .. .... ... | 1F04 (A#4 BA) .. .... ... | .... .. ... . |\n|    30 | 1D46 (A-4 B9) .. .... ... | 15EB (E-4 B4) .. .... ... | 0F82 (A#3 AE) .. .... ... | .... .. ... . |\n";

function view_footer() {
  return $html.footer(
    listPrepend(class$("site-footer"), $List$Empty$const),
    listPrepend(
      $html.p(
        $List$Empty$const,
        listPrepend(
          text("sid-to-skode · Built with "),
          listPrepend(
            $html.a(
              listPrepend(
                href("https://gleam.run/"),
                listPrepend(target("_blank"), $List$Empty$const),
              ),
              listPrepend(text("Gleam"), $List$Empty$const),
            ),
            listPrepend(
              text(", "),
              listPrepend(
                $html.a(
                  listPrepend(
                    href("https://hexdocs.pm/lustre/"),
                    listPrepend(target("_blank"), $List$Empty$const),
                  ),
                  listPrepend(text("Lustre"), $List$Empty$const),
                ),
                listPrepend(
                  text(", and "),
                  listPrepend(
                    $html.a(
                      listPrepend(
                        href("https://github.com/octetta/pulp"),
                        listPrepend(target("_blank"), $List$Empty$const),
                      ),
                      listPrepend(text("Skred"), $List$Empty$const),
                    ),
                    listPrepend(
                      text(" by Joseph Stewart ("),
                      listPrepend(
                        $html.a(
                          listPrepend(
                            href("https://github.com/octetta"),
                            listPrepend(target("_blank"), $List$Empty$const),
                          ),
                          listPrepend(text("octetta"), $List$Empty$const),
                        ),
                        listPrepend(text(")."), $List$Empty$const),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      $List$Empty$const,
    ),
  );
}

function view_dump_text(model) {
  return $html.div(
    listPrepend(class$("card dump-view"), $List$Empty$const),
    listPrepend(
      $html.h3(
        $List$Empty$const,
        listPrepend(text("siddump Frame Table"), $List$Empty$const),
      ),
      listPrepend(
        $html.pre(
          listPrepend(class$("dump-pre"), $List$Empty$const),
          listPrepend(text(model.raw_dump_text), $List$Empty$const),
        ),
        $List$Empty$const,
      ),
    ),
  );
}

function view_deep_sid_browser(_) {
  return $html.div(
    listPrepend(class$("card"), $List$Empty$const),
    listPrepend(
      $html.h3(
        $List$Empty$const,
        listPrepend(
          text("Explore High Voltage SID Collection"),
          $List$Empty$const,
        ),
      ),
      listPrepend(
        $html.p(
          $List$Empty$const,
          listPrepend(
            text(
              "Search tunes by composer or title. Requires DeepSID CORS access.",
            ),
            $List$Empty$const,
          ),
        ),
        $List$Empty$const,
      ),
    ),
  );
}

function view_skode_source(model) {
  let $ = model.conversion;
  if ($ instanceof Some) {
    let conv = $[0];
    return $html.div(
      listPrepend(class$("code-view-container card"), $List$Empty$const),
      listPrepend(
        $html.div(
          listPrepend(class$("code-header"), $List$Empty$const),
          listPrepend(
            $html.span(
              $List$Empty$const,
              listPrepend(
                text(
                  ("Generated main.sk (" + $int.to_string(conv.step_count)) + " steps)",
                ),
                $List$Empty$const,
              ),
            ),
            listPrepend(
              $html.div(
                listPrepend(class$("code-actions"), $List$Empty$const),
                listPrepend(
                  $html.button(
                    listPrepend(
                      class$("btn btn-sm"),
                      listPrepend(
                        $event.on_click(Msg$CopySkodeToClipboard$const),
                        $List$Empty$const,
                      ),
                    ),
                    listPrepend(text("📋 Copy"), $List$Empty$const),
                  ),
                  listPrepend(
                    $html.button(
                      listPrepend(
                        class$("btn btn-sm"),
                        listPrepend(
                          $event.on_click(Msg$DownloadSkodeFile$const),
                          $List$Empty$const,
                        ),
                      ),
                      listPrepend(text("💾 Download .sk"), $List$Empty$const),
                    ),
                    $List$Empty$const,
                  ),
                ),
              ),
              $List$Empty$const,
            ),
          ),
        ),
        listPrepend(
          $html.textarea(
            listPrepend(
              class$("code-editor"),
              listPrepend(
                $attribute.readonly(true),
                listPrepend($attribute.rows(24), $List$Empty$const),
              ),
            ),
            conv.skode_code,
          ),
          $List$Empty$const,
        ),
      ),
    );
  } else {
    return $html.div(
      listPrepend(class$("card empty-state"), $List$Empty$const),
      listPrepend(
        text("No tune loaded. Load a SID dump to view generated Skode code."),
        $List$Empty$const,
      ),
    );
  }
}

function view_voice_card(_, label, v_cmd) {
  return $html.div(
    listPrepend(class$("voice-card card"), $List$Empty$const),
    listPrepend(
      $html.div(
        listPrepend(class$("voice-card-header"), $List$Empty$const),
        listPrepend(
          $html.h3(
            $List$Empty$const,
            listPrepend(text(label), $List$Empty$const),
          ),
          listPrepend(
            $html.span(
              listPrepend(class$("badge"), $List$Empty$const),
              listPrepend(text(v_cmd), $List$Empty$const),
            ),
            $List$Empty$const,
          ),
        ),
      ),
      listPrepend(
        $html.div(
          listPrepend(class$("voice-features"), $List$Empty$const),
          listPrepend(
            $html.div(
              listPrepend(class$("param-row"), $List$Empty$const),
              listPrepend(
                $html.span(
                  listPrepend(class$("param-name"), $List$Empty$const),
                  listPrepend(text("Waveform:"), $List$Empty$const),
                ),
                listPrepend(
                  $html.span(
                    listPrepend(class$("param-val"), $List$Empty$const),
                    listPrepend(
                      text("DWGS w15/w16/w18 & Noise"),
                      $List$Empty$const,
                    ),
                  ),
                  $List$Empty$const,
                ),
              ),
            ),
            listPrepend(
              $html.div(
                listPrepend(class$("param-row"), $List$Empty$const),
                listPrepend(
                  $html.span(
                    listPrepend(class$("param-name"), $List$Empty$const),
                    listPrepend(text("Modulation:"), $List$Empty$const),
                  ),
                  listPrepend(
                    $html.span(
                      listPrepend(class$("param-val"), $List$Empty$const),
                      listPrepend(
                        text("PWM (CZ c1) & Ring Mod (XM)"),
                        $List$Empty$const,
                      ),
                    ),
                    $List$Empty$const,
                  ),
                ),
              ),
              listPrepend(
                $html.div(
                  listPrepend(class$("param-row"), $List$Empty$const),
                  listPrepend(
                    $html.span(
                      listPrepend(class$("param-name"), $List$Empty$const),
                      listPrepend(text("Filter:"), $List$Empty$const),
                    ),
                    listPrepend(
                      $html.span(
                        listPrepend(class$("param-val"), $List$Empty$const),
                        listPrepend(
                          text("Multi-mode LP/HP/BP (j1..j4)"),
                          $List$Empty$const,
                        ),
                      ),
                      $List$Empty$const,
                    ),
                  ),
                ),
                $List$Empty$const,
              ),
            ),
          ),
        ),
        $List$Empty$const,
      ),
    ),
  );
}

function view_studio(model) {
  let $ = model.loaded_song;
  if ($ instanceof Some) {
    let song = $[0];
    return $html.div(
      listPrepend(class$("studio-rack"), $List$Empty$const),
      listPrepend(
        $html.div(
          listPrepend(class$("track-info card"), $List$Empty$const),
          listPrepend(
            $html.h2(
              $List$Empty$const,
              listPrepend(text("🎶 " + song.title), $List$Empty$const),
            ),
            listPrepend(
              $html.div(
                listPrepend(class$("meta-grid"), $List$Empty$const),
                listPrepend(
                  $html.div(
                    $List$Empty$const,
                    listPrepend(
                      text("Frames: " + $int.to_string(song.frame_count)),
                      $List$Empty$const,
                    ),
                  ),
                  listPrepend(
                    $html.div(
                      $List$Empty$const,
                      listPrepend(
                        text("Rate: 50.0 Hz (PAL)"),
                        $List$Empty$const,
                      ),
                    ),
                    listPrepend(
                      $html.div(
                        $List$Empty$const,
                        listPrepend(
                          text(
                            ("Duration: ~" + $float.to_string(
                              $int.to_float(song.frame_count) * 0.02,
                            )) + "s",
                          ),
                          $List$Empty$const,
                        ),
                      ),
                      listPrepend(
                        $html.div(
                          $List$Empty$const,
                          listPrepend(
                            text("Voices: 3 SID Oscillators"),
                            $List$Empty$const,
                          ),
                        ),
                        $List$Empty$const,
                      ),
                    ),
                  ),
                ),
              ),
              $List$Empty$const,
            ),
          ),
        ),
        listPrepend(
          $html.div(
            listPrepend(class$("voices-grid"), $List$Empty$const),
            listPrepend(
              view_voice_card(0, "Voice 1 (Left / Carrier)", "v0"),
              listPrepend(
                view_voice_card(1, "Voice 2 (Right / Lead)", "v1"),
                listPrepend(
                  view_voice_card(2, "Voice 3 (Center / Bass & Filter)", "v2"),
                  $List$Empty$const,
                ),
              ),
            ),
          ),
          $List$Empty$const,
        ),
      ),
    );
  } else {
    return $html.div(
      listPrepend(class$("dropzone-container card"), $List$Empty$const),
      listPrepend(
        $html.div(
          listPrepend(class$("dropzone"), $List$Empty$const),
          listPrepend(
            $html.h3(
              $List$Empty$const,
              listPrepend(
                text("Drag & Drop Any .sid or .dump File Here"),
                $List$Empty$const,
              ),
            ),
            listPrepend(
              $html.p(
                $List$Empty$const,
                listPrepend(
                  text(
                    "Or click '🎲 Random from DeepSID' in the transport bar to fetch an iconic C64 tune directly from the High Voltage SID Collection!",
                  ),
                  $List$Empty$const,
                ),
              ),
              listPrepend(
                $html.div(
                  listPrepend(class$("demo-buttons"), $List$Empty$const),
                  listPrepend(
                    $html.button(
                      listPrepend(
                        class$("btn btn-demo"),
                        listPrepend(
                          $event.on_click(
                            new UserLoadedDump(
                              "Commando (5s)",
                              commando_sample_snippet,
                            ),
                          ),
                          $List$Empty$const,
                        ),
                      ),
                      listPrepend(
                        text("Load Commando (5s Demo)"),
                        $List$Empty$const,
                      ),
                    ),
                    $List$Empty$const,
                  ),
                ),
                $List$Empty$const,
              ),
            ),
          ),
        ),
        $List$Empty$const,
      ),
    );
  }
}

function view_tab_switcher(model) {
  return $html.nav(
    listPrepend(class$("tab-bar"), $List$Empty$const),
    listPrepend(
      $html.button(
        listPrepend(
          class$(
            (() => {
              let $ = model.active_tab;
              if ($ instanceof TabStudio) {
                return "tab active";
              } else {
                return "tab";
              }
            })(),
          ),
          listPrepend(
            $event.on_click(new UserSelectTab(ActiveTab$TabStudio$const)),
            $List$Empty$const,
          ),
        ),
        listPrepend(text("🎛 Studio Voice Rack"), $List$Empty$const),
      ),
      listPrepend(
        $html.button(
          listPrepend(
            class$(
              (() => {
                let $ = model.active_tab;
                if ($ instanceof TabSkodeSource) {
                  return "tab active";
                } else {
                  return "tab";
                }
              })(),
            ),
            listPrepend(
              $event.on_click(new UserSelectTab(ActiveTab$TabSkodeSource$const)),
              $List$Empty$const,
            ),
          ),
          listPrepend(text("📝 Skode Script (.sk)"), $List$Empty$const),
        ),
        listPrepend(
          $html.button(
            listPrepend(
              class$(
                (() => {
                  let $ = model.active_tab;
                  if ($ instanceof TabDumpView) {
                    return "tab active";
                  } else {
                    return "tab";
                  }
                })(),
              ),
              listPrepend(
                $event.on_click(new UserSelectTab(ActiveTab$TabDumpView$const)),
                $List$Empty$const,
              ),
            ),
            listPrepend(text("📜 SID Dump Output"), $List$Empty$const),
          ),
          $List$Empty$const,
        ),
      ),
    ),
  );
}

function view_error_banner(err) {
  return $html.div(
    listPrepend(class$("banner banner-error"), $List$Empty$const),
    listPrepend(
      $html.span(
        $List$Empty$const,
        listPrepend(text("⚠️ " + err), $List$Empty$const),
      ),
      listPrepend(
        $html.button(
          listPrepend(
            class$("btn-close"),
            listPrepend(
              $event.on_click(Msg$DismissError$const),
              $List$Empty$const,
            ),
          ),
          listPrepend(text("✕"), $List$Empty$const),
        ),
        $List$Empty$const,
      ),
    ),
  );
}

function view_transport_bar(model) {
  return $html.section(
    listPrepend(class$("transport-bar card"), $List$Empty$const),
    listPrepend(
      $html.div(
        listPrepend(class$("controls-group"), $List$Empty$const),
        listPrepend(
          (() => {
            let $ = model.is_playing;
            if ($) {
              return $html.button(
                listPrepend(
                  class$("btn btn-pause"),
                  listPrepend(
                    $event.on_click(Msg$UserTriggerPause$const),
                    $List$Empty$const,
                  ),
                ),
                listPrepend(text("⏸ Pause"), $List$Empty$const),
              );
            } else {
              return $html.button(
                listPrepend(
                  class$("btn btn-play"),
                  listPrepend(
                    $attribute.disabled(
                      !model.engine_ready || $option.is_none(model.conversion),
                    ),
                    listPrepend(
                      $event.on_click(Msg$UserTriggerPlay$const),
                      $List$Empty$const,
                    ),
                  ),
                ),
                listPrepend(text("▶ Play"), $List$Empty$const),
              );
            }
          })(),
          listPrepend(
            $html.button(
              listPrepend(
                class$("btn btn-stop"),
                listPrepend(
                  $attribute.disabled(!model.is_playing && !model.is_paused),
                  listPrepend(
                    $event.on_click(Msg$UserTriggerStop$const),
                    $List$Empty$const,
                  ),
                ),
              ),
              listPrepend(text("⏹ Stop"), $List$Empty$const),
            ),
            listPrepend(
              $html.button(
                listPrepend(
                  class$("btn btn-random"),
                  listPrepend(
                    $event.on_click(new SearchDeepSid("random")),
                    listPrepend(
                      $attribute.disabled(model.is_searching),
                      $List$Empty$const,
                    ),
                  ),
                ),
                listPrepend(
                  (() => {
                    let $ = model.is_searching;
                    if ($) {
                      return text("⏳ Downloading from DeepSID...");
                    } else {
                      return text("🎲 Random from DeepSID");
                    }
                  })(),
                  $List$Empty$const,
                ),
              ),
              $List$Empty$const,
            ),
          ),
        ),
      ),
      listPrepend(
        $html.div(
          listPrepend(class$("volume-group"), $List$Empty$const),
          listPrepend(
            $html.label(
              $List$Empty$const,
              listPrepend(
                text(
                  ("Volume: " + $float.to_string(model.master_volume_db)) + " dB",
                ),
                $List$Empty$const,
              ),
            ),
            listPrepend(
              $html.input(
                listPrepend(
                  type_("range"),
                  listPrepend(
                    $attribute.min("-40"),
                    listPrepend(
                      $attribute.max("6"),
                      listPrepend(
                        $attribute.step("1"),
                        listPrepend(
                          value($float.to_string(model.master_volume_db)),
                          listPrepend(
                            $event.on_input(
                              (v) => {
                                let $ = $float.parse(v);
                                if ($ instanceof Ok) {
                                  let f = $[0];
                                  return new UserSetVolume(f);
                                } else {
                                  return new UserSetVolume(-6.0);
                                }
                              },
                            ),
                            $List$Empty$const,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              $List$Empty$const,
            ),
          ),
        ),
        listPrepend(
          $html.div(
            listPrepend(class$("stereo-group"), $List$Empty$const),
            listPrepend(
              $html.label(
                $List$Empty$const,
                listPrepend(text("Stereo: "), $List$Empty$const),
              ),
              listPrepend(
                $html.button(
                  listPrepend(
                    class$(
                      (() => {
                        let $ = model.stereo_profile;
                        if ($ instanceof StereoHeadphone) {
                          return "btn-opt active";
                        } else {
                          return "btn-opt";
                        }
                      })(),
                    ),
                    listPrepend(
                      $event.on_click(
                        new UserSetStereo(StereoProfile$StereoHeadphone$const),
                      ),
                      $List$Empty$const,
                    ),
                  ),
                  listPrepend(text("🎧 Headphone (75%)"), $List$Empty$const),
                ),
                listPrepend(
                  $html.button(
                    listPrepend(
                      class$(
                        (() => {
                          let $ = model.stereo_profile;
                          if ($ instanceof StereoAmiga) {
                            return "btn-opt active";
                          } else {
                            return "btn-opt";
                          }
                        })(),
                      ),
                      listPrepend(
                        $event.on_click(
                          new UserSetStereo(StereoProfile$StereoAmiga$const),
                        ),
                        $List$Empty$const,
                      ),
                    ),
                    listPrepend(text("🔊 Wide (100%)"), $List$Empty$const),
                  ),
                  listPrepend(
                    $html.button(
                      listPrepend(
                        class$(
                          (() => {
                            let $ = model.stereo_profile;
                            if ($ instanceof StereoMono) {
                              return "btn-opt active";
                            } else {
                              return "btn-opt";
                            }
                          })(),
                        ),
                        listPrepend(
                          $event.on_click(
                            new UserSetStereo(StereoProfile$StereoMono$const),
                          ),
                          $List$Empty$const,
                        ),
                      ),
                      listPrepend(text("📻 Mono"), $List$Empty$const),
                    ),
                    $List$Empty$const,
                  ),
                ),
              ),
            ),
          ),
          $List$Empty$const,
        ),
      ),
    ),
  );
}

function view_header() {
  return $html.header(
    listPrepend(class$("site-header"), $List$Empty$const),
    listPrepend(
      $html.div(
        listPrepend(class$("logo-title"), $List$Empty$const),
        listPrepend(
          $html.h1(
            $List$Empty$const,
            listPrepend(text("sid-to-skode"), $List$Empty$const),
          ),
          listPrepend(
            $html.span(
              listPrepend(class$("badge gleam-badge"), $List$Empty$const),
              listPrepend(text("Gleam"), $List$Empty$const),
            ),
            listPrepend(
              $html.span(
                listPrepend(class$("badge lustre-badge"), $List$Empty$const),
                listPrepend(text("Lustre"), $List$Empty$const),
              ),
              listPrepend(
                $html.span(
                  listPrepend(class$("badge skred-badge"), $List$Empty$const),
                  listPrepend(text("Skred 0.80.0"), $List$Empty$const),
                ),
                listPrepend(
                  $html.span(
                    listPrepend(class$("badge sid-badge"), $List$Empty$const),
                    listPrepend(text("MOS 6581/8580"), $List$Empty$const),
                  ),
                  $List$Empty$const,
                ),
              ),
            ),
          ),
        ),
      ),
      listPrepend(
        $html.p(
          listPrepend(class$("subtitle"), $List$Empty$const),
          listPrepend(
            text(
              "Commodore 64 SID register dump converter, interactive web studio & real-time WebAssembly synthesis engine.",
            ),
            $List$Empty$const,
          ),
        ),
        $List$Empty$const,
      ),
    ),
  );
}

export function view(model) {
  return $html.div(
    listPrepend(class$("app-container"), $List$Empty$const),
    listPrepend(
      view_header(),
      listPrepend(
        view_transport_bar(model),
        listPrepend(
          (() => {
            let $ = model.error_message;
            if ($ instanceof Some) {
              let err = $[0];
              return view_error_banner(err);
            } else {
              return $element.none();
            }
          })(),
          listPrepend(
            view_tab_switcher(model),
            listPrepend(
              (() => {
                let $ = model.active_tab;
                if ($ instanceof TabStudio) {
                  return view_studio(model);
                } else if ($ instanceof TabSkodeSource) {
                  return view_skode_source(model);
                } else if ($ instanceof TabDeepSidBrowser) {
                  return view_deep_sid_browser(model);
                } else {
                  return view_dump_text(model);
                }
              })(),
              listPrepend(view_footer(), $List$Empty$const),
            ),
          ),
        ),
      ),
    ),
  );
}

function stereo_to_int(mode) {
  if (mode instanceof StereoHeadphone) {
    return 0;
  } else if (mode instanceof StereoAmiga) {
    return 1;
  } else {
    return 2;
  }
}

function update(model, msg) {
  if (msg instanceof EngineReady) {
    return [
      new Model(
        true,
        model.is_playing,
        model.is_paused,
        model.current_step,
        model.total_steps,
        model.master_volume_db,
        model.stereo_profile,
        model.active_tab,
        model.loaded_song,
        model.conversion,
        model.is_converting,
        model.error_message,
        model.raw_dump_text,
        model.deep_sid_query,
        model.deep_sid_results,
        model.is_searching,
      ),
      $effect.none(),
    ];
  } else if (msg instanceof UserLoadedDump) {
    let name = msg.name;
    let content = msg.content;
    let $ = $dump_parser.parse_dump(content, name);
    if ($ instanceof Ok) {
      let song = $[0];
      let conversion = $converter.convert_song(song, model.stereo_profile);
      return [
        new Model(
          model.engine_ready,
          model.is_playing,
          model.is_paused,
          model.current_step,
          conversion.step_count,
          model.master_volume_db,
          model.stereo_profile,
          model.active_tab,
          new Some(song),
          new Some(conversion),
          model.is_converting,
          Option$None$const,
          content,
          model.deep_sid_query,
          model.deep_sid_results,
          model.is_searching,
        ),
        $effect.none(),
      ];
    } else {
      let err = $[0];
      return [
        new Model(
          model.engine_ready,
          model.is_playing,
          model.is_paused,
          model.current_step,
          model.total_steps,
          model.master_volume_db,
          model.stereo_profile,
          model.active_tab,
          model.loaded_song,
          model.conversion,
          model.is_converting,
          new Some(err),
          model.raw_dump_text,
          model.deep_sid_query,
          model.deep_sid_results,
          model.is_searching,
        ),
        $effect.none(),
      ];
    }
  } else if (msg instanceof UserTriggerPlay) {
    let $ = model.conversion;
    if ($ instanceof Some) {
      let conv = $[0];
      let $1 = model.is_paused;
      if ($1) {
        js_resume_playback();
        return [
          new Model(
            model.engine_ready,
            true,
            false,
            model.current_step,
            model.total_steps,
            model.master_volume_db,
            model.stereo_profile,
            model.active_tab,
            model.loaded_song,
            model.conversion,
            model.is_converting,
            model.error_message,
            model.raw_dump_text,
            model.deep_sid_query,
            model.deep_sid_results,
            model.is_searching,
          ),
          $effect.none(),
        ];
      } else {
        js_play_skode(conv.skode_code, conv.step_count);
        return [
          new Model(
            model.engine_ready,
            true,
            false,
            model.current_step,
            model.total_steps,
            model.master_volume_db,
            model.stereo_profile,
            model.active_tab,
            model.loaded_song,
            model.conversion,
            model.is_converting,
            model.error_message,
            model.raw_dump_text,
            model.deep_sid_query,
            model.deep_sid_results,
            model.is_searching,
          ),
          $effect.none(),
        ];
      }
    } else {
      return [model, $effect.none()];
    }
  } else if (msg instanceof UserTriggerPause) {
    js_pause_playback();
    return [
      new Model(
        model.engine_ready,
        false,
        true,
        model.current_step,
        model.total_steps,
        model.master_volume_db,
        model.stereo_profile,
        model.active_tab,
        model.loaded_song,
        model.conversion,
        model.is_converting,
        model.error_message,
        model.raw_dump_text,
        model.deep_sid_query,
        model.deep_sid_results,
        model.is_searching,
      ),
      $effect.none(),
    ];
  } else if (msg instanceof UserTriggerStop) {
    js_stop_playback();
    return [
      new Model(
        model.engine_ready,
        false,
        false,
        0,
        model.total_steps,
        model.master_volume_db,
        model.stereo_profile,
        model.active_tab,
        model.loaded_song,
        model.conversion,
        model.is_converting,
        model.error_message,
        model.raw_dump_text,
        model.deep_sid_query,
        model.deep_sid_results,
        model.is_searching,
      ),
      $effect.none(),
    ];
  } else if (msg instanceof UserSetStereo) {
    let mode = msg[0];
    js_set_stereo_profile(stereo_to_int(mode));
    let _block;
    let $ = model.loaded_song;
    if ($ instanceof Some) {
      let song = $[0];
      _block = new Some($converter.convert_song(song, mode));
    } else {
      _block = model.conversion;
    }
    let next_conversion = _block;
    return [
      new Model(
        model.engine_ready,
        model.is_playing,
        model.is_paused,
        model.current_step,
        model.total_steps,
        model.master_volume_db,
        mode,
        model.active_tab,
        model.loaded_song,
        next_conversion,
        model.is_converting,
        model.error_message,
        model.raw_dump_text,
        model.deep_sid_query,
        model.deep_sid_results,
        model.is_searching,
      ),
      $effect.none(),
    ];
  } else if (msg instanceof UserSetVolume) {
    let vol = msg[0];
    js_set_volume(vol);
    return [
      new Model(
        model.engine_ready,
        model.is_playing,
        model.is_paused,
        model.current_step,
        model.total_steps,
        vol,
        model.stereo_profile,
        model.active_tab,
        model.loaded_song,
        model.conversion,
        model.is_converting,
        model.error_message,
        model.raw_dump_text,
        model.deep_sid_query,
        model.deep_sid_results,
        model.is_searching,
      ),
      $effect.none(),
    ];
  } else if (msg instanceof UserSelectTab) {
    let tab = msg[0];
    return [
      new Model(
        model.engine_ready,
        model.is_playing,
        model.is_paused,
        model.current_step,
        model.total_steps,
        model.master_volume_db,
        model.stereo_profile,
        tab,
        model.loaded_song,
        model.conversion,
        model.is_converting,
        model.error_message,
        model.raw_dump_text,
        model.deep_sid_query,
        model.deep_sid_results,
        model.is_searching,
      ),
      $effect.none(),
    ];
  } else if (msg instanceof EngineStepUpdated) {
    let step = msg[0];
    return [
      new Model(
        model.engine_ready,
        model.is_playing,
        model.is_paused,
        step,
        model.total_steps,
        model.master_volume_db,
        model.stereo_profile,
        model.active_tab,
        model.loaded_song,
        model.conversion,
        model.is_converting,
        model.error_message,
        model.raw_dump_text,
        model.deep_sid_query,
        model.deep_sid_results,
        model.is_searching,
      ),
      $effect.none(),
    ];
  } else if (msg instanceof EnginePlaybackEnded) {
    return [
      new Model(
        model.engine_ready,
        false,
        false,
        0,
        model.total_steps,
        model.master_volume_db,
        model.stereo_profile,
        model.active_tab,
        model.loaded_song,
        model.conversion,
        model.is_converting,
        model.error_message,
        model.raw_dump_text,
        model.deep_sid_query,
        model.deep_sid_results,
        model.is_searching,
      ),
      $effect.none(),
    ];
  } else if (msg instanceof SearchDeepSid) {
    let effect = $effect.from(
      (dispatch) => {
        return js_fetch_random_deep_sid(
          (name, dump) => { return dispatch(new UserLoadedDump(name, dump)); },
          (err) => { return dispatch(new DeepSidSearchResults(new Error(err))); },
        );
      },
    );
    return [
      new Model(
        model.engine_ready,
        model.is_playing,
        model.is_paused,
        model.current_step,
        model.total_steps,
        model.master_volume_db,
        model.stereo_profile,
        model.active_tab,
        model.loaded_song,
        model.conversion,
        model.is_converting,
        model.error_message,
        model.raw_dump_text,
        model.deep_sid_query,
        model.deep_sid_results,
        true,
      ),
      effect,
    ];
  } else if (msg instanceof DeepSidSearchResults) {
    let res = msg[0];
    if (res instanceof Ok) {
      let tracks = res[0];
      return [
        new Model(
          model.engine_ready,
          model.is_playing,
          model.is_paused,
          model.current_step,
          model.total_steps,
          model.master_volume_db,
          model.stereo_profile,
          model.active_tab,
          model.loaded_song,
          model.conversion,
          model.is_converting,
          model.error_message,
          model.raw_dump_text,
          model.deep_sid_query,
          tracks,
          false,
        ),
        $effect.none(),
      ];
    } else {
      let err = res[0];
      return [
        new Model(
          model.engine_ready,
          model.is_playing,
          model.is_paused,
          model.current_step,
          model.total_steps,
          model.master_volume_db,
          model.stereo_profile,
          model.active_tab,
          model.loaded_song,
          model.conversion,
          model.is_converting,
          new Some(err),
          model.raw_dump_text,
          model.deep_sid_query,
          model.deep_sid_results,
          false,
        ),
        $effect.none(),
      ];
    }
  } else if (msg instanceof LoadDeepSidTrack) {
    return [model, $effect.none()];
  } else if (msg instanceof DeepSidTrackDownloaded) {
    let res = msg[0];
    if (res instanceof Ok) {
      return [model, $effect.none()];
    } else {
      let err = res[0];
      return [
        new Model(
          model.engine_ready,
          model.is_playing,
          model.is_paused,
          model.current_step,
          model.total_steps,
          model.master_volume_db,
          model.stereo_profile,
          model.active_tab,
          model.loaded_song,
          model.conversion,
          model.is_converting,
          new Some(err),
          model.raw_dump_text,
          model.deep_sid_query,
          model.deep_sid_results,
          model.is_searching,
        ),
        $effect.none(),
      ];
    }
  } else if (msg instanceof CopySkodeToClipboard) {
    let $ = model.conversion;
    if ($ instanceof Some) {
      let conv = $[0];
      js_copy_to_clipboard(conv.skode_code);
      return [model, $effect.none()];
    } else {
      return [model, $effect.none()];
    }
  } else if (msg instanceof DownloadSkodeFile) {
    let $ = model.conversion;
    if ($ instanceof Some) {
      let conv = $[0];
      js_download_file(conv.title + ".sk", conv.skode_code);
      return [model, $effect.none()];
    } else {
      return [model, $effect.none()];
    }
  } else {
    return [
      new Model(
        model.engine_ready,
        model.is_playing,
        model.is_paused,
        model.current_step,
        model.total_steps,
        model.master_volume_db,
        model.stereo_profile,
        model.active_tab,
        model.loaded_song,
        model.conversion,
        model.is_converting,
        Option$None$const,
        model.raw_dump_text,
        model.deep_sid_query,
        model.deep_sid_results,
        model.is_searching,
      ),
      $effect.none(),
    ];
  }
}

function init(_) {
  let model = new Model(
    false,
    false,
    false,
    0,
    0,
    -6.0,
    StereoProfile$StereoHeadphone$const,
    ActiveTab$TabStudio$const,
    Option$None$const,
    Option$None$const,
    false,
    Option$None$const,
    "",
    "",
    $List$Empty$const,
    false,
  );
  let effect = $effect.from(
    (dispatch) => {
      js_init_engine((_) => { return dispatch(Msg$EngineReady$const); });
      js_register_file_drop(
        (name, content) => {
          return dispatch(new UserLoadedDump(name, content));
        },
      );
      return js_register_playback_listener(
        (step) => { return dispatch(new EngineStepUpdated(step)); },
        () => { return dispatch(Msg$EnginePlaybackEnded$const); },
      );
    },
  );
  return [model, effect];
}

export function main() {
  let app = $lustre.application(init, update, view);
  let $ = $lustre.start(app, "#app", undefined);
  if (!($ instanceof Ok)) {
    throw makeError(
      "let_assert",
      FILEPATH,
      "sid_to_skode",
      77,
      "main",
      "Pattern match failed, no pattern matched the value.",
      {
        value: $,
        start: 2758,
        end: 2807,
        pattern_start: 2769,
        pattern_end: 2774
      }
    )
  }
  return undefined;
}
