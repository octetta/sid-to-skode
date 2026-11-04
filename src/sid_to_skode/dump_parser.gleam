//// Pure Gleam parser for siddump text output.

import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import sid_to_skode/types.{
  type DigiEvent, type DigiSample, type DumpSong, type FilterFrame,
  type SidFrame, type VoiceFrame, DigiEvent, DigiSample, DumpSong,
  FilterFrame, SidFrame, VoiceFrame,
}

pub type ParserState {
  ParserState(
    prev_v1: VoiceFrame,
    prev_v2: VoiceFrame,
    prev_v3: VoiceFrame,
    prev_filter: FilterFrame,
    frames: List(SidFrame),
    digi_samples: List(DigiSample),
    current_sample_meta: Option(#(Int, Float, Int)),
    digi_events: List(DigiEvent),
  )
}

pub fn default_voice() -> VoiceFrame {
  VoiceFrame(
    freq: 0,
    note_name: "...",
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

pub fn default_filter() -> FilterFrame {
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

fn parse_hex(s: String, default: Int) -> Int {
  case int.base_parse(string.trim(s), 16) {
    Ok(val) -> val
    Error(_) -> default
  }
}

fn parse_voice_cell(raw: String, prev: VoiceFrame) -> VoiceFrame {
  let cell = string.trim(raw)
  let len = string.length(cell)

  // Typical cell: "AF58  E-7 D8  15 0DFB 180" or "....  ... ..  80 .... ..."
  let freq_str = string.slice(cell, 0, 4)
  let freq_is_dot = string.contains(freq_str, ".")
  let freq = case freq_is_dot {
    True -> prev.freq
    False -> parse_hex(freq_str, prev.freq)
  }
  let freq_changed = !freq_is_dot && freq != prev.freq

  // Note part is between index 4 and 15
  let note_chunk = case len >= 14 {
    True -> string.slice(cell, 5, 8)
    False -> "..."
  }
  let note_trimmed = string.trim(note_chunk)
  let note_name = case string.length(note_trimmed) > 0 {
    True -> string.slice(note_trimmed, 0, 3)
    False -> prev.note_name
  }

  // Waveform byte (2 chars hex or "..")
  let wave_chunk = case len >= 17 {
    True -> string.slice(cell, 14, 2)
    False -> ".."
  }
  let wave_is_dot = string.contains(wave_chunk, ".")
  let wave_byte = case wave_is_dot {
    True -> prev.waveform_byte
    False -> parse_hex(wave_chunk, prev.waveform_byte)
  }
  let wave_changed = !wave_is_dot && wave_byte != prev.waveform_byte

  let gate = int.bitwise_and(wave_byte, 0x01) != 0
  let sync = int.bitwise_and(wave_byte, 0x02) != 0
  let ring_mod = int.bitwise_and(wave_byte, 0x04) != 0
  let test_flag = int.bitwise_and(wave_byte, 0x08) != 0

  // ADSR (4 chars hex or "....")
  let adsr_chunk = case len >= 22 {
    True -> string.slice(cell, 17, 4)
    False -> "...."
  }
  let adsr_is_dot = string.contains(adsr_chunk, ".")
  let adsr = case adsr_is_dot {
    True -> prev.adsr
    False -> parse_hex(adsr_chunk, prev.adsr)
  }
  let adsr_changed = !adsr_is_dot && adsr != prev.adsr

  let attack = int.bitwise_and(int.bitwise_shift_right(adsr, 12), 0x0F)
  let decay = int.bitwise_and(int.bitwise_shift_right(adsr, 8), 0x0F)
  let sustain = int.bitwise_and(int.bitwise_shift_right(adsr, 4), 0x0F)
  let release = int.bitwise_and(adsr, 0x0F)

  // Pulse width (3 chars hex or "...")
  let pulse_chunk = case len >= 25 {
    True -> string.slice(cell, 22, 3)
    False -> "..."
  }
  let pulse_is_dot = string.contains(pulse_chunk, ".")
  let pulse = case pulse_is_dot {
    True -> prev.pulse_width
    False -> parse_hex(pulse_chunk, prev.pulse_width)
  }
  let pulse_changed = !pulse_is_dot && pulse != prev.pulse_width
  let gate_triggered = !wave_is_dot && gate

  VoiceFrame(
    freq: freq,
    note_name: note_name,
    semitone: 0,
    waveform_byte: wave_byte,
    gate: gate,
    sync: sync,
    ring_mod: ring_mod,
    test_bit: test_flag,
    adsr: adsr,
    attack: attack,
    decay: decay,
    sustain: sustain,
    release: release,
    pulse_width: pulse,
    freq_changed: freq_changed,
    wave_changed: wave_changed,
    adsr_changed: adsr_changed,
    pulse_changed: pulse_changed,
    gate_triggered: gate_triggered,
  )
}

fn parse_filter_cell(raw: String, prev: FilterFrame) -> FilterFrame {
  let cell = string.trim(raw)
  let len = string.length(cell)

  // Typical: "0000 00 Off F" or ".... .. ... ."
  let cutoff_chunk = string.slice(cell, 0, 4)
  let cutoff_is_dot = string.contains(cutoff_chunk, ".")
  let cutoff = case cutoff_is_dot {
    True -> prev.cutoff
    False -> parse_hex(cutoff_chunk, prev.cutoff)
  }
  let cutoff_changed = !cutoff_is_dot && cutoff != prev.cutoff

  let ctrl_chunk = case len >= 7 {
    True -> string.slice(cell, 5, 2)
    False -> ".."
  }
  let ctrl_is_dot = string.contains(ctrl_chunk, ".")
  let ctrl = case ctrl_is_dot {
    True -> prev.res_routing
    False -> parse_hex(ctrl_chunk, prev.res_routing)
  }
  let ctrl_changed = !ctrl_is_dot && ctrl != prev.res_routing

  let resonance = int.bitwise_and(int.bitwise_shift_right(ctrl, 4), 0x0F)
  let route_v1 = int.bitwise_and(ctrl, 0x01) != 0
  let route_v2 = int.bitwise_and(ctrl, 0x02) != 0
  let route_v3 = int.bitwise_and(ctrl, 0x04) != 0
  let route_ext = int.bitwise_and(ctrl, 0x08) != 0

  let mode_chunk = case len >= 11 {
    True -> string.slice(cell, 8, 3)
    False -> "..."
  }
  let mode_is_dot = string.contains(mode_chunk, ".")
  let mode_str = case mode_is_dot {
    True -> prev.mode_str
    False -> mode_chunk
  }
  let mode_changed = !mode_is_dot && mode_str != prev.mode_str

  let vol_chunk = case len >= 13 {
    True -> string.slice(cell, 12, 1)
    False -> "."
  }
  let vol_is_dot = string.contains(vol_chunk, ".")
  let volume = case vol_is_dot {
    True -> prev.volume
    False -> parse_hex(vol_chunk, prev.volume)
  }
  let vol_changed = !vol_is_dot && volume != prev.volume

  FilterFrame(
    cutoff: cutoff,
    res_routing: ctrl,
    resonance: resonance,
    route_v1: route_v1,
    route_v2: route_v2,
    route_v3: route_v3,
    route_ext: route_ext,
    mode_str: mode_str,
    volume: volume,
    cutoff_changed: cutoff_changed,
    ctrl_changed: ctrl_changed,
    mode_changed: mode_changed,
    vol_changed: vol_changed,
  )
}

fn parse_line(line: String, state: ParserState) -> Result(ParserState, Nil) {
  let trimmed = string.trim(line)
  case string.starts_with(trimmed, "# DIGI_SAMPLE ") {
    True -> {
      let parts =
        string.drop_start(trimmed, 14)
        |> string.split(" ")
        |> list.filter(fn(p) { string.length(p) > 0 })
      case parts {
        [slot_str, rate_str, len_str, ..] -> {
          case
            int.parse(slot_str),
            float.parse(rate_str),
            int.parse(len_str)
          {
            Ok(slot), Ok(rate), Ok(len) ->
              Ok(ParserState(..state, current_sample_meta: Some(#(slot, rate, len))))
            _, _, _ ->
              // In case rate was formatted as integer like 6842 without decimal point:
              case int.parse(slot_str), int.parse(rate_str), int.parse(len_str) {
                Ok(slot), Ok(rate_i), Ok(len) ->
                  Ok(ParserState(
                    ..state,
                    current_sample_meta: Some(#(slot, int.to_float(rate_i), len)),
                  ))
                _, _, _ -> Error(Nil)
              }
          }
        }
        _ -> Error(Nil)
      }
    }
    False -> {
      case string.starts_with(trimmed, "# DATA ") {
        True -> {
          case state.current_sample_meta {
            Some(#(slot, rate, len)) -> {
              let samples =
                string.drop_start(trimmed, 7)
                |> string.split(" ")
                |> list.filter_map(fn(s) {
                  let tr = string.trim(s)
                  case tr {
                    "" -> Error(Nil)
                    _ -> float.parse(tr)
                  }
                })
              let sample = DigiSample(slot, rate, len, samples)
              Ok(
                ParserState(
                  ..state,
                  digi_samples: [sample, ..state.digi_samples],
                  current_sample_meta: None,
                ),
              )
            }
            None -> Error(Nil)
          }
        }
        False -> {
          case string.starts_with(trimmed, "# DIGI_EVENT ") {
            True -> {
              let parts =
                string.drop_start(trimmed, 13)
                |> string.split(" ")
                |> list.filter(fn(p) { string.length(p) > 0 })
              case parts {
                [frame_str, slot_str, ..] -> {
                  case int.parse(frame_str), int.parse(slot_str) {
                    Ok(fr), Ok(sl) ->
                      Ok(
                        ParserState(
                          ..state,
                          digi_events: [DigiEvent(fr, sl), ..state.digi_events],
                        ),
                      )
                    _, _ -> Error(Nil)
                  }
                }
                _ -> Error(Nil)
              }
            }
            False -> {
              case
                string.starts_with(trimmed, "|")
                && !string.contains(trimmed, "Frame")
              {
                False -> Error(Nil)
                True -> {
                  let parts =
                    string.split(trimmed, "|")
                    |> list.filter(fn(p) { string.length(p) > 0 })

                  case parts {
                    [frame_str, v1_str, v2_str, v3_str, filt_str, ..] -> {
                      let frame_idx = case int.parse(string.trim(frame_str)) {
                        Ok(idx) -> idx
                        Error(_) -> list.length(state.frames)
                      }

                      let v1 = parse_voice_cell(v1_str, state.prev_v1)
                      let v2 = parse_voice_cell(v2_str, state.prev_v2)
                      let v3 = parse_voice_cell(v3_str, state.prev_v3)
                      let filt = parse_filter_cell(filt_str, state.prev_filter)

                      let frame =
                        SidFrame(
                          frame_index: frame_idx,
                          v1: v1,
                          v2: v2,
                          v3: v3,
                          filter: filt,
                        )

                      Ok(
                        ParserState(
                          ..state,
                          prev_v1: v1,
                          prev_v2: v2,
                          prev_v3: v3,
                          prev_filter: filt,
                          frames: [frame, ..state.frames],
                        ),
                      )
                    }
                    _ -> Error(Nil)
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

pub fn parse_dump(content: String, title: String) -> Result(DumpSong, String) {
  let lines = string.split(content, "\n")
  let init_state =
    ParserState(
      prev_v1: default_voice(),
      prev_v2: default_voice(),
      prev_v3: default_voice(),
      prev_filter: default_filter(),
      frames: [],
      digi_samples: [],
      current_sample_meta: None,
      digi_events: [],
    )

  let final_state =
    list.fold(lines, init_state, fn(acc, line) {
      case parse_line(line, acc) {
        Ok(next_state) -> next_state
        Error(_) -> acc
      }
    })

  let reversed_frames = list.reverse(final_state.frames)
  let count = list.length(reversed_frames)
  let frame_dict =
    list.map(reversed_frames, fn(f) { #(f.frame_index, f) })
    |> dict.from_list

  let rev_digi_events = list.reverse(final_state.digi_events)
  let digi_events_map =
    list.map(rev_digi_events, fn(ev) { #(ev.frame, ev.slot) })
    |> dict.from_list

  case count > 0 {
    True ->
      Ok(DumpSong(
        title: title,
        author: "Unknown Composer",
        copyright: "C64 SID",
        frames: reversed_frames,
        frame_dict: frame_dict,
        frame_count: count,
        frame_rate: 50.0,
        digi_samples: list.reverse(final_state.digi_samples),
        digi_events: rev_digi_events,
        digi_events_map: digi_events_map,
      ))
    False -> Error("No valid SID dump rows found in file.")
  }
}
