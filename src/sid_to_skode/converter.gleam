//// Compiles parsed SID dumps into clean, idiomatic Skode 0.80.0 scripts.

import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/string
import sid_to_skode/types.{
  type ConversionResult, type DumpSong, type FilterFrame, type SidFrame,
  type StereoMode, type VoiceFrame, ConversionResult, StereoCustom,
  StereoHeadphone, StereoMono, StereoWide,
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

// Hardware SID ADSR time constants calibrated with software DSP anti-click floors:
// On physical SID hardware (MOS 6581/8580), Attack 0 is 2.0ms and Release 0 is 6.0ms.
// Neither parameter was ever 0.0ms on real hardware. In software DSP (Skred),
// an instantaneous 0.0s jump creates a step discontinuity that produces audible clicks.
// An attack floor of 4ms and a release floor of 12ms eliminate clicks while keeping
// the punchy, snappy percussive feel identical to authentic C64 hardware.
const sid_attack_table: List(Float) = [
  0.004, 0.008, 0.016, 0.024, 0.038, 0.056, 0.068, 0.08, 0.1, 0.25, 0.5, 0.8,
  1.0, 3.0, 5.0, 8.0,
]

const sid_decay_table: List(Float) = [
  0.008, 0.024, 0.048, 0.072, 0.114, 0.168, 0.204, 0.24, 0.3, 0.75, 1.5, 2.4,
  3.0, 9.0, 15.0, 24.0,
]

const sid_release_table: List(Float) = [
  0.012, 0.024, 0.048, 0.072, 0.114, 0.168, 0.204, 0.24, 0.3, 0.75, 1.5, 2.4,
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
  let is_negative = val <. 0.0
  let abs_val = float.absolute_value(val)
  let factor = case decimals {
    1 -> 10.0
    2 -> 100.0
    3 -> 1000.0
    _ -> 100.0
  }
  let rounded = float.round(abs_val *. factor)
  let whole = rounded / float.round(factor)
  let frac = rounded % float.round(factor)
  let raw_frac = int.to_string(frac)
  let pad_needed = decimals - string.length(raw_frac)
  let frac_str = case pad_needed > 0 {
    True -> string.repeat("0", pad_needed) <> raw_frac
    False -> raw_frac
  }
  let num_str = int.to_string(whole) <> "." <> frac_str
  case is_negative && rounded > 0 {
    True -> "-" <> num_str
    False -> num_str
  }
}

pub type VoiceTracker {
  VoiceTracker(
    last_freq: Int,
    last_wave: Int,
    last_adsr: Int,
    last_pulse: Int,
    last_gate: Bool,
    last_ring: Bool,
    frames_held: Int,
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
    frames_held: 0,
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
    _, True, _, _ -> "w15"
    _, _, True, _ -> "w16"
    _, _, _, True -> "w18"
    _, _, _, _ -> "w16"
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

  // Pulse width changed (for pulse wave w1)
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
  let adsr_changed = vf.adsr != tracker.last_adsr
  let #(tokens, next_adsr) = case adsr_changed {
    True -> {
      let a_sec = lookup_table(sid_attack_table, vf.attack, 0.004)
      let d_sec = lookup_table(sid_decay_table, vf.decay, 0.008)
      let s_lvl = int.to_float(vf.sustain) /. 15.0
      let r_sec = lookup_table(sid_release_table, vf.release, 0.012)
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

  // Ring modulation:
  // SID ring modulation XORs phase accumulator MSBs (MSB1 ^ MSB3), which affects only the triangle
  // wave and continues oscillating even when the modulator voice has zero volume / gate off.
  // In Skred's C DSP engine, 'XM' is 4-quadrant PCM sample multiplication (f *= sv.sample[mod]).
  // Emitting 'XM' when the modulator is silent mutes the voice to 0.0, destroying melodic tunes
  // like Commando where Voice 1 rapidly multiplexes between lead notes and drum noise.
  // We keep track of ring_mod in VoiceTracker but do not emit destructive audio-multiplication XM.
  let next_ring = vf.ring_mod

  // Frequency and Gate transitions
  let freq_changed = vf.freq != tracker.last_freq && vf.freq > 0
  let gate_turned_on = vf.gate && !tracker.last_gate && vf.freq > 0
  let gate_turned_off = !vf.gate && tracker.last_gate

  // Frequency must ALWAYS be updated whenever pitch changes OR gate turns on!
  let #(tokens, next_freq) = case gate_turned_on || freq_changed {
    True -> {
      let f_str = "f" <> format_float(freq_to_hz(vf.freq), 2)
      #([f_str, ..tokens], vf.freq)
    }
    False -> #(tokens, tracker.last_freq)
  }

  // Gate and Voice Attack events:
  // In Skred, 'l1' (velocity 1) attacks the voice envelope.
  // We emit 'l1' when:
  // 1. Gate turns on with valid frequency (note-on).
  // 2. Gate is held active, but ADSR parameters change (e.g. percussion hits).
  // 3. Gate is held active, but pitch changes after sustain has reached 0.
  // 4. Gate is held active, but pitch changes after being held (staccato re-attack).
  // When gate turns off and voice is not attacking, we emit 'l0' (note-off/release).
  // NOTE: 'vt' is voice-text-set and is IMMEDIATE-ONLY; never compile 'vt' into pattern steps!
  let should_attack =
    gate_turned_on
    || { vf.gate && adsr_changed && vf.freq > 0 }
    || { vf.gate && freq_changed && tracker.frames_held >= 2 }
    || { vf.gate && freq_changed && vf.sustain == 0 }

  let tokens = case should_attack, gate_turned_off {
    True, _ -> ["l1", ..tokens]
    False, True -> ["l0", ..tokens]
    False, False -> tokens
  }

  let next_frames_held = case freq_changed {
    True -> 0
    False -> tracker.frames_held + 1
  }

  let next_tracker =
    VoiceTracker(
      last_freq: next_freq,
      last_wave: next_wave,
      last_adsr: next_adsr,
      last_pulse: next_pulse,
      last_gate: vf.gate,
      last_ring: next_ring,
      frames_held: next_frames_held,
    )

  #(list.reverse(tokens), next_tracker)
}

pub fn filter_mode_int(mode_str: String) -> Int {
  case mode_str {
    "Low" | "LP" | "lp" -> 1
    "Hig" | "HP" | "hp" -> 2
    "Bnd" | "BP" | "bp" -> 3
    "L+H" | "Not" | "not" -> 4
    "LBH" | "All" | "all" -> 5
    "L+B" -> 1
    "B+H" -> 2
    _ -> 0
  }
}

fn voice_filter_tokens(
  v_idx: Int,
  is_routed: Bool,
  was_routed: Bool,
  mode_int: Int,
  prev_mode_int: Int,
  cutoff_changed: Bool,
  res_changed: Bool,
  hz_str: String,
  q_str: String,
) -> List(String) {
  let is_filtered = mode_int > 0 && is_routed
  let was_filtered = prev_mode_int > 0 && was_routed
  let v_tag = "v" <> int.to_string(v_idx)

  case was_filtered, is_filtered {
    // Was filtered, now turned off
    True, False -> [v_tag, "j0"]

    // Turned on
    False, True -> [
      v_tag,
      "j" <> int.to_string(mode_int),
      "k" <> hz_str,
      "q" <> q_str,
    ]

    // Still filtered
    True, True -> {
      let mode_changed = mode_int != prev_mode_int
      case mode_changed, cutoff_changed, res_changed {
        True, _, _ -> [
          v_tag,
          "j" <> int.to_string(mode_int),
          "k" <> hz_str,
          "q" <> q_str,
        ]
        False, True, True -> [v_tag, "k" <> hz_str, "q" <> q_str]
        False, True, False -> [v_tag, "k" <> hz_str]
        False, False, True -> [v_tag, "q" <> q_str]
        False, False, False -> []
      }
    }

    // Unfiltered before and after
    False, False -> []
  }
}

/// Generates space-separated tokens for volume and filter changes on conductor track.
fn generate_filter_step_tokens(
  ff: FilterFrame,
  tracker: FilterTracker,
) -> #(List(String), FilterTracker) {
  let mode_int = filter_mode_int(ff.mode_str)
  let prev_mode_int = filter_mode_int(tracker.last_mode)

  let cutoff_changed = ff.cutoff != tracker.last_cutoff
  let res_changed = ff.resonance != tracker.last_res

  let hz_str = format_float(cutoff_to_hz(ff.cutoff), 1)
  let q_str = format_float(res_to_q(ff.resonance), 2)

  let v0_toks =
    voice_filter_tokens(
      0,
      ff.route_v1,
      tracker.last_route_v1,
      mode_int,
      prev_mode_int,
      cutoff_changed,
      res_changed,
      hz_str,
      q_str,
    )

  let v1_toks =
    voice_filter_tokens(
      1,
      ff.route_v2,
      tracker.last_route_v2,
      mode_int,
      prev_mode_int,
      cutoff_changed,
      res_changed,
      hz_str,
      q_str,
    )

  let v2_toks =
    voice_filter_tokens(
      2,
      ff.route_v3,
      tracker.last_route_v3,
      mode_int,
      prev_mode_int,
      cutoff_changed,
      res_changed,
      hz_str,
      q_str,
    )

  let filter_tokens = list.flatten([v0_toks, v1_toks, v2_toks])

  // Volume changes: per-voice amplitude 'a' is schedulable, while master 'V' is immediate-only.
  let vol_changed = ff.volume != tracker.last_vol
  let #(vol_tokens, next_vol) = case vol_changed {
    True -> {
      let vol_db = case ff.volume {
        0 -> -100
        v -> -8 + { v - 15 } * 2
      }
      let db_str = "a" <> int.to_string(vol_db)
      #(["v0", db_str, "v1", db_str, "v2", db_str], ff.volume)
    }
    False -> #([], tracker.last_vol)
  }

  let all_tokens = list.append(vol_tokens, filter_tokens)

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

  #(all_tokens, next_tracker)
}

