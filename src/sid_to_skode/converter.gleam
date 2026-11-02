//// Compiles parsed SID dumps into clean, optimized Skode 0.80.0 scripts.

import gleam/float
import gleam/int
import gleam/list
import gleam/string
import sid_to_skode/types.{
  type ConversionResult, type DumpSong, type StereoProfile, type VoiceFrame,
  ConversionResult, StereoAmiga, StereoHeadphone, StereoMono,
}

pub fn make_range(start: Int, end: Int) -> List(Int) {
  case start <= end {
    True -> [start, ..make_range(start + 1, end)]
    False -> []
  }
}

const sid_attack_table: List(Float) = [
  0.002, 0.008, 0.016, 0.024, 0.038, 0.056, 0.068, 0.080, 0.100, 0.250, 0.500,
  0.800, 1.000, 3.000, 5.000, 8.000,
]

const sid_decay_table: List(Float) = [
  0.006, 0.024, 0.048, 0.072, 0.114, 0.168, 0.204, 0.240, 0.300, 0.750, 1.500,
  2.400, 3.000, 9.000, 15.000, 24.000,
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

fn round_float(val: Float, decimals: Int) -> String {
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

fn wave_opcode(wave_byte: Int) -> String {
  // Check waveform selection bits
  let is_tri = int.bitwise_and(wave_byte, 0x10) != 0
  let is_saw = int.bitwise_and(wave_byte, 0x20) != 0
  let is_pulse = int.bitwise_and(wave_byte, 0x40) != 0
  let is_noise = int.bitwise_and(wave_byte, 0x80) != 0

  case is_noise, is_saw, is_pulse, is_tri {
    True, _, _, _ -> "w6" // Knuth MMIX LCG white noise
    _, True, _, _ -> "w15" // Band-limited DWGS Saw
    _, _, True, _ -> "w16" // Band-limited DWGS Square/Pulse
    _, _, _, True -> "w18" // Band-limited DWGS Triangle
    _, _, _, _ -> "w15"
  }
}

fn filter_mode_num(mode_str: String) -> Int {
  case mode_str {
    "Low" -> 1
    "Hi " -> 2
    "Bnd" -> 3
    "L+H" -> 4
    _ -> 1
  }
}

fn generate_voice_cmds(
  v_num: Int,
  vf: VoiceFrame,
  tracker: VoiceTracker,
  filter_routed: Bool,
  filter_mode: Int,
  cutoff_hz: Float,
  res_q: Float,
  mod_voice: Int,
) -> #(String, VoiceTracker) {
  let v_prefix = "v" <> int.to_string(v_num) <> " "

  // Waveform changed
  let #(wave_parts, next_wave) = case vf.waveform_byte != tracker.last_wave {
    True -> #(
      [v_prefix <> wave_opcode(vf.waveform_byte)],
      vf.waveform_byte,
    )
    False -> #([], tracker.last_wave)
  }

  // Frequency changed
  let #(freq_parts, next_freq) = case vf.freq != tracker.last_freq && vf.freq > 0 {
    True -> #(
      [v_prefix <> "f" <> round_float(freq_to_hz(vf.freq), 2)],
      vf.freq,
    )
    False -> #([], tracker.last_freq)
  }

  // Pulse width changed (apply CZ distortion on pulse wave)
  let is_pulse = int.bitwise_and(vf.waveform_byte, 0x40) != 0
  let #(pulse_parts, next_pulse) = case
    is_pulse && vf.pulse_width != tracker.last_pulse
  {
    True -> #(
      [v_prefix <> "c1," <> round_float(pulse_to_cz(vf.pulse_width), 3)],
      vf.pulse_width,
    )
    False -> #([], tracker.last_pulse)
  }

  // ADSR changed
  let #(adsr_parts, next_adsr) = case vf.adsr != tracker.last_adsr {
    True -> {
      let a_sec = lookup_table(sid_attack_table, vf.attack, 0.002)
      let d_sec = lookup_table(sid_decay_table, vf.decay, 0.006)
      let s_lvl = int.to_float(vf.sustain) /. 15.0
      let r_sec = lookup_table(sid_decay_table, vf.release, 0.006)
      let adsr_str =
        v_prefix
        <> "t "
        <> round_float(a_sec, 3)
        <> ","
        <> round_float(d_sec, 3)
        <> ","
        <> round_float(s_lvl, 2)
        <> ","
        <> round_float(r_sec, 3)
      #([adsr_str], vf.adsr)
    }
    False -> #([], tracker.last_adsr)
  }

  // Ring modulation
  let #(ring_parts, next_ring) = case vf.ring_mod != tracker.last_ring {
    True -> {
      let ring_str = case vf.ring_mod {
        True -> v_prefix <> "XM " <> int.to_string(mod_voice)
        False -> v_prefix <> "XM -1"
      }
      #([ring_str], vf.ring_mod)
    }
    False -> #([], tracker.last_ring)
  }

  // Gate transition (Note On / Off)
  let #(gate_parts, next_gate) = case vf.gate != tracker.last_gate {
    True -> {
      let gate_str = case vf.gate {
        True -> v_prefix <> "l1"
        False -> v_prefix <> "l0"
      }
      #([gate_str], vf.gate)
    }
    False -> #([], tracker.last_gate)
  }

  // Filter routing
  let filt_parts = case filter_routed {
    True -> [
      v_prefix
      <> "j"
      <> int.to_string(filter_mode)
      <> " k"
      <> round_float(cutoff_hz, 1)
      <> " q"
      <> round_float(res_q, 2),
    ]
    False -> []
  }

  let all_parts =
    list.flatten([
      wave_parts,
      pulse_parts,
      adsr_parts,
      ring_parts,
      freq_parts,
      filt_parts,
      gate_parts,
    ])

  let next_tracker =
    VoiceTracker(
      last_freq: next_freq,
      last_wave: next_wave,
      last_adsr: next_adsr,
      last_pulse: next_pulse,
      last_gate: next_gate,
      last_ring: next_ring,
    )

  #(string.join(all_parts, "; "), next_tracker)
}

