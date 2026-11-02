import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $string from "../../gleam_stdlib/gleam/string.mjs";
import {
  Ok,
  Error,
  Empty as $Empty,
  List$Empty$const as $List$Empty$const,
  prepend as listPrepend,
  CustomType as $CustomType,
} from "../gleam.mjs";
import * as $types from "../sid_to_skode/types.mjs";
import { DumpSong, FilterFrame, SidFrame, VoiceFrame } from "../sid_to_skode/types.mjs";

export class ParserState extends $CustomType {
  constructor(prev_v1, prev_v2, prev_v3, prev_filter, frames) {
    super();
    this.prev_v1 = prev_v1;
    this.prev_v2 = prev_v2;
    this.prev_v3 = prev_v3;
    this.prev_filter = prev_filter;
    this.frames = frames;
  }
}
export const ParserState$ParserState = (prev_v1, prev_v2, prev_v3, prev_filter, frames) =>
  new ParserState(prev_v1, prev_v2, prev_v3, prev_filter, frames);
export const ParserState$isParserState = (value) =>
  value instanceof ParserState;
export const ParserState$ParserState$prev_v1 = (value) => value.prev_v1;
export const ParserState$ParserState$0 = (value) => value.prev_v1;
export const ParserState$ParserState$prev_v2 = (value) => value.prev_v2;
export const ParserState$ParserState$1 = (value) => value.prev_v2;
export const ParserState$ParserState$prev_v3 = (value) => value.prev_v3;
export const ParserState$ParserState$2 = (value) => value.prev_v3;
export const ParserState$ParserState$prev_filter = (value) => value.prev_filter;
export const ParserState$ParserState$3 = (value) => value.prev_filter;
export const ParserState$ParserState$frames = (value) => value.frames;
export const ParserState$ParserState$4 = (value) => value.frames;

export function default_voice() {
  return new VoiceFrame(
    0,
    "...",
    0,
    0,
    false,
    false,
    false,
    false,
    0,
    0,
    0,
    0,
    0,
    2048,
    false,
    false,
    false,
    false,
  );
}

export function default_filter() {
  return new FilterFrame(
    0,
    0,
    0,
    false,
    false,
    false,
    false,
    "Off",
    15,
    false,
    false,
    false,
    false,
  );
}

function parse_hex(s, default$) {
  let $ = $int.base_parse($string.trim(s), 16);
  if ($ instanceof Ok) {
    let val = $[0];
    return val;
  } else {
    return default$;
  }
}

