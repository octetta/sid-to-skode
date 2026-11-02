import * as $gleeunit from "../gleeunit/gleeunit.mjs";
import * as $should from "../gleeunit/gleeunit/should.mjs";
import { Ok, makeError } from "./gleam.mjs";
import * as $converter from "./sid_to_skode/converter.mjs";
import * as $dump_parser from "./sid_to_skode/dump_parser.mjs";
import * as $types from "./sid_to_skode/types.mjs";
import { StereoProfile$StereoHeadphone$const } from "./sid_to_skode/types.mjs";

const FILEPATH = "test/sid_to_skode_test.gleam";

const sample_dump = "| Frame | Freq Note/Abs WF ADSR Pul | Freq Note/Abs WF ADSR Pul | Freq Note/Abs WF ADSR Pul | FCut RC Typ V |\n+-------+---------------------------+---------------------------+---------------------------+---------------+\n|     0 | 0116  ... ..  00 0000 0B8 | 0116  ... ..  00 0000 000 | 0000  ... ..  00 0000 068 | 0000 00 Off F |\n|     1 | AF58  E-7 D8  15 0DFB 180 | 2141  B-4 BB  43 0FC4 200 | 03A9  A-1 95  41 099F 168 | .... .. ... . |\n|     2 | ....  ... ..  80 .... ... | ....  ... ..  80 .... ... | ....  ... ..  .. .... 17E | .... .. ... . |\n|     3 | 0303 (F#1 92) .. .... ... | ....  ... ..  .. .... ... | ....  ... ..  .. .... 194 | .... .. ... . |\n";

export function main() {
  return $gleeunit.main();
}

export function freq_conversion_test() {
  let hz = $converter.freq_to_hz(0x1168);
  let _pipe = ((hz > 261.0) && (hz < 262.0));
  return $should.be_true(_pipe);
}

export function pulse_width_conversion_test() {
  let _pipe = $converter.pulse_to_cz(2048);
  $should.equal(_pipe, 0.0);
  let _pipe$1 = ($converter.pulse_to_cz(100) < -0.9);
  $should.be_true(_pipe$1);
  let _pipe$2 = ($converter.pulse_to_cz(4000) > 0.9);
  return $should.be_true(_pipe$2);
}

export function parse_and_convert_test() {
  let song_res = $dump_parser.parse_dump(sample_dump, "Test Tune");
  let _pipe = song_res;
  $should.be_ok(_pipe);
  let song;
  if (song_res instanceof Ok) {
    song = song_res[0];
  } else {
    throw makeError(
      "let_assert",
      FILEPATH,
      "sid_to_skode_test",
      45,
      "parse_and_convert_test",
      "Pattern match failed, no pattern matched the value.",
      {
        value: song_res,
        start: 1560,
        end: 1590,
        pattern_start: 1571,
        pattern_end: 1579
      }
    )
  }
  let _pipe$1 = song.frame_count;
  $should.equal(_pipe$1, 4);
  let res = $converter.convert_song(song, StereoProfile$StereoHeadphone$const);
  let _pipe$2 = res.title;
  $should.equal(_pipe$2, "Test Tune");
  let _pipe$3 = res.step_count;
  return $should.equal(_pipe$3, 4);
}
