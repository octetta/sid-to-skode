//// Compiles parsed SID dumps into clean, idiomatic Skode 0.80.0 scripts.

import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/string
import sid_to_skode/types.{
  type ConversionResult, type DumpSong, type FilterFrame, type SidFrame,
  type StereoMode, type VoiceFrame, ConversionResult, StereoHeadphone,
  StereoMono, StereoWide,
}

pub fn make_range(start: Int, end: Int) -> List(Int) {
  case start <= end {
    True -> [start, ..make_range(start + 1, end)]
    False -> []
  }
}

pub fn format_duration(seconds: Float) -> String {
  let total_secs = float.truncate(seconds)
  let mins = total_secs / 60
  let secs = total_secs % 60
  let mins_str = case mins < 10 {
    True -> "0" <> int.to_string(mins)
    False -> int.to_string(mins)
  }
  let secs_str = case secs < 10 {
    True -> "0" <> int.to_string(secs)
    False -> int.to_string(secs)
  }
  mins_str <> ":" <> secs_str
}

const sid_attack_table: List(Float) = [
  0.002, 0.008, 0.016, 0.024, 0.038, 0.056, 0.068, 0.08, 0.1, 0.25, 0.5, 0.8,
  1.0, 3.0, 5.0, 8.0,
]

const sid_decay_table: List(Float) = [
  0.006, 0.024, 0.048, 0.072, 0.114, 0.168, 0.204, 0.24, 0.3, 0.75, 1.5, 2.4,
  3.0, 9.0, 15.0, 24.0,
]

fn lookup_table(tbl: List(Float), index: Int, default: Float) -> Float {
  case list.drop(tbl, index) {
    [val, ..] -> val
    [] -> default
  }
}

pub fn freq_to_hz(freq: Int) -> Float {
  // PAL C64 clock: 985248.4 Hz / 16777216.0 ≈ 0.0587285 Hz per frequency unit
  int.to_float(freq) *. 0.0587285
}

pub fn pulse_to_cz(pulse: Int) -> Float {
  // 12-bit pulse (0..4095), 2048 is 50% square (cz = 0.0)
  let norm = { int.to_float(pulse) -. 2048.0 } /. 2048.0
  case norm {
    _ if norm >. 0.98 -> 0.98
    _ if norm <. -0.98 -> -0.98
    _ -> norm
  }
}

pub fn cutoff_to_hz(cutoff: Int) -> Float {
  // SID 11-bit filter cutoff (0..2047) roughly covers 30Hz to 12kHz
  30.0 +. { int.to_float(cutoff) *. 5.8 }
}

pub fn res_to_q(res: Int) -> Float {
  // 4-bit resonance (0..15) -> Q from 0.707 to 7.0
  0.707 +. { int.to_float(res) *. 0.42 }
}

pub fn format_float(val: Float, decimals: Int) -> String {
  let factor = case decimals {
    1 -> 10.0
    2 -> 100.0
    3 -> 1000.0
    _ -> 100.0
  }
  let rounded = float.round(val *. factor)
  let whole = rounded / float.round(factor)
  let frac = int.absolute_value(rounded % float.round(factor))
  let frac_str = case frac < 10 && decimals > 1 {
    True -> "0" <> int.to_string(frac)
    False -> int.to_string(frac)
  }
  int.to_string(whole) <> "." <> frac_str
}

pub type VoiceTracker {
  VoiceTracker(
    last_freq: Int,
    last_wave: Int,
    last_adsr: Int,
    last_pulse: Int,
    last_gate: Bool,
    last_ring: Bool,
  )
}

pub fn init_tracker() -> VoiceTracker {
  VoiceTracker(
    last_freq: -1,
    last_wave: -1,
    last_adsr: -1,
    last_pulse: -1,
    last_gate: False,
    last_ring: False,
  )
}

pub type FilterTracker {
  FilterTracker(
    last_cutoff: Int,
    last_res: Int,
    last_mode: String,
    last_vol: Int,
    last_route_v1: Bool,
    last_route_v2: Bool,
    last_route_v3: Bool,
  )
}

pub fn init_filter_tracker() -> FilterTracker {
  FilterTracker(
    last_cutoff: -1,
    last_res: -1,
    last_mode: "",
    last_vol: -1,
    last_route_v1: False,
    last_route_v2: False,
    last_route_v3: False,
  )
}

