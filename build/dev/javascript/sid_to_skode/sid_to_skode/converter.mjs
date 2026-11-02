import * as $float from "../../gleam_stdlib/gleam/float.mjs";
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $string from "../../gleam_stdlib/gleam/string.mjs";
import {
  toList,
  Empty as $Empty,
  List$Empty$const as $List$Empty$const,
  prepend as listPrepend,
  CustomType as $CustomType,
  remainderInt,
  divideInt,
} from "../gleam.mjs";
import * as $types from "../sid_to_skode/types.mjs";
import { ConversionResult, StereoAmiga, StereoHeadphone, StereoMono } from "../sid_to_skode/types.mjs";

export class VoiceTracker extends $CustomType {
  constructor(last_freq, last_wave, last_adsr, last_pulse, last_gate, last_ring) {
    super();
    this.last_freq = last_freq;
    this.last_wave = last_wave;
    this.last_adsr = last_adsr;
    this.last_pulse = last_pulse;
    this.last_gate = last_gate;
    this.last_ring = last_ring;
  }
}
export const VoiceTracker$VoiceTracker = (last_freq, last_wave, last_adsr, last_pulse, last_gate, last_ring) =>
  new VoiceTracker(last_freq,
  last_wave,
  last_adsr,
  last_pulse,
  last_gate,
  last_ring);
export const VoiceTracker$isVoiceTracker = (value) =>
  value instanceof VoiceTracker;
export const VoiceTracker$VoiceTracker$last_freq = (value) => value.last_freq;
export const VoiceTracker$VoiceTracker$0 = (value) => value.last_freq;
export const VoiceTracker$VoiceTracker$last_wave = (value) => value.last_wave;
export const VoiceTracker$VoiceTracker$1 = (value) => value.last_wave;
export const VoiceTracker$VoiceTracker$last_adsr = (value) => value.last_adsr;
export const VoiceTracker$VoiceTracker$2 = (value) => value.last_adsr;
export const VoiceTracker$VoiceTracker$last_pulse = (value) => value.last_pulse;
export const VoiceTracker$VoiceTracker$3 = (value) => value.last_pulse;
export const VoiceTracker$VoiceTracker$last_gate = (value) => value.last_gate;
export const VoiceTracker$VoiceTracker$4 = (value) => value.last_gate;
export const VoiceTracker$VoiceTracker$last_ring = (value) => value.last_ring;
export const VoiceTracker$VoiceTracker$5 = (value) => value.last_ring;

const sid_decay_table = /* @__PURE__ */ toList([
  0.006,
  0.024,
  0.048,
  0.072,
  0.114,
  0.168,
  0.204,
  0.240,
  0.300,
  0.750,
  1.500,
  2.400,
  3.000,
  9.000,
  15.000,
  24.000,
]);

const sid_attack_table = /* @__PURE__ */ toList([
  0.002,
  0.008,
  0.016,
  0.024,
  0.038,
  0.056,
  0.068,
  0.080,
  0.100,
  0.250,
  0.500,
  0.800,
  1.000,
  3.000,
  5.000,
  8.000,
]);

export function make_range(start, end) {
  let $ = start <= end;
  if ($) {
    return listPrepend(start, make_range(start + 1, end));
  } else {
    return $List$Empty$const;
  }
}

function lookup_table(tbl, index, default$) {
  let $ = $list.drop(tbl, index);
  if ($ instanceof $Empty) {
    return default$;
  } else {
    let val = $.head;
    return val;
  }
}

export function freq_to_hz(freq) {
  return $int.to_float(freq) * 0.0587285;
}

export function pulse_to_cz(pulse) {
  let norm = ($int.to_float(pulse) - 2048.0) / 2048.0;
  if (norm > 0.98) {
    return 0.98;
  } else if (norm < -0.98) {
    return -0.98;
  } else {
    return norm;
  }
}

export function cutoff_to_hz(cutoff) {
  return 30.0 + ($int.to_float(cutoff) * 5.8);
}