pub fn convert_song(
  song: DumpSong,
  stereo: StereoMode,
) -> Result(ConversionResult, String) {
  convert_song_with_options(song, stereo, True)
}

pub fn convert_song_with_options(
  song: DumpSong,
  stereo: StereoMode,
  dac_crunch: Bool,
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
        StereoCustom(v0, v1, v2) -> #(
          format_float(v0, 2),
          format_float(v1, 2),
          format_float(v2, 2),
        )
      }

      let bc_suffix = case dac_crunch {
        True -> " bc6"
        False -> ""
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
        "V -8",
        "M 125 96",
        "",
        "# === INITIALIZATION ===",
        case dac_crunch {
          True ->
            "# S0-S2 clear voice state -- bc6 emulates MOS 6581/8580 non-linear 8-bit DAC crunch"
          False ->
            "# S0-S2 clear voice state -- clean 24-bit floating point DSP"
        },
        "S0 S1 S2",
        "v0 [Voice 1] vt w16 a-8 t0.004,0.008,0.5,0.012 p" <> p0 <> bc_suffix,
        "v1 [Voice 2] vt w15 a-8 t0.004,0.008,0.5,0.012 p" <> p1 <> bc_suffix,
        "v2 [Voice 3] vt w18 a-8 t0.004,0.008,0.5,0.012 p" <> p2 <> bc_suffix,
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
        |> list.append(["[v0 l0 v1 l0 v2 l0 ce 127 Z0] x" <> s_last_str])
        |> string.join("\n")

      // Track 1
      let t1_text =
        list.reverse(ch1_lines_rev)
        |> list.prepend("[#] x " <> s_last_str)
        |> list.append(["[v1 l0] x" <> s_last_str])
        |> string.join("\n")

      // Track 2
      let t2_text =
        list.reverse(ch2_lines_rev)
        |> list.prepend("[#] x " <> s_last_str)
        |> list.append(["[v2 l0] x" <> s_last_str])
        |> string.join("\n")

      // Conductor / Filter Track 3
      let cond_text =
        list.reverse(cond_lines_rev)
        |> list.prepend("[#] x " <> s_last_str)
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
      let stop_cmds = "/cer 0 Z0 O DQ ?ce!; v0 l0; v1 l0; v2 l0; S-1"
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
    StereoCustom(p0, p1, p2) ->
      "v0 p"
      <> format_float(p0, 2)
      <> "; v1 p"
      <> format_float(p1, 2)
      <> "; v2 p"
      <> format_float(p2, 2)
  }
}

pub fn build_voice_pan_command(voice: Int, pan: Float) -> String {
  "v" <> int.to_string(voice) <> " p" <> format_float(pan, 2)
}
