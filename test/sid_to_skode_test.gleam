import gleam/list
import gleam/string
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

pub fn filter_mode_mapping_test() {
  converter.filter_mode_int("Low") |> should.equal(1)
  converter.filter_mode_int("LP") |> should.equal(1)
  converter.filter_mode_int("Hig") |> should.equal(2)
  converter.filter_mode_int("HP") |> should.equal(2)
  converter.filter_mode_int("Bnd") |> should.equal(3)
  converter.filter_mode_int("BP") |> should.equal(3)
  converter.filter_mode_int("L+H") |> should.equal(4)
  converter.filter_mode_int("Not") |> should.equal(4)
  converter.filter_mode_int("LBH") |> should.equal(5)
  converter.filter_mode_int("All") |> should.equal(5)
  converter.filter_mode_int("Off") |> should.equal(0)
  converter.filter_mode_int("Unknown") |> should.equal(0)
}

pub fn filter_cutoff_and_resonance_test() {
  let hz_0 = converter.cutoff_to_hz(0)
  hz_0 |> should.equal(30.0)

  let hz_mid = converter.cutoff_to_hz(1000)
  hz_mid |> should.equal(5830.0)

  let q_0 = converter.res_to_q(0)
  q_0 |> should.equal(0.707)

  let q_15 = converter.res_to_q(15)
  { q_15 >. 7.0 } |> should.be_true
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

pub fn realtime_filter_automation_test() {
  // Frame 0: Filter off
  // Frame 1: Lowpass filter enabled on Voice 1 (v0), Cutoff 0400 (1024), Res 1
  // Frame 2: Cutoff slid to 0600 (1536)
  // Frame 3: Filter turned off
  let filter_dump =
    "| Frame | Freq Note/Abs WF ADSR Pul | Freq Note/Abs WF ADSR Pul | Freq Note/Abs WF ADSR Pul | FCut RC Typ V |
+-------+---------------------------+---------------------------+---------------------------+---------------+
|     0 | AF58  E-7 D8  15 0DFB 180 | 0000  C-0 80  43 0FC4 200 | 03A9  A-1 95  41 099F 180 | 0000 00 Off F |
|     1 | 0303 (F#1 92) 80 .... ... | ....  ... ..  .. .... ... | ....  ... ..  .. .... 196 | 0400 11 Low F |
|     2 | AF58 (E-7 D8) .. .... ... | ....  ... ..  .. .... ... | ....  ... ..  .. .... 1AC | 0600 11 Low F |
|     3 | 0303 (F#1 92) 14 .... ... | ....  ... ..  42 0000 ... | ....  ... ..  .. .... 1C2 | 0000 00 Off F |
"

  let assert Ok(song) = dump_parser.parse_dump(filter_dump, "Filter Tune")
  let assert Ok(res) = converter.convert_song(song, StereoHeadphone)

  // Must contain lowercase realtime filter commands
  string.contains(res.skode_text, "j1") |> should.be_true
  string.contains(res.skode_text, "k5969.2") |> should.be_true
  string.contains(res.skode_text, "q1.13") |> should.be_true
  string.contains(res.skode_text, "k8938.8") |> should.be_true
  string.contains(res.skode_text, "j0") |> should.be_true

  // Must NOT contain immediate-only uppercase filter commands inside pattern steps
  string.contains(res.skode_text, "] x") |> should.be_true
  string.contains(res.skode_text, " J") |> should.be_false
  string.contains(res.skode_text, " K") |> should.be_false
  string.contains(res.skode_text, " Q") |> should.be_false
}

pub fn ring_modulation_and_release_pitch_test() {
  // Voice 1: Frame 0 has WF 15 (RingMod + Triangle + Gate), Freq AF58 (2636.2 Hz)
  // Frame 1: WF 80 (Noise, Gate OFF), Freq 0303 (45.28 Hz)
  // Frame 2: Freq AF58 (2636.2 Hz) while gate is still OFF!
  // Frame 3: WF 14 (RingMod + Triangle, Gate OFF), Freq 0303
  let test_dump =
    "| Frame | Freq Note/Abs WF ADSR Pul | Freq Note/Abs WF ADSR Pul | Freq Note/Abs WF ADSR Pul | FCut RC Typ V |
+-------+---------------------------+---------------------------+---------------------------+---------------+
|     0 | AF58  E-7 D8  15 0DFB 180 | 0000  C-0 80  43 0FC4 200 | 03A9  A-1 95  41 099F 180 | 0000 00 Off F |
|     1 | 0303 (F#1 92) 80 .... ... | ....  ... ..  .. .... ... | ....  ... ..  .. .... 196 | .... .. ... . |
|     2 | AF58 (E-7 D8) .. .... ... | ....  ... ..  .. .... ... | ....  ... ..  .. .... 1AC | .... .. ... . |
|     3 | 0303 (F#1 92) 14 .... ... | ....  ... ..  42 0000 ... | ....  ... ..  .. .... 1C2 | .... .. ... . |
"

  let assert Ok(song) = dump_parser.parse_dump(test_dump, "Hubbard Tune")
  let assert Ok(res) = converter.convert_song(song, StereoHeadphone)

  // Voice 1 uses w18 analog triangle without destructive XM audio-multiplication muting
  string.contains(res.skode_text, "w18") |> should.be_true
  string.contains(res.skode_text, "XM") |> should.be_false
  string.contains(res.skode_text, "bc6") |> should.be_true

  // Release pitch modulation: pitch changes even though gate is off!
  string.contains(res.skode_text, "f45.28") |> should.be_true
  string.contains(res.skode_text, "[f2636.20] x2") |> should.be_true
}

pub fn analog_waveforms_and_headroom_test() {
  let test_dump =
    "| Frame | Freq Note/Abs WF ADSR Pul | Freq Note/Abs WF ADSR Pul | Freq Note/Abs WF ADSR Pul | FCut RC Typ V |
+-------+---------------------------+---------------------------+---------------------------+---------------+
|     0 | AF58  E-7 D8  15 0DFB 180 | 0000  C-0 80  43 0FC4 200 | 03A9  A-1 95  21 099F 180 | 0000 00 Off F |
|     1 | 0303 (F#1 92) 80 .... ... | ....  ... ..  .. .... ... | ....  ... ..  .. .... 196 | .... .. ... . |
"
  let assert Ok(song) = dump_parser.parse_dump(test_dump, "Analog Waves")
  let assert Ok(res) = converter.convert_song(song, StereoHeadphone)

  // Header must use bandlimited analog waveforms and proper headroom
  string.contains(res.skode_text, "v0 [Voice 1] vt w16 a-8") |> should.be_true
  string.contains(res.skode_text, "v1 [Voice 2] vt w15 a-8") |> should.be_true
  string.contains(res.skode_text, "v2 [Voice 3] vt w18 a-8") |> should.be_true
  string.contains(res.skode_text, "V -8") |> should.be_true

  // Step commands:
  // Voice 1 WF 15 (triangle) -> w18
  string.contains(res.skode_text, "w18") |> should.be_true
  // Voice 2 WF 43 (pulse) -> w16
  string.contains(res.skode_text, "w16") |> should.be_true
  // Voice 3 WF 21 (saw) -> w15
  string.contains(res.skode_text, "w15") |> should.be_true
  // Voice 1 WF 80 (noise) -> w5
  string.contains(res.skode_text, "w5") |> should.be_true
}

pub fn pulse_width_modulation_test() {
  let pwm_dump =
    "| Frame | Freq Note/Abs WF ADSR Pul | Freq Note/Abs WF ADSR Pul | Freq Note/Abs WF ADSR Pul | FCut RC Typ V |
+-------+---------------------------+---------------------------+---------------------------+---------------+
|     0 | AF58  E-7 D8  41 0DFB 180 | 0000  C-0 80  41 0FC4 800 | 03A9  A-1 95  41 099F 180 | 0000 00 Off F |
|     1 | ....  ... ..  .. .... 200 | ....  ... ..  .. .... ... | ....  ... ..  .. .... 196 | .... .. ... . |
"
  let assert Ok(song) = dump_parser.parse_dump(pwm_dump, "PWM Tune")
  let assert Ok(res) = converter.convert_song(song, StereoHeadphone)

  // Voice 0 starts with pulse 0x180 (384) -> CZ ~ -0.8125
  // Frame 1 updates to 0x200 (512) -> CZ -0.75
  // Must contain phase distortion modulation c1,... on pulse wave w16
  string.contains(res.skode_text, "c1,") |> should.be_true
}

pub fn no_vt_in_pattern_steps_test() {
  // Drums and chord changes with active gate
  let drum_dump =
    "| Frame | Freq Note/Abs WF ADSR Pul | Freq Note/Abs WF ADSR Pul | Freq Note/Abs WF ADSR Pul | FCut RC Typ V |
+-------+---------------------------+---------------------------+---------------------------+---------------+
|     0 | 022C  C-1 8C  81 0720 000 | 05C8  F-2 9D  41 0800 05A | 0B90  F-3 A9  41 0500 05A | 0000 00 Off F |
|     1 | 332C (G-5 C3) .. 0820 ... | ....  ... ..  .. .... 0B4 | ....  ... ..  .. .... 0B4 | .... .. ... . |
|     2 | 022C (C-1 8C) .. 0300 ... | ....  ... ..  .. .... 10E | ....  ... ..  .. .... 10E | .... .. ... . |
"
  let assert Ok(song) = dump_parser.parse_dump(drum_dump, "Whittaker Drums")
  let assert Ok(res) = converter.convert_song(song, StereoHeadphone)

  // Pattern steps MUST NOT contain immediate-only 'vt'
  // (e.g. '[vt ...]' causes # 'vt' is immediate-only and cannot be compiled into a pattern step)
  let pattern_lines =
    string.split(res.skode_text, "\n")
    |> list.filter(fn(line) { string.contains(line, "] x") })

  let has_vt_in_steps =
    list.any(pattern_lines, fn(line) { string.contains(line, "vt") })
  has_vt_in_steps |> should.be_false

  // ADSR change while gate is active must trigger 'l1'
  string.contains(res.skode_text, "l1") |> should.be_true
}

pub fn voice_panning_test() {
  let sample_dump =
    "| Frame | Freq Note/Abs WF ADSR Pul | Freq Note/Abs WF ADSR Pul | Freq Note/Abs WF ADSR Pul | FCut RC Typ V |
+-------+---------------------------+---------------------------+---------------------------+---------------+
|     0 | AF58  E-7 D8  15 0DFB 180 | 0000  C-0 80  43 0FC4 200 | 03A9  A-1 95  41 099F 180 | 0000 00 Off F |
"
  let assert Ok(song) = dump_parser.parse_dump(sample_dump, "Pan Tune")

  // Test custom floating-point stereo pan (e.g. v0 p-1.0, v1 p1.0, v2 p0.25)
  let assert Ok(res) =
    converter.convert_song(song, types.StereoCustom(-1.0, 1.0, 0.25))
  string.contains(
    res.skode_text,
    "v0 [Voice 1] vt w16 a-8 t0.004,0.008,0.5,0.012 p-1.00",
  )
  |> should.be_true
  string.contains(
    res.skode_text,
    "v1 [Voice 2] vt w15 a-8 t0.004,0.008,0.5,0.012 p1.00",
  )
  |> should.be_true
  string.contains(
    res.skode_text,
    "v2 [Voice 3] vt w18 a-8 t0.004,0.008,0.5,0.012 p0.25",
  )
  |> should.be_true

  // Test anti-click float formatting and leading zero padding
  converter.format_float(0.004, 3) |> should.equal("0.004")
  converter.format_float(0.012, 3) |> should.equal("0.012")
  converter.format_float(0.5, 2) |> should.equal("0.50")
  converter.format_float(-0.6, 2) |> should.equal("-0.60")
  converter.format_float(0.0, 2) |> should.equal("0.00")

  // Test live commands
  converter.build_voice_pan_command(0, -1.0) |> should.equal("v0 p-1.00")
  converter.build_voice_pan_command(1, 0.75) |> should.equal("v1 p0.75")
  converter.build_voice_pan_command(2, 0.0) |> should.equal("v2 p0.00")
  converter.build_live_stereo_command(types.StereoCustom(-0.5, 0.5, 0.0))
  |> should.equal("v0 p-0.50; v1 p0.50; v2 p0.00")
}

pub fn combo_waveforms_priority_test() {
  // Voice 1: WF 31 (Saw + Tri + Gate) -> w15 (Analog Saw)
  // Voice 2: WF 61 (Saw + Pulse + Gate) -> w15 (Analog Saw)
  // Voice 3: WF 51 (Tri + Pulse + Gate) -> w16 (Analog Pulse)
  let dump =
    "| Frame | Freq Note/Abs WF ADSR Pul | Freq Note/Abs WF ADSR Pul | Freq Note/Abs WF ADSR Pul | FCut RC Typ V |
+-------+---------------------------+---------------------------+---------------------------+---------------+
|     0 | AF58  E-7 D8  31 0DFB 180 | 0000  C-0 80  61 0FC4 200 | 03A9  A-1 95  51 099F 180 | 0000 00 Off F |
|     1 | ....  ... ..  71 .... ... | ....  ... ..  .. .... ... | ....  ... ..  .. .... ... | .... .. ... . |
"
  let assert Ok(song) = dump_parser.parse_dump(dump, "Combo Waves")
  let assert Ok(res) = converter.convert_song(song, StereoHeadphone)

  // Must map to clean bandlimited analog waveforms without DC clicks
  string.contains(res.skode_text, "w15") |> should.be_true
  string.contains(res.skode_text, "w16") |> should.be_true
}