fn wave_opcode(wave_byte: Int) -> String {
  let is_tri = int.bitwise_and(wave_byte, 0x10) != 0
  let is_saw = int.bitwise_and(wave_byte, 0x20) != 0
  let is_pulse = int.bitwise_and(wave_byte, 0x40) != 0
  let is_noise = int.bitwise_and(wave_byte, 0x80) != 0

  case is_noise, is_saw, is_pulse, is_tri {
    True, _, _, _ -> "w5"
    _, True, _, _ -> "w3"
    _, _, True, _ -> "w1"
    _, _, _, True -> "w4"
    _, _, _, _ -> "w1"
  }
}



/// Generates space-separated Skode command tokens for a voice frame.
/// Pattern remembers the selected voice, so voice selection is not repeated.
fn generate_voice_step_tokens(
  vf: VoiceFrame,
  tracker: VoiceTracker,
  _mod_voice: Int,
) -> #(List(String), VoiceTracker) {
  let tokens = []

  // Waveform changed
  let #(tokens, next_wave) = case vf.waveform_byte != tracker.last_wave {
    True -> #([wave_opcode(vf.waveform_byte), ..tokens], vf.waveform_byte)
    False -> #(tokens, tracker.last_wave)
  }

  // Pulse width changed (for pulse wave w16)
  let is_pulse = int.bitwise_and(vf.waveform_byte, 0x40) != 0
  let #(tokens, next_pulse) = case
    is_pulse && vf.pulse_width != tracker.last_pulse
  {
    True -> #(
      ["c1," <> format_float(pulse_to_cz(vf.pulse_width), 3), ..tokens],
      vf.pulse_width,
    )
    False -> #(tokens, tracker.last_pulse)
  }

  // ADSR envelope changed
  let #(tokens, next_adsr) = case vf.adsr != tracker.last_adsr {
    True -> {
      let a_sec = lookup_table(sid_attack_table, vf.attack, 0.002)
      let d_sec = lookup_table(sid_decay_table, vf.decay, 0.006)
      let s_lvl = int.to_float(vf.sustain) /. 15.0
      let r_sec = lookup_table(sid_decay_table, vf.release, 0.006)
      let adsr_str =
        "t"
        <> format_float(a_sec, 3)
        <> ","
        <> format_float(d_sec, 3)
        <> ","
        <> format_float(s_lvl, 2)
        <> ","
        <> format_float(r_sec, 3)
      #([adsr_str, ..tokens], vf.adsr)
    }
    False -> #(tokens, tracker.last_adsr)
  }

  // Frequency and Gate transitions
  let freq_changed = vf.freq != tracker.last_freq && vf.freq > 0
  let gate_turned_on = vf.gate && !tracker.last_gate
  let gate_turned_off = !vf.gate && tracker.last_gate

  let #(tokens, next_freq) = case gate_turned_on {
    True -> {
      let f_str = "f" <> format_float(freq_to_hz(vf.freq), 2)
      #(["l1", f_str, ..tokens], vf.freq)
    }
    False -> {
      case gate_turned_off {
        True -> #(["l0", ..tokens], tracker.last_freq)
        False -> {
          // Gate remains ON, frequency slid
          case vf.gate && freq_changed {
            True -> {
              let f_str = "f" <> format_float(freq_to_hz(vf.freq), 2)
              #([f_str, ..tokens], vf.freq)
            }
            False -> #(tokens, tracker.last_freq)
          }
        }
      }
    }
  }

  let next_tracker =
    VoiceTracker(
      last_freq: next_freq,
      last_wave: next_wave,
      last_adsr: next_adsr,
      last_pulse: next_pulse,
      last_gate: vf.gate,
      last_ring: tracker.last_ring,
    )

  #(list.reverse(tokens), next_tracker)
}