function parse_voice_cell(raw, prev) {
  let cell = $string.trim(raw);
  let len = $string.length(cell);
  let freq_str = $string.slice(cell, 0, 4);
  let freq_is_dot = $string.contains(freq_str, ".");
  let _block;
  if (freq_is_dot) {
    _block = prev.freq;
  } else {
    _block = parse_hex(freq_str, prev.freq);
  }
  let freq = _block;
  let freq_changed = !freq_is_dot && (freq !== prev.freq);
  let _block$1;
  let $ = len >= 14;
  if ($) {
    _block$1 = $string.slice(cell, 5, 8);
  } else {
    _block$1 = "...";
  }
  let note_chunk = _block$1;
  let note_trimmed = $string.trim(note_chunk);
  let _block$2;
  let $1 = $string.length(note_trimmed) > 0;
  if ($1) {
    _block$2 = $string.slice(note_trimmed, 0, 3);
  } else {
    _block$2 = prev.note_name;
  }
  let note_name = _block$2;
  let _block$3;
  let $2 = len >= 17;
  if ($2) {
    _block$3 = $string.slice(cell, 14, 2);
  } else {
    _block$3 = "..";
  }
  let wave_chunk = _block$3;
  let wave_is_dot = $string.contains(wave_chunk, ".");
  let _block$4;
  if (wave_is_dot) {
    _block$4 = prev.waveform_byte;
  } else {
    _block$4 = parse_hex(wave_chunk, prev.waveform_byte);
  }
  let wave_byte = _block$4;
  let wave_changed = !wave_is_dot && (wave_byte !== prev.waveform_byte);
  let gate = $int.bitwise_and(wave_byte, 0x1) !== 0;
  let sync = $int.bitwise_and(wave_byte, 0x2) !== 0;
  let ring_mod = $int.bitwise_and(wave_byte, 0x4) !== 0;
  let test_flag = $int.bitwise_and(wave_byte, 0x8) !== 0;
  let _block$5;
  let $3 = len >= 22;
  if ($3) {
    _block$5 = $string.slice(cell, 17, 4);
  } else {
    _block$5 = "....";
  }
  let adsr_chunk = _block$5;
  let adsr_is_dot = $string.contains(adsr_chunk, ".");
  let _block$6;
  if (adsr_is_dot) {
    _block$6 = prev.adsr;
  } else {
    _block$6 = parse_hex(adsr_chunk, prev.adsr);
  }
  let adsr = _block$6;
  let adsr_changed = !adsr_is_dot && (adsr !== prev.adsr);
  let attack = $int.bitwise_and($int.bitwise_shift_right(adsr, 12), 0xF);
  let decay = $int.bitwise_and($int.bitwise_shift_right(adsr, 8), 0xF);
  let sustain = $int.bitwise_and($int.bitwise_shift_right(adsr, 4), 0xF);
  let release = $int.bitwise_and(adsr, 0xF);
  let _block$7;
  let $4 = len >= 26;
  if ($4) {
    _block$7 = $string.slice(cell, 22, 3);
  } else {
    _block$7 = "...";
  }
  let pulse_chunk = _block$7;
  let pulse_is_dot = $string.contains(pulse_chunk, ".");
  let _block$8;
  if (pulse_is_dot) {
    _block$8 = prev.pulse_width;
  } else {
    _block$8 = parse_hex(pulse_chunk, prev.pulse_width);
  }
  let pulse = _block$8;
  let pulse_changed = !pulse_is_dot && (pulse !== prev.pulse_width);
  return new VoiceFrame(
    freq,
    note_name,
    0,
    wave_byte,
    gate,
    sync,
    ring_mod,
    test_flag,
    adsr,
    attack,
    decay,
    sustain,
    release,
    pulse,
    freq_changed,
    wave_changed,
    adsr_changed,
    pulse_changed,
  );
}

function parse_filter_cell(raw, prev) {
  let cell = $string.trim(raw);
  let len = $string.length(cell);
  let cutoff_chunk = $string.slice(cell, 0, 4);
  let cutoff_is_dot = $string.contains(cutoff_chunk, ".");
  let _block;
  if (cutoff_is_dot) {
    _block = prev.cutoff;
  } else {
    _block = parse_hex(cutoff_chunk, prev.cutoff);
  }
  let cutoff = _block;
  let cutoff_changed = !cutoff_is_dot && (cutoff !== prev.cutoff);
  let _block$1;
  let $ = len >= 7;
  if ($) {
    _block$1 = $string.slice(cell, 5, 2);
  } else {
    _block$1 = "..";
  }
  let ctrl_chunk = _block$1;
  let ctrl_is_dot = $string.contains(ctrl_chunk, ".");
  let _block$2;
  if (ctrl_is_dot) {
    _block$2 = prev.res_routing;
  } else {
    _block$2 = parse_hex(ctrl_chunk, prev.res_routing);
  }
  let ctrl = _block$2;
  let ctrl_changed = !ctrl_is_dot && (ctrl !== prev.res_routing);
  let resonance = $int.bitwise_and($int.bitwise_shift_right(ctrl, 4), 0xF);
  let route_v1 = $int.bitwise_and(ctrl, 0x1) !== 0;
  let route_v2 = $int.bitwise_and(ctrl, 0x2) !== 0;
  let route_v3 = $int.bitwise_and(ctrl, 0x4) !== 0;
  let route_ext = $int.bitwise_and(ctrl, 0x8) !== 0;
  let _block$3;
  let $1 = len >= 11;
  if ($1) {
    _block$3 = $string.slice(cell, 8, 3);
  } else {
    _block$3 = "...";
  }
  let mode_chunk = _block$3;
  let mode_is_dot = $string.contains(mode_chunk, ".");
  let _block$4;
  if (mode_is_dot) {
    _block$4 = prev.mode_str;
  } else {
    _block$4 = mode_chunk;
  }
  let mode_str = _block$4;
  let mode_changed = !mode_is_dot && (mode_str !== prev.mode_str);
  let _block$5;
  let $2 = len >= 13;
  if ($2) {
    _block$5 = $string.slice(cell, 12, 1);
  } else {
    _block$5 = ".";
  }
  let vol_chunk = _block$5;
  let vol_is_dot = $string.contains(vol_chunk, ".");
  let _block$6;
  if (vol_is_dot) {
    _block$6 = prev.volume;
  } else {
    _block$6 = parse_hex(vol_chunk, prev.volume);
  }
  let volume = _block$6;
  let vol_changed = !vol_is_dot && (volume !== prev.volume);
  return new FilterFrame(
    cutoff,
    ctrl,
    resonance,
    route_v1,
    route_v2,
    route_v3,
    route_ext,
    mode_str,
    volume,
    cutoff_changed,
    ctrl_changed,
    mode_changed,
    vol_changed,
  );
}

