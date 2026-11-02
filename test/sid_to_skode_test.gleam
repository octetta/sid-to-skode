import gleeunit
import gleeunit/should
import sid_to_skode/converter
import sid_to_skode/dump_parser
import sid_to_skode/types.{StereoHeadphone}

pub fn main() {
  gleeunit.main()
}

pub fn freq_conversion_test() {
  let hz = converter.freq_to_hz(0x1168)
  // 0x1168 = 4456 * 0.0587285 ≈ 261.69 Hz (Middle C)
  { hz >. 261.0 && hz <. 262.0 }
  |> should.be_true
}

pub fn pulse_cz_conversion_test() {
  // 2048 should be exact 0.0 (50% square)
  let cz_mid = converter.pulse_to_cz(2048)
  cz_mid |> should.equal(0.0)

  // 4095 should be clamped to 0.98
  let cz_max = converter.pulse_to_cz(4095)
  cz_max |> should.equal(0.98)

  // 0 should be clamped to -0.98
  let cz_min = converter.pulse_to_cz(0)
  cz_min |> should.equal(-0.98)
}

pub fn dump_parse_and_convert_test() {
  let sample_dump =
    "| Frame | Freq Note/Abs WF ADSR Pul | Freq Note/Abs WF ADSR Pul | Freq Note/Abs WF ADSR Pul | FCut RC Typ V |
+-------+---------------------------+---------------------------+---------------------------+---------------+
|     0 | AF58  E-7 D8  15 0DFB 180 | 0000  C-0 80  43 0FC4 200 | 03A9  A-1 95  41 099F 180 | 0000 00 Off F |
|     1 | 0303 (F#1 92) 80 .... ... | ....  ... ..  .. .... ... | ....  ... ..  .. .... 196 | .... .. ... . |
|     2 | AF58 (E-7 D8) .. .... ... | ....  ... ..  .. .... ... | ....  ... ..  .. .... 1AC | .... .. ... . |
|     3 | 0303 (F#1 92) 14 .... ... | ....  ... ..  42 0000 ... | ....  ... ..  .. .... 1C2 | .... .. ... . |
"

  let assert Ok(song) = dump_parser.parse_dump(sample_dump, "Test Tune")
  song.frame_count |> should.equal(4)

  let assert Ok(res) = converter.convert_song(song, StereoHeadphone)
  res.total_steps |> should.equal(5)
  res.duration_seconds |> should.equal(0.08)
}