/// Generates space-separated tokens for volume changes on conductor track.
fn generate_filter_step_tokens(
  ff: FilterFrame,
  tracker: FilterTracker,
) -> #(List(String), FilterTracker) {
  let tokens = []
  let vol_changed = ff.volume != tracker.last_vol

  // Volume changes: per-voice amplitude 'a' is schedulable, while master 'V' is immediate-only.
  let #(tokens, next_vol) = case vol_changed {
    True -> {
      let vol_db = case ff.volume {
        0 -> -100
        15 -> 0
        v -> { v - 15 } * 2
      }
      let db_str = "a" <> int.to_string(vol_db)
      #(
        ["v0 " <> db_str <> " v1 " <> db_str <> " v2 " <> db_str, ..tokens],
        ff.volume,
      )
    }
    False -> #(tokens, tracker.last_vol)
  }

  let next_tracker =
    FilterTracker(
      last_cutoff: ff.cutoff,
      last_res: ff.resonance,
      last_mode: ff.mode_str,
      last_vol: next_vol,
      last_route_v1: ff.route_v1,
      last_route_v2: ff.route_v2,
      last_route_v3: ff.route_v3,
    )

  #(list.reverse(tokens), next_tracker)
}

pub fn convert_song(
  song: DumpSong,
  stereo: StereoMode,
) -> Result(ConversionResult, String) {
  let frame_count = song.frame_count
  case frame_count == 0 {
    True -> Error("SID dump contains 0 frames.")
    False -> {
      let total_steps = frame_count + 1
      let s_last = total_steps - 1
      let duration_seconds = int.to_float(frame_count) /. 50.0

      // Stereo positioning
      let #(p0, p1, p2) = case stereo {
        StereoHeadphone -> #("-0.6", "0.6", "0.0")
        StereoWide -> #("-1.0", "1.0", "0.0")
        StereoMono -> #("0.0", "0.0", "0.0")
      }

      // Initial header
      let init_header = [
        "# ==============================================================================",
        "# Converted from: " <> song.title <> " (" <> song.author <> ")",
        "# Frames: " <> int.to_string(frame_count) <> " @ 50.0 Hz (PAL C64)",
        "# Duration: " <> format_duration(duration_seconds),
        "# Generated for Skred v0.80.0",
        "# ==============================================================================",
        "",
        "# Master volume and 50 Hz tick rate: (125 BPM * 96 subdivision) / 240 = 50.0 Hz step clock",
        "V -6",
        "M 125 96",
        "",
        "# === INITIALIZATION ===",
        "S0 S1 S2 S3",
        "v0 [Voice 1] vt w1 a0 t0.002,0.008,0.5,0.01 p" <> p0,
        "v1 [Voice 2] vt w3 a0 t0.002,0.008,0.5,0.01 p" <> p1,
        "v2 [Voice 3] vt w4 a0 t0.002,0.008,0.5,0.01 p" <> p2,
        "v3 [Filter] vt w0 a0",
        "",
        "# Tracks setup: modulo 1 = advance 1 step per 50Hz tick",
        "y0 %1",
        "y1 %1",
        "y2 %1",
        "y3 %1",
        "",
        "# === THE MASTER CONDUCTOR ===",
        "# y127 provides downbeat synchronization and song tracking",
        "y127 %1 [v0] x" <> int.to_string(s_last) <> " yp127",
        "",
      ]

      // State tracking accumulator for all 3 voices + filter
      let initial_acc = #(
        init_tracker(),
        init_tracker(),
        init_tracker(),
        init_filter_tracker(),
        [],
        [],
        [],
        [],
        dict.new(),
        0,
      )

      let #(
        _t0,
        _t1,
        _t2,
        _tf,
        ch0_lines_rev,
        ch1_lines_rev,
        ch2_lines_rev,
        cond_lines_rev,
        step_times,
        _total_frames,
      ) =
        list.fold(song.frames, initial_acc, fn(acc, frame: SidFrame) {
          let #(
            t0,
            t1,
            t2,
            tf,
            lines0,
            lines1,
            lines2,
            lines_cond,
            times,
            step_idx,
          ) = acc

          let cur_time = int.to_float(step_idx) /. 50.0
          let updated_times = dict.insert(times, step_idx, cur_time)

          // Step 0 must bind voice identity to each track
          let step_str = int.to_string(step_idx)

          // Voice 0 (modulated by V2)
          let #(toks0, nt0) = generate_voice_step_tokens(frame.v1, t0, 2)
          let toks0 = case step_idx == 0 {
            True -> ["v0", ..toks0]
            False -> toks0
          }
          let new_lines0 = case toks0 {
            [] -> lines0
            _ -> ["[" <> string.join(toks0, " ") <> "] x" <> step_str, ..lines0]
          }

          // Voice 1 (modulated by V0)
          let #(toks1, nt1) = generate_voice_step_tokens(frame.v2, t1, 0)
          let toks1 = case step_idx == 0 {
            True -> ["v1", ..toks1]
            False -> toks1
          }
          let new_lines1 = case toks1 {
            [] -> lines1
            _ -> ["[" <> string.join(toks1, " ") <> "] x" <> step_str, ..lines1]
          }

          // Voice 2 (modulated by V1)
          let #(toks2, nt2) = generate_voice_step_tokens(frame.v3, t2, 1)
          let toks2 = case step_idx == 0 {
            True -> ["v2", ..toks2]
            False -> toks2
          }
          let new_lines2 = case toks2 {
            [] -> lines2
            _ -> ["[" <> string.join(toks2, " ") <> "] x" <> step_str, ..lines2]
          }

          // Conductor / Filter (Track 3)
          let #(toks_f, ntf) = generate_filter_step_tokens(frame.filter, tf)
          let new_lines_cond = case toks_f {
            [] -> lines_cond
            _ -> [
              "[" <> string.join(toks_f, " ") <> "] x" <> step_str,
              ..lines_cond
            ]
          }

          #(
            nt0,
            nt1,
            nt2,
            ntf,
            new_lines0,
            new_lines1,
            new_lines2,
            new_lines_cond,
            updated_times,
            step_idx + 1,
          )
        })

      let s_last_str = int.to_string(s_last)

      // Track 0
      let t0_text =
        list.reverse(ch0_lines_rev)
        |> list.prepend("[#] x " <> s_last_str)
        |> list.append(["[Z0 ce 127 v0] x" <> s_last_str])
        |> string.join("\n")

      // Track 1
      let t1_text =
        list.reverse(ch1_lines_rev)
        |> list.prepend("[#] x " <> s_last_str)
        |> list.append(["[v1] x" <> s_last_str])
        |> string.join("\n")

      // Track 2
      let t2_text =
        list.reverse(ch2_lines_rev)
        |> list.prepend("[#] x " <> s_last_str)
        |> list.append(["[v2] x" <> s_last_str])
        |> string.join("\n")

      // Conductor / Filter Track 3
      let cond_text =
        list.reverse(cond_lines_rev)
        |> list.prepend("[#] x " <> s_last_str)
        |> list.append(["[v3] x" <> s_last_str])
        |> string.join("\n")

      let track_blocks = [
        "# ==============================================================================",
        "# TRACK 0 (Voice 1)",
        "# ==============================================================================",
        "y0",
        t0_text,
        "",
        "# ==============================================================================",
        "# TRACK 1 (Voice 2)",
        "# ==============================================================================",
        "y1",
        t1_text,
        "",
        "# ==============================================================================",
        "# TRACK 2 (Voice 3)",
        "# ==============================================================================",
        "y2",
        t2_text,
        "",
        "# ==============================================================================",
        "# CONDUCTOR TRACK (Filter & Volume Automation)",
        "# ==============================================================================",
        "y3",
        cond_text,
        "",
      ]

      // Stop & Play Macros matching Skred v0.80.0
      let stop_cmds = "/cer 0 Z0 O DQ ?ce!"
      let play_cmds = "?ce! /cer 1 Z0 Z! y0 z1 y1 z1 y2 z1 y3 z1 y127 z1"

      let end_blocks = [
        "# === PATTERN TRANSITIONS & END OF SONG HOOK ===",
        "[" <> stop_cmds <> "] /ceb 4 127",
        "/cer 1",
        "",
        "# === MACROS ===",
        "# The file does not start automatically. Type 'play' to begin, and 'stop' to halt.",
        "[play]: " <> play_cmds <> ";",
        "[stop]: " <> stop_cmds <> ";",
        "",
      ]

      let all_skode_lines =
        list.flatten([init_header, track_blocks, end_blocks])
      let full_skode = string.join(all_skode_lines, "\n")

      Ok(ConversionResult(
        skode_text: full_skode,
        total_steps: total_steps,
        duration_seconds: duration_seconds,
        step_times: step_times,
      ))
    }
  }
}

pub fn build_live_stereo_command(stereo: StereoMode) -> String {
  case stereo {
    StereoHeadphone -> "v0 p-0.6; v1 p0.6; v2 p0.0"
    StereoWide -> "v0 p-1.0; v1 p1.0; v2 p0.0"
    StereoMono -> "v0 p0.0; v1 p0.0; v2 p0.0"
  }
}