export function res_to_q(res) {
  return 0.707 + ($int.to_float(res) * 0.42);
}

function round_float(val, decimals) {
  let _block;
  if (decimals === 1) {
    _block = 10.0;
  } else if (decimals === 2) {
    _block = 100.0;
  } else if (decimals === 3) {
    _block = 1000.0;
  } else {
    _block = 100.0;
  }
  let factor = _block;
  let rounded = $float.round(val * factor);
  let whole = divideInt(rounded, $float.round(factor));
  let frac = $int.absolute_value(remainderInt(rounded, $float.round(factor)));
  let _block$1;
  let $ = (frac < 10) && (decimals > 1);
  if ($) {
    _block$1 = "0" + $int.to_string(frac);
  } else {
    _block$1 = $int.to_string(frac);
  }
  let frac_str = _block$1;
  return ($int.to_string(whole) + ".") + frac_str;
}

export function init_tracker() {
  return new VoiceTracker(-1, -1, -1, -1, false, false);
}

function wave_opcode(wave_byte) {
  let is_tri = $int.bitwise_and(wave_byte, 0x10) !== 0;
  let is_saw = $int.bitwise_and(wave_byte, 0x20) !== 0;
  let is_pulse = $int.bitwise_and(wave_byte, 0x40) !== 0;
  let is_noise = $int.bitwise_and(wave_byte, 0x80) !== 0;
  if (is_noise) {
    return "w6";
  } else if (is_saw) {
    return "w15";
  } else if (is_pulse) {
    return "w16";
  } else if (is_tri) {
    return "w18";
  } else {
    return "w15";
  }
}

function filter_mode_num(mode_str) {
  if (mode_str === "Low") {
    return 1;
  } else if (mode_str === "Hi ") {
    return 2;
  } else if (mode_str === "Bnd") {
    return 3;
  } else if (mode_str === "L+H") {
    return 4;
  } else {
    return 1;
  }
}