pub fn convert_song(
  song: DumpSong,
  stereo: StereoProfile,
) -> ConversionResult {
  // Panning setups
  let #(p0, p1, p2) = case stereo {
    StereoHeadphone -> #("-0.6", "0.6", "0.0")
    StereoAmiga -> #("-1.0", "1.0", "0.0")
    StereoMono -> #("0.0", "0.0", "0.0")
  }

  let header_lines = [
    "# Generated by sid-to-skode for Skred 0.80.0",
    "# Song: " <> song.title,
    "# Frames: " <> int.to_string(song.frame_count) <> " @ 50 Hz",
    "",
    "# Global audio setup & panning",
    "V -6",
    "v0 p " <> p0,
    "v1 p " <> p1,
    "v2 p " <> p2,
    "",
    "# Sequence Patterns",
  ]

  let initial_state = #(
    init_tracker(),
    init_tracker(),
    init_tracker(),
    [],
    0,
  )

  let #(_t0, _t1, _t2, pattern_lines_rev, total_steps) =
    list.fold(song.frames, initial_state, fn(acc, frame) {
      let #(t0, t1, t2, lines_acc, step_idx) = acc
      let filt = frame.filter
      let filt_hz = cutoff_to_hz(filt.cutoff)
      let res_q = res_to_q(filt.resonance)
      let f_mode = filter_mode_num(filt.mode_str)

      // Ring modulation routing: V0 modulated by V2, V1 by V0, V2 by V1
      let #(c0, nt0) =
        generate_voice_cmds(
          0,
          frame.v1,
          t0,
          filt.route_v1,
          f_mode,
          filt_hz,
          res_q,
          2,
        )
      let #(c1, nt1) =
        generate_voice_cmds(
          1,
          frame.v2,
          t1,
          filt.route_v2,
          f_mode,
          filt_hz,
          res_q,
          0,
        )
      let #(c2, nt2) =
        generate_voice_cmds(
          2,
          frame.v3,
          t2,
          filt.route_v3,
          f_mode,
          filt_hz,
          res_q,
          1,
        )

      let active_cmds =
        [c0, c1, c2]
        |> list.filter(fn(c) { string.length(c) > 0 })

      let step_str = case active_cmds {
        [] -> "-"
        _ -> "[ " <> string.join(active_cmds, " | ") <> " ]"
      }

      // Pattern formatting: 64 steps per pattern
      let pat_idx = step_idx / 64
      let pat_step = step_idx % 64

      let step_line = case pat_step == 0 {
        True ->
          "\n# Pattern "
          <> int.to_string(pat_idx)
          <> "\ny"
          <> int.to_string(pat_idx)
          <> "\n"
          <> step_str
          <> " x"
          <> int.to_string(pat_step)
        False -> step_str <> " x" <> int.to_string(pat_step)
      }

      #(nt0, nt1, nt2, [step_line, ..lines_acc], step_idx + 1)
    })

  let pattern_code =
    list.reverse(pattern_lines_rev)
    |> string.join("\n")

  // Pattern playlist sequencer
  let num_patterns = { total_steps + 63 } / 64
  let playlist_entries =
    make_range(0, num_patterns - 1)
    |> list.map(fn(i) { "y" <> int.to_string(i) })
    |> string.join(" ")

  let footer_lines = [
    "",
    "# Playlist Arrangement",
    playlist_entries,
    "",
    "# Sentinel end of song trigger",
    "[ S-1 ] ce 127",
  ]

  let full_script =
    string.join(
      list.flatten([header_lines, [pattern_code], footer_lines]),
      "\n",
    )

  let duration = int.to_float(total_steps) *. 0.02

  ConversionResult(
    skode_code: full_script,
    title: song.title,
    duration_seconds: duration,
    frame_count: song.frame_count,
    step_count: total_steps,
  )
}
