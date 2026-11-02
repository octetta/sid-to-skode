//// Core domain models and Lustre UI types for sid-to-skode.

import gleam/option.{type Option}

pub type StereoProfile {
  StereoHeadphone
  StereoAmiga
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
    skode_code: String,
    title: String,
    duration_seconds: Float,
    frame_count: Int,
    step_count: Int,
  )
}

pub type DeepSidTrack {
  DeepSidTrack(
    id: Int,
    name: String,
    author: String,
    copyright: String,
    file_path: String,
    subtunes: Int,
  )
}

pub type ActiveTab {
  TabStudio
  TabSkodeSource
  TabDeepSidBrowser
  TabDumpView
}

pub type Model {
  Model(
    engine_ready: Bool,
    is_playing: Bool,
    is_paused: Bool,
    current_step: Int,
    total_steps: Int,
    master_volume_db: Float,
    stereo_profile: StereoProfile,
    active_tab: ActiveTab,
    loaded_song: Option(DumpSong),
    conversion: Option(ConversionResult),
    is_converting: Bool,
    error_message: Option(String),
    raw_dump_text: String,
    deep_sid_query: String,
    deep_sid_results: List(DeepSidTrack),
    is_searching: Bool,
  )
}

pub type Msg {
  EngineReady
  UserLoadedDump(name: String, content: String)
  UserTriggerPlay
  UserTriggerPause
  UserTriggerStop
  UserSetStereo(StereoProfile)
  UserSetVolume(Float)
  UserSelectTab(ActiveTab)
  EngineStepUpdated(Int)
  EnginePlaybackEnded
  SearchDeepSid(String)
  DeepSidSearchResults(Result(List(DeepSidTrack), String))
  LoadDeepSidTrack(DeepSidTrack)
  DeepSidTrackDownloaded(Result(String, String))
  CopySkodeToClipboard
  DownloadSkodeFile
  DismissError
}