function parse_line(line, state) {
  let trimmed = $string.trim(line);
  let $ = $string.starts_with(trimmed, "|") && !$string.contains(
    trimmed,
    "Frame",
  );
  if ($) {
    let _block;
    let _pipe = $string.split(trimmed, "|");
    _block = $list.filter(_pipe, (p) => { return $string.length(p) > 0; });
    let parts = _block;
    if (parts instanceof $Empty) {
      return new Error(undefined);
    } else {
      let $1 = parts.tail;
      if ($1 instanceof $Empty) {
        return new Error(undefined);
      } else {
        let $2 = $1.tail;
        if ($2 instanceof $Empty) {
          return new Error(undefined);
        } else {
          let $3 = $2.tail;
          if ($3 instanceof $Empty) {
            return new Error(undefined);
          } else {
            let $4 = $3.tail;
            if ($4 instanceof $Empty) {
              return new Error(undefined);
            } else {
              let frame_str = parts.head;
              let v1_str = $1.head;
              let v2_str = $2.head;
              let v3_str = $3.head;
              let filt_str = $4.head;
              let _block$1;
              let $5 = $int.parse($string.trim(frame_str));
              if ($5 instanceof Ok) {
                let idx = $5[0];
                _block$1 = idx;
              } else {
                _block$1 = $list.length(state.frames);
              }
              let frame_idx = _block$1;
              let v1 = parse_voice_cell(v1_str, state.prev_v1);
              let v2 = parse_voice_cell(v2_str, state.prev_v2);
              let v3 = parse_voice_cell(v3_str, state.prev_v3);
              let filt = parse_filter_cell(filt_str, state.prev_filter);
              let frame = new SidFrame(frame_idx, v1, v2, v3, filt);
              return new Ok(
                new ParserState(
                  v1,
                  v2,
                  v3,
                  filt,
                  listPrepend(frame, state.frames),
                ),
              );
            }
          }
        }
      }
    }
  } else {
    return new Error(undefined);
  }
}

export function parse_dump(content, title) {
  let lines = $string.split(content, "\n");
  let init_state = new ParserState(
    default_voice(),
    default_voice(),
    default_voice(),
    default_filter(),
    $List$Empty$const,
  );
  let final_state = $list.fold(
    lines,
    init_state,
    (acc, line) => {
      let $ = parse_line(line, acc);
      if ($ instanceof Ok) {
        let next_state = $[0];
        return next_state;
      } else {
        return acc;
      }
    },
  );
  let reversed_frames = $list.reverse(final_state.frames);
  let count = $list.length(reversed_frames);
  let $ = count > 0;
  if ($) {
    return new Ok(
      new DumpSong(
        title,
        "Unknown Composer",
        "C64 SID",
        reversed_frames,
        count,
        50.0,
      ),
    );
  } else {
    return new Error("No valid SID dump rows found in file.");
  }
}