function generate_voice_cmds(
  v_num,
  vf,
  tracker,
  filter_routed,
  filter_mode,
  cutoff_hz,
  res_q,
  mod_voice
) {
  let v_prefix = ("v" + $int.to_string(v_num)) + " ";
  let _block;
  let $1 = vf.waveform_byte !== tracker.last_wave;
  if ($1) {
    _block = [
      listPrepend(v_prefix + wave_opcode(vf.waveform_byte), $List$Empty$const),
      vf.waveform_byte,
    ];
  } else {
    _block = [$List$Empty$const, tracker.last_wave];
  }
  let $ = _block;
  let wave_parts = $[0];
  let next_wave = $[1];
  let _block$1;
  let $3 = (vf.freq !== tracker.last_freq) && (vf.freq > 0);
  if ($3) {
    _block$1 = [
      listPrepend(
        (v_prefix + "f") + round_float(freq_to_hz(vf.freq), 2),
        $List$Empty$const,
      ),
      vf.freq,
    ];
  } else {
    _block$1 = [$List$Empty$const, tracker.last_freq];
  }
  let $2 = _block$1;
  let freq_parts = $2[0];
  let next_freq = $2[1];
  let is_pulse = $int.bitwise_and(vf.waveform_byte, 0x40) !== 0;
  let _block$2;
  let $5 = is_pulse && (vf.pulse_width !== tracker.last_pulse);
  if ($5) {
    _block$2 = [
      listPrepend(
        (v_prefix + "c1,") + round_float(pulse_to_cz(vf.pulse_width), 3),
        $List$Empty$const,
      ),
      vf.pulse_width,
    ];
  } else {
    _block$2 = [$List$Empty$const, tracker.last_pulse];
  }
  let $4 = _block$2;
  let pulse_parts = $4[0];
  let next_pulse = $4[1];
  let _block$3;
  let $7 = vf.adsr !== tracker.last_adsr;
  if ($7) {
    let a_sec = lookup_table(sid_attack_table, vf.attack, 0.002);
    let d_sec = lookup_table(sid_decay_table, vf.decay, 0.006);
    let s_lvl = $int.to_float(vf.sustain) / 15.0;
    let r_sec = lookup_table(sid_decay_table, vf.release, 0.006);
    let adsr_str = (((((((v_prefix + "t ") + round_float(a_sec, 3)) + ",") + round_float(
      d_sec,
      3,
    )) + ",") + round_float(s_lvl, 2)) + ",") + round_float(r_sec, 3);
    _block$3 = [listPrepend(adsr_str, $List$Empty$const), vf.adsr];
  } else {
    _block$3 = [$List$Empty$const, tracker.last_adsr];
  }
  let $6 = _block$3;
  let adsr_parts = $6[0];
  let next_adsr = $6[1];
  let _block$4;
  let $9 = vf.ring_mod !== tracker.last_ring;
  if ($9) {
    let _block$5;
    let $10 = vf.ring_mod;
    if ($10) {
      _block$5 = (v_prefix + "XM ") + $int.to_string(mod_voice);
    } else {
      _block$5 = v_prefix + "XM -1";
    }
    let ring_str = _block$5;
    _block$4 = [listPrepend(ring_str, $List$Empty$const), vf.ring_mod];
  } else {
    _block$4 = [$List$Empty$const, tracker.last_ring];
  }
  let $8 = _block$4;
  let ring_parts = $8[0];
  let next_ring = $8[1];
  let _block$5;
  let $11 = vf.gate !== tracker.last_gate;
  if ($11) {
    let _block$6;
    let $12 = vf.gate;
    if ($12) {
      _block$6 = v_prefix + "l1";
    } else {
      _block$6 = v_prefix + "l0";
    }
    let gate_str = _block$6;
    _block$5 = [listPrepend(gate_str, $List$Empty$const), vf.gate];
  } else {
    _block$5 = [$List$Empty$const, tracker.last_gate];
  }
  let $10 = _block$5;
  let gate_parts = $10[0];
  let next_gate = $10[1];
  let _block$6;
  if (filter_routed) {
    _block$6 = listPrepend(
      (((((v_prefix + "j") + $int.to_string(filter_mode)) + " k") + round_float(
        cutoff_hz,
        1,
      )) + " q") + round_float(res_q, 2),
      $List$Empty$const,
    );
  } else {
    _block$6 = $List$Empty$const;
  }
  let filt_parts = _block$6;
  let all_parts = $list.flatten(
    listPrepend(
      wave_parts,
      listPrepend(
        pulse_parts,
        listPrepend(
          adsr_parts,
          listPrepend(
            ring_parts,
            listPrepend(
              freq_parts,
              listPrepend(
                filt_parts,
                listPrepend(gate_parts, $List$Empty$const),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  let next_tracker = new VoiceTracker(
    next_freq,
    next_wave,
    next_adsr,
    next_pulse,
    next_gate,
    next_ring,
  );
  return [$string.join(all_parts, "; "), next_tracker];
}

export function convert_song(song, stereo) {
  let _block;
  if (stereo instanceof StereoHeadphone) {
    _block = ["-0.6", "0.6", "0.0"];
  } else if (stereo instanceof StereoAmiga) {
    _block = ["-1.0", "1.0", "0.0"];
  } else {
    _block = ["0.0", "0.0", "0.0"];
  }
  let $ = _block;
  let p0 = $[0];
  let p1 = $[1];
  let p2 = $[2];
  let header_lines = toList([
    "# Generated by sid-to-skode for Skred 0.80.0",
    "# Song: " + song.title,
    ("# Frames: " + $int.to_string(song.frame_count)) + " @ 50 Hz",
    "",
    "# Global audio setup & panning",
    "V -6",
    "v0 p " + p0,
    "v1 p " + p1,
    "v2 p " + p2,
    "",
    "# Sequence Patterns",
  ]);
  let initial_state = [
    init_tracker(),
    init_tracker(),
    init_tracker(),
    $List$Empty$const,
    0,
  ];
  let $1 = $list.fold(
    song.frames,
    initial_state,
    (acc, frame) => {
      let t0 = acc[0];
      let t1 = acc[1];
      let t2 = acc[2];
      let lines_acc = acc[3];
      let step_idx = acc[4];
      let filt = frame.filter;
      let filt_hz = cutoff_to_hz(filt.cutoff);
      let res_q = res_to_q(filt.resonance);
      let f_mode = filter_mode_num(filt.mode_str);
      let $2 = generate_voice_cmds(
        0,
        frame.v1,
        t0,
        filt.route_v1,
        f_mode,
        filt_hz,
        res_q,
        2,
      );
      let c0 = $2[0];
      let nt0 = $2[1];
      let $3 = generate_voice_cmds(
        1,
        frame.v2,
        t1,
        filt.route_v2,
        f_mode,
        filt_hz,
        res_q,
        0,
      );
      let c1 = $3[0];
      let nt1 = $3[1];
      let $4 = generate_voice_cmds(
        2,
        frame.v3,
        t2,
        filt.route_v3,
        f_mode,
        filt_hz,
        res_q,
        1,
      );
      let c2 = $4[0];
      let nt2 = $4[1];
      let _block$1;
      let _pipe = listPrepend(
        c0,
        listPrepend(c1, listPrepend(c2, $List$Empty$const)),
      );
      _block$1 = $list.filter(_pipe, (c) => { return $string.length(c) > 0; });
      let active_cmds = _block$1;
      let _block$2;
      if (active_cmds instanceof $Empty) {
        _block$2 = "-";
      } else {
        _block$2 = ("[ " + $string.join(active_cmds, " | ")) + " ]";
      }
      let step_str = _block$2;
      let pat_idx = globalThis.Math.trunc(step_idx / 64);
      let pat_step = step_idx % 64;
      let _block$3;
      let $5 = pat_step === 0;
      if ($5) {
        _block$3 = (((((("\n# Pattern " + $int.to_string(pat_idx)) + "\ny") + $int.to_string(
          pat_idx,
        )) + "\n") + step_str) + " x") + $int.to_string(pat_step);
      } else {
        _block$3 = (step_str + " x") + $int.to_string(pat_step);
      }
      let step_line = _block$3;
      return [nt0, nt1, nt2, listPrepend(step_line, lines_acc), step_idx + 1];
    },
  );
  let pattern_lines_rev = $1[3];
  let total_steps = $1[4];
  let _block$1;
  let _pipe = $list.reverse(pattern_lines_rev);
  _block$1 = $string.join(_pipe, "\n");
  let pattern_code = _block$1;
  let num_patterns = globalThis.Math.trunc((total_steps + 63) / 64);
  let _block$2;
  let _pipe$1 = make_range(0, num_patterns - 1);
  let _pipe$2 = $list.map(_pipe$1, (i) => { return "y" + $int.to_string(i); });
  _block$2 = $string.join(_pipe$2, " ");
  let playlist_entries = _block$2;
  let footer_lines = listPrepend(
    "",
    listPrepend(
      "# Playlist Arrangement",
      listPrepend(
        playlist_entries,
        listPrepend(
          "",
          listPrepend(
            "# Sentinel end of song trigger",
            listPrepend("[ S-1 ] ce 127", $List$Empty$const),
          ),
        ),
      ),
    ),
  );
  let full_script = $string.join(
    $list.flatten(
      listPrepend(
        header_lines,
        listPrepend(
          listPrepend(pattern_code, $List$Empty$const),
          listPrepend(footer_lines, $List$Empty$const),
        ),
      ),
    ),
    "\n",
  );
  let duration = $int.to_float(total_steps) * 0.02;
  return new ConversionResult(
    full_script,
    song.title,
    duration,
    song.frame_count,
    total_steps,
  );
}
