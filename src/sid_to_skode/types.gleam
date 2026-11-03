//// Domain models and Lustre UI types for sid-to-skode.

import gleam/dict.{type Dict}
import gleam/option.{type Option}

pub type StereoMode {
  StereoHeadphone
  StereoWide
  StereoMono
}

pub type SidWaveform {
  WaveNone
  WaveTriangle
  WaveSawtooth
  WavePulse
  WaveNoise
  WaveSawPulse
  WaveTriPulse
  WaveSawTri
  WaveAllCombos
  WaveCustom(Int)
}

pub type VoiceFrame {
  VoiceFrame(
    freq: Int,
    note_name: String,
    semitone: Int,
    waveform_byte: Int,
    gate: Bool,
    sync: Bool,
    ring_mod: Bool,
    test_bit: Bool,
    adsr: Int,
    attack: Int,
    decay: Int,
    sustain: Int,
    release: Int,
    pulse_width: Int,
    freq_changed: Bool,
    wave_changed: Bool,
    adsr_changed: Bool,
    pulse_changed: Bool,
  )
}

pub type FilterFrame {
  FilterFrame(
    cutoff: Int,
    res_routing: Int,
    resonance: Int,
    route_v1: Bool,
    route_v2: Bool,
    route_v3: Bool,
    route_ext: Bool,
    mode_str: String,
    volume: Int,
    cutoff_changed: Bool,
    ctrl_changed: Bool,
    mode_changed: Bool,
    vol_changed: Bool,
  )
}

pub type SidFrame {
  SidFrame(
    frame_index: Int,
    v1: VoiceFrame,
    v2: VoiceFrame,
    v3: VoiceFrame,
    filter: FilterFrame,
  )
}

pub type DumpSong {
  DumpSong(
    title: String,
    author: String,
    copyright: String,
    frames: List(SidFrame),
    frame_count: Int,
    frame_rate: Float,
  )
}

pub type ConversionResult {
  ConversionResult(
    skode_text: String,
    total_steps: Int,
    duration_seconds: Float,
    step_times: Dict(Int, Float),
  )
}

pub type SidCatalogInfo {
  SidCatalogInfo(
    title: String,
    author: String,
    filename: String,
    source: String,
  )
}

pub type Model {
  Model(
    engine_ready: Bool,
    is_playing: Bool,
    is_paused: Bool,
    current_step: Int,
    active_song: Option(DumpSong),
    conversion: Option(ConversionResult),
    is_converting: Bool,
    error_message: Option(String),
    status_text: String,
    active_tab: String,
    catalog_info: Option(SidCatalogInfo),
    stereo_mode: StereoMode,
    master_volume: Int,
    raw_dump_text: String,
    source_description: String,
    hvsc_path: Option(String),
  )
}

pub type Msg {
  EngineStatusChanged(Bool)
  FileDropped(name: String, data: BitArray)
  DumpTextReady(
    name: String,
    dump_text: String,
    source_desc: String,
    hvsc_path: String,
  )
  PlayClicked
  PauseClicked
  ResumeClicked
  StopClicked
  PlaybackStepChanged(step: Int, total_steps: Int)
  PlaybackEnded
  DownloadSkodeClicked
  ResetClicked
  TabSelected(String)
  PanicClicked
  LoadDemo(url: String, filename: String, title: String, author: String)
  RandomSidClicked
  StereoModeChanged(StereoMode)
  MasterVolumeChanged(Int)
  CopySkodeClicked
  ConversionFailed(String)
  ToggleReplClicked
}
