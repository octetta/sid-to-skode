import gleeunit
import gleeunit/should
import sid_to_skode/converter
import sid_to_skode/dump_parser
import sid_to_skode/types.{StereoHeadphone}

pub fn main() {
  gleeunit.main()
}

pub fn freq_conversion_test() {
  // Middle C in C64 SID PAL frequency is approx $1168 = 4456 -> ~261.69 Hz
  let hz = converter.freq_to_hz(0x1168)
  // Check within 0.5 Hz of 261.6
  { hz >. 261.0 && hz <. 262.0 }
  |> should.be_true
}

pub fn pulse_width_conversion_test() {
  // 2048 (0x800) should be 0.0 (50% square)
  converter.pulse_to_cz(2048)
  |> should.equal(0.0)

  // Near 0 (thin pulse)
  { converter.pulse_to_cz(100) <. -0.9 }
  |> should.be_true

  // Near 4095 (wide pulse)
  { converter.pulse_to_cz(4000) >. 0.9 }
  |> should.be_true
}

const sample_dump: String = "| Frame | Freq Note/Abs WF ADSR Pul | Freq Note/Abs WF ADSR Pul | Freq Note/Abs WF ADSR Pul | FCut RC Typ V |
+-------+---------------------------+---------------------------+---------------------------+---------------+
|     0 | 0116  ... ..  00 0000 0B8 | 0116  ... ..  00 0000 000 | 0000  ... ..  00 0000 068 | 0000 00 Off F |
|     1 | AF58  E-7 D8  15 0DFB 180 | 2141  B-4 BB  43 0FC4 200 | 03A9  A-1 95  41 099F 168 | .... .. ... . |
|     2 | ....  ... ..  80 .... ... | ....  ... ..  80 .... ... | ....  ... ..  .. .... 17E | .... .. ... . |
|     3 | 0303 (F#1 92) .. .... ... | ....  ... ..  .. .... ... | ....  ... ..  .. .... 194 | .... .. ... . |
"

pub fn parse_and_convert_test() {
  let song_res = dump_parser.parse_dump(sample_dump, "Test Tune")
  song_res |> should.be_ok

  let assert Ok(song) = song_res
  song.frame_count |> should.equal(4)

  let res = converter.convert_song(song, StereoHeadphone)
  res.title |> should.equal("Test Tune")
  res.step_count |> should.equal(4)
}
