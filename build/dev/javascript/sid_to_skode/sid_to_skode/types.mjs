import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { CustomType as $CustomType } from "../gleam.mjs";

export class StereoHeadphone extends $CustomType {}
export const StereoProfile$StereoHeadphone$const = new StereoHeadphone();
export const StereoProfile$StereoHeadphone = () =>
  StereoProfile$StereoHeadphone$const;
export const StereoProfile$isStereoHeadphone = (value) =>
  value instanceof StereoHeadphone;

export class StereoAmiga extends $CustomType {}
export const StereoProfile$StereoAmiga$const = new StereoAmiga();
export const StereoProfile$StereoAmiga = () => StereoProfile$StereoAmiga$const;
export const StereoProfile$isStereoAmiga = (value) =>
  value instanceof StereoAmiga;

export class StereoMono extends $CustomType {}
export const StereoProfile$StereoMono$const = new StereoMono();
export const StereoProfile$StereoMono = () => StereoProfile$StereoMono$const;
export const StereoProfile$isStereoMono = (value) =>
  value instanceof StereoMono;

export class WaveNone extends $CustomType {}
export const SidWaveform$WaveNone$const = new WaveNone();
export const SidWaveform$WaveNone = () => SidWaveform$WaveNone$const;
export const SidWaveform$isWaveNone = (value) => value instanceof WaveNone;

export class WaveTriangle extends $CustomType {}
export const SidWaveform$WaveTriangle$const = new WaveTriangle();
export const SidWaveform$WaveTriangle = () => SidWaveform$WaveTriangle$const;
export const SidWaveform$isWaveTriangle = (value) =>
  value instanceof WaveTriangle;

export class WaveSawtooth extends $CustomType {}
export const SidWaveform$WaveSawtooth$const = new WaveSawtooth();
export const SidWaveform$WaveSawtooth = () => SidWaveform$WaveSawtooth$const;
export const SidWaveform$isWaveSawtooth = (value) =>
  value instanceof WaveSawtooth;

export class WavePulse extends $CustomType {}
export const SidWaveform$WavePulse$const = new WavePulse();
export const SidWaveform$WavePulse = () => SidWaveform$WavePulse$const;
export const SidWaveform$isWavePulse = (value) => value instanceof WavePulse;

export class WaveNoise extends $CustomType {}
export const SidWaveform$WaveNoise$const = new WaveNoise();
export const SidWaveform$WaveNoise = () => SidWaveform$WaveNoise$const;
export const SidWaveform$isWaveNoise = (value) => value instanceof WaveNoise;

export class WaveSawPulse extends $CustomType {}
export const SidWaveform$WaveSawPulse$const = new WaveSawPulse();
export const SidWaveform$WaveSawPulse = () => SidWaveform$WaveSawPulse$const;
export const SidWaveform$isWaveSawPulse = (value) =>
  value instanceof WaveSawPulse;

export class WaveTriPulse extends $CustomType {}
export const SidWaveform$WaveTriPulse$const = new WaveTriPulse();
export const SidWaveform$WaveTriPulse = () => SidWaveform$WaveTriPulse$const;
export const SidWaveform$isWaveTriPulse = (value) =>
  value instanceof WaveTriPulse;

export class WaveSawTri extends $CustomType {}
export const SidWaveform$WaveSawTri$const = new WaveSawTri();
export const SidWaveform$WaveSawTri = () => SidWaveform$WaveSawTri$const;
export const SidWaveform$isWaveSawTri = (value) => value instanceof WaveSawTri;

export class WaveAllCombos extends $CustomType {}
export const SidWaveform$WaveAllCombos$const = new WaveAllCombos();
export const SidWaveform$WaveAllCombos = () => SidWaveform$WaveAllCombos$const;
export const SidWaveform$isWaveAllCombos = (value) =>
  value instanceof WaveAllCombos;

export class WaveCustom extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const SidWaveform$WaveCustom = ($0) => new WaveCustom($0);
export const SidWaveform$isWaveCustom = (value) => value instanceof WaveCustom;
export const SidWaveform$WaveCustom$0 = (value) => value[0];

export class VoiceFrame extends $CustomType {
  constructor(freq, note_name, semitone, waveform_byte, gate, sync, ring_mod, test_bit, adsr, attack, decay, sustain, release, pulse_width, freq_changed, wave_changed, adsr_changed, pulse_changed) {
    super();
    this.freq = freq;
    this.note_name = note_name;
    this.semitone = semitone;
    this.waveform_byte = waveform_byte;
    this.gate = gate;
    this.sync = sync;
    this.ring_mod = ring_mod;
    this.test_bit = test_bit;
    this.adsr = adsr;
    this.attack = attack;
    this.decay = decay;
    this.sustain = sustain;
    this.release = release;
    this.pulse_width = pulse_width;
    this.freq_changed = freq_changed;
    this.wave_changed = wave_changed;
    this.adsr_changed = adsr_changed;
    this.pulse_changed = pulse_changed;
  }
}
export const VoiceFrame$VoiceFrame = (freq, note_name, semitone, waveform_byte, gate, sync, ring_mod, test_bit, adsr, attack, decay, sustain, release, pulse_width, freq_changed, wave_changed, adsr_changed, pulse_changed) =>
  new VoiceFrame(freq,
  note_name,
  semitone,
  waveform_byte,
  gate,
  sync,
  ring_mod,
  test_bit,
  adsr,
  attack,
  decay,
  sustain,
  release,
  pulse_width,
  freq_changed,
  wave_changed,
  adsr_changed,
  pulse_changed);
export const VoiceFrame$isVoiceFrame = (value) => value instanceof VoiceFrame;
export const VoiceFrame$VoiceFrame$freq = (value) => value.freq;
export const VoiceFrame$VoiceFrame$0 = (value) => value.freq;
export const VoiceFrame$VoiceFrame$note_name = (value) => value.note_name;
export const VoiceFrame$VoiceFrame$1 = (value) => value.note_name;
export const VoiceFrame$VoiceFrame$semitone = (value) => value.semitone;
export const VoiceFrame$VoiceFrame$2 = (value) => value.semitone;
export const VoiceFrame$VoiceFrame$waveform_byte = (value) =>
  value.waveform_byte;
export const VoiceFrame$VoiceFrame$3 = (value) => value.waveform_byte;
export const VoiceFrame$VoiceFrame$gate = (value) => value.gate;
export const VoiceFrame$VoiceFrame$4 = (value) => value.gate;
export const VoiceFrame$VoiceFrame$sync = (value) => value.sync;
export const VoiceFrame$VoiceFrame$5 = (value) => value.sync;
export const VoiceFrame$VoiceFrame$ring_mod = (value) => value.ring_mod;
export const VoiceFrame$VoiceFrame$6 = (value) => value.ring_mod;
export const VoiceFrame$VoiceFrame$test_bit = (value) => value.test_bit;
export const VoiceFrame$VoiceFrame$7 = (value) => value.test_bit;
export const VoiceFrame$VoiceFrame$adsr = (value) => value.adsr;
export const VoiceFrame$VoiceFrame$8 = (value) => value.adsr;
export const VoiceFrame$VoiceFrame$attack = (value) => value.attack;
export const VoiceFrame$VoiceFrame$9 = (value) => value.attack;
export const VoiceFrame$VoiceFrame$decay = (value) => value.decay;
export const VoiceFrame$VoiceFrame$10 = (value) => value.decay;
export const VoiceFrame$VoiceFrame$sustain = (value) => value.sustain;
export const VoiceFrame$VoiceFrame$11 = (value) => value.sustain;
export const VoiceFrame$VoiceFrame$release = (value) => value.release;
export const VoiceFrame$VoiceFrame$12 = (value) => value.release;
export const VoiceFrame$VoiceFrame$pulse_width = (value) => value.pulse_width;
export const VoiceFrame$VoiceFrame$13 = (value) => value.pulse_width;
export const VoiceFrame$VoiceFrame$freq_changed = (value) => value.freq_changed;
export const VoiceFrame$VoiceFrame$14 = (value) => value.freq_changed;
export const VoiceFrame$VoiceFrame$wave_changed = (value) => value.wave_changed;
export const VoiceFrame$VoiceFrame$15 = (value) => value.wave_changed;
export const VoiceFrame$VoiceFrame$adsr_changed = (value) => value.adsr_changed;
export const VoiceFrame$VoiceFrame$16 = (value) => value.adsr_changed;
export const VoiceFrame$VoiceFrame$pulse_changed = (value) =>
  value.pulse_changed;
export const VoiceFrame$VoiceFrame$17 = (value) => value.pulse_changed;

export class FilterFrame extends $CustomType {
  constructor(cutoff, res_routing, resonance, route_v1, route_v2, route_v3, route_ext, mode_str, volume, cutoff_changed, ctrl_changed, mode_changed, vol_changed) {
    super();
    this.cutoff = cutoff;
    this.res_routing = res_routing;
    this.resonance = resonance;
    this.route_v1 = route_v1;
    this.route_v2 = route_v2;
    this.route_v3 = route_v3;
    this.route_ext = route_ext;
    this.mode_str = mode_str;
    this.volume = volume;
    this.cutoff_changed = cutoff_changed;
    this.ctrl_changed = ctrl_changed;
    this.mode_changed = mode_changed;
    this.vol_changed = vol_changed;
  }
}
export const FilterFrame$FilterFrame = (cutoff, res_routing, resonance, route_v1, route_v2, route_v3, route_ext, mode_str, volume, cutoff_changed, ctrl_changed, mode_changed, vol_changed) =>
  new FilterFrame(cutoff,
  res_routing,
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
  vol_changed);
export const FilterFrame$isFilterFrame = (value) =>
  value instanceof FilterFrame;
export const FilterFrame$FilterFrame$cutoff = (value) => value.cutoff;
export const FilterFrame$FilterFrame$0 = (value) => value.cutoff;
export const FilterFrame$FilterFrame$res_routing = (value) => value.res_routing;
export const FilterFrame$FilterFrame$1 = (value) => value.res_routing;
export const FilterFrame$FilterFrame$resonance = (value) => value.resonance;
export const FilterFrame$FilterFrame$2 = (value) => value.resonance;
export const FilterFrame$FilterFrame$route_v1 = (value) => value.route_v1;
export const FilterFrame$FilterFrame$3 = (value) => value.route_v1;
export const FilterFrame$FilterFrame$route_v2 = (value) => value.route_v2;
export const FilterFrame$FilterFrame$4 = (value) => value.route_v2;
export const FilterFrame$FilterFrame$route_v3 = (value) => value.route_v3;
export const FilterFrame$FilterFrame$5 = (value) => value.route_v3;
export const FilterFrame$FilterFrame$route_ext = (value) => value.route_ext;
export const FilterFrame$FilterFrame$6 = (value) => value.route_ext;
export const FilterFrame$FilterFrame$mode_str = (value) => value.mode_str;
export const FilterFrame$FilterFrame$7 = (value) => value.mode_str;
export const FilterFrame$FilterFrame$volume = (value) => value.volume;
export const FilterFrame$FilterFrame$8 = (value) => value.volume;
export const FilterFrame$FilterFrame$cutoff_changed = (value) =>
  value.cutoff_changed;
export const FilterFrame$FilterFrame$9 = (value) => value.cutoff_changed;
export const FilterFrame$FilterFrame$ctrl_changed = (value) =>
  value.ctrl_changed;
export const FilterFrame$FilterFrame$10 = (value) => value.ctrl_changed;
export const FilterFrame$FilterFrame$mode_changed = (value) =>
  value.mode_changed;
export const FilterFrame$FilterFrame$11 = (value) => value.mode_changed;
export const FilterFrame$FilterFrame$vol_changed = (value) => value.vol_changed;
export const FilterFrame$FilterFrame$12 = (value) => value.vol_changed;

export class SidFrame extends $CustomType {
  constructor(frame_index, v1, v2, v3, filter) {
    super();
    this.frame_index = frame_index;
    this.v1 = v1;
    this.v2 = v2;
    this.v3 = v3;
    this.filter = filter;
  }
}
export const SidFrame$SidFrame = (frame_index, v1, v2, v3, filter) =>
  new SidFrame(frame_index, v1, v2, v3, filter);
export const SidFrame$isSidFrame = (value) => value instanceof SidFrame;
export const SidFrame$SidFrame$frame_index = (value) => value.frame_index;
export const SidFrame$SidFrame$0 = (value) => value.frame_index;
export const SidFrame$SidFrame$v1 = (value) => value.v1;
export const SidFrame$SidFrame$1 = (value) => value.v1;
export const SidFrame$SidFrame$v2 = (value) => value.v2;
export const SidFrame$SidFrame$2 = (value) => value.v2;
export const SidFrame$SidFrame$v3 = (value) => value.v3;
export const SidFrame$SidFrame$3 = (value) => value.v3;
export const SidFrame$SidFrame$filter = (value) => value.filter;
export const SidFrame$SidFrame$4 = (value) => value.filter;

export class DumpSong extends $CustomType {
  constructor(title, author, copyright, frames, frame_count, frame_rate) {
    super();
    this.title = title;
    this.author = author;
    this.copyright = copyright;
    this.frames = frames;
    this.frame_count = frame_count;
    this.frame_rate = frame_rate;
  }
}
export const DumpSong$DumpSong = (title, author, copyright, frames, frame_count, frame_rate) =>
  new DumpSong(title, author, copyright, frames, frame_count, frame_rate);
export const DumpSong$isDumpSong = (value) => value instanceof DumpSong;
export const DumpSong$DumpSong$title = (value) => value.title;
export const DumpSong$DumpSong$0 = (value) => value.title;
export const DumpSong$DumpSong$author = (value) => value.author;
export const DumpSong$DumpSong$1 = (value) => value.author;
export const DumpSong$DumpSong$copyright = (value) => value.copyright;
export const DumpSong$DumpSong$2 = (value) => value.copyright;
export const DumpSong$DumpSong$frames = (value) => value.frames;
export const DumpSong$DumpSong$3 = (value) => value.frames;
export const DumpSong$DumpSong$frame_count = (value) => value.frame_count;
export const DumpSong$DumpSong$4 = (value) => value.frame_count;
export const DumpSong$DumpSong$frame_rate = (value) => value.frame_rate;
export const DumpSong$DumpSong$5 = (value) => value.frame_rate;

export class ConversionResult extends $CustomType {
  constructor(skode_code, title, duration_seconds, frame_count, step_count) {
    super();
    this.skode_code = skode_code;
    this.title = title;
    this.duration_seconds = duration_seconds;
    this.frame_count = frame_count;
    this.step_count = step_count;
  }
}
export const ConversionResult$ConversionResult = (skode_code, title, duration_seconds, frame_count, step_count) =>
  new ConversionResult(skode_code,
  title,
  duration_seconds,
  frame_count,
  step_count);
export const ConversionResult$isConversionResult = (value) =>
  value instanceof ConversionResult;
export const ConversionResult$ConversionResult$skode_code = (value) =>
  value.skode_code;
export const ConversionResult$ConversionResult$0 = (value) => value.skode_code;
export const ConversionResult$ConversionResult$title = (value) => value.title;
export const ConversionResult$ConversionResult$1 = (value) => value.title;
export const ConversionResult$ConversionResult$duration_seconds = (value) =>
  value.duration_seconds;
export const ConversionResult$ConversionResult$2 = (value) =>
  value.duration_seconds;
export const ConversionResult$ConversionResult$frame_count = (value) =>
  value.frame_count;
export const ConversionResult$ConversionResult$3 = (value) => value.frame_count;
export const ConversionResult$ConversionResult$step_count = (value) =>
  value.step_count;
export const ConversionResult$ConversionResult$4 = (value) => value.step_count;

export class DeepSidTrack extends $CustomType {
  constructor(id, name, author, copyright, file_path, subtunes) {
    super();
    this.id = id;
    this.name = name;
    this.author = author;
    this.copyright = copyright;
    this.file_path = file_path;
    this.subtunes = subtunes;
  }
}
export const DeepSidTrack$DeepSidTrack = (id, name, author, copyright, file_path, subtunes) =>
  new DeepSidTrack(id, name, author, copyright, file_path, subtunes);
export const DeepSidTrack$isDeepSidTrack = (value) =>
  value instanceof DeepSidTrack;
export const DeepSidTrack$DeepSidTrack$id = (value) => value.id;
export const DeepSidTrack$DeepSidTrack$0 = (value) => value.id;
export const DeepSidTrack$DeepSidTrack$name = (value) => value.name;
export const DeepSidTrack$DeepSidTrack$1 = (value) => value.name;
export const DeepSidTrack$DeepSidTrack$author = (value) => value.author;
export const DeepSidTrack$DeepSidTrack$2 = (value) => value.author;
export const DeepSidTrack$DeepSidTrack$copyright = (value) => value.copyright;
export const DeepSidTrack$DeepSidTrack$3 = (value) => value.copyright;
export const DeepSidTrack$DeepSidTrack$file_path = (value) => value.file_path;
export const DeepSidTrack$DeepSidTrack$4 = (value) => value.file_path;
export const DeepSidTrack$DeepSidTrack$subtunes = (value) => value.subtunes;
export const DeepSidTrack$DeepSidTrack$5 = (value) => value.subtunes;

export class TabStudio extends $CustomType {}
export const ActiveTab$TabStudio$const = new TabStudio();
export const ActiveTab$TabStudio = () => ActiveTab$TabStudio$const;
export const ActiveTab$isTabStudio = (value) => value instanceof TabStudio;

export class TabSkodeSource extends $CustomType {}
export const ActiveTab$TabSkodeSource$const = new TabSkodeSource();
export const ActiveTab$TabSkodeSource = () => ActiveTab$TabSkodeSource$const;
export const ActiveTab$isTabSkodeSource = (value) =>
  value instanceof TabSkodeSource;

export class TabDeepSidBrowser extends $CustomType {}
export const ActiveTab$TabDeepSidBrowser$const = new TabDeepSidBrowser();
export const ActiveTab$TabDeepSidBrowser = () =>
  ActiveTab$TabDeepSidBrowser$const;
export const ActiveTab$isTabDeepSidBrowser = (value) =>
  value instanceof TabDeepSidBrowser;

export class TabDumpView extends $CustomType {}
export const ActiveTab$TabDumpView$const = new TabDumpView();
export const ActiveTab$TabDumpView = () => ActiveTab$TabDumpView$const;
export const ActiveTab$isTabDumpView = (value) => value instanceof TabDumpView;

export class Model extends $CustomType {
  constructor(engine_ready, is_playing, is_paused, current_step, total_steps, master_volume_db, stereo_profile, active_tab, loaded_song, conversion, is_converting, error_message, raw_dump_text, deep_sid_query, deep_sid_results, is_searching) {
    super();
    this.engine_ready = engine_ready;
    this.is_playing = is_playing;
    this.is_paused = is_paused;
    this.current_step = current_step;
    this.total_steps = total_steps;
    this.master_volume_db = master_volume_db;
    this.stereo_profile = stereo_profile;
    this.active_tab = active_tab;
    this.loaded_song = loaded_song;
    this.conversion = conversion;
    this.is_converting = is_converting;
    this.error_message = error_message;
    this.raw_dump_text = raw_dump_text;
    this.deep_sid_query = deep_sid_query;
    this.deep_sid_results = deep_sid_results;
    this.is_searching = is_searching;
  }
}
export const Model$Model = (engine_ready, is_playing, is_paused, current_step, total_steps, master_volume_db, stereo_profile, active_tab, loaded_song, conversion, is_converting, error_message, raw_dump_text, deep_sid_query, deep_sid_results, is_searching) =>
  new Model(engine_ready,
  is_playing,
  is_paused,
  current_step,
  total_steps,
  master_volume_db,
  stereo_profile,
  active_tab,
  loaded_song,
  conversion,
  is_converting,
  error_message,
  raw_dump_text,
  deep_sid_query,
  deep_sid_results,
  is_searching);
export const Model$isModel = (value) => value instanceof Model;
export const Model$Model$engine_ready = (value) => value.engine_ready;
export const Model$Model$0 = (value) => value.engine_ready;
export const Model$Model$is_playing = (value) => value.is_playing;
export const Model$Model$1 = (value) => value.is_playing;
export const Model$Model$is_paused = (value) => value.is_paused;
export const Model$Model$2 = (value) => value.is_paused;
export const Model$Model$current_step = (value) => value.current_step;
export const Model$Model$3 = (value) => value.current_step;
export const Model$Model$total_steps = (value) => value.total_steps;
export const Model$Model$4 = (value) => value.total_steps;
export const Model$Model$master_volume_db = (value) => value.master_volume_db;
export const Model$Model$5 = (value) => value.master_volume_db;
export const Model$Model$stereo_profile = (value) => value.stereo_profile;
export const Model$Model$6 = (value) => value.stereo_profile;
export const Model$Model$active_tab = (value) => value.active_tab;
export const Model$Model$7 = (value) => value.active_tab;
export const Model$Model$loaded_song = (value) => value.loaded_song;
export const Model$Model$8 = (value) => value.loaded_song;
export const Model$Model$conversion = (value) => value.conversion;
export const Model$Model$9 = (value) => value.conversion;
export const Model$Model$is_converting = (value) => value.is_converting;
export const Model$Model$10 = (value) => value.is_converting;
export const Model$Model$error_message = (value) => value.error_message;
export const Model$Model$11 = (value) => value.error_message;
export const Model$Model$raw_dump_text = (value) => value.raw_dump_text;
export const Model$Model$12 = (value) => value.raw_dump_text;
export const Model$Model$deep_sid_query = (value) => value.deep_sid_query;
export const Model$Model$13 = (value) => value.deep_sid_query;
export const Model$Model$deep_sid_results = (value) => value.deep_sid_results;
export const Model$Model$14 = (value) => value.deep_sid_results;
export const Model$Model$is_searching = (value) => value.is_searching;
export const Model$Model$15 = (value) => value.is_searching;

export class EngineReady extends $CustomType {}
export const Msg$EngineReady$const = new EngineReady();
export const Msg$EngineReady = () => Msg$EngineReady$const;
export const Msg$isEngineReady = (value) => value instanceof EngineReady;

export class UserLoadedDump extends $CustomType {
  constructor(name, content) {
    super();
    this.name = name;
    this.content = content;
  }
}
export const Msg$UserLoadedDump = (name, content) =>
  new UserLoadedDump(name, content);
export const Msg$isUserLoadedDump = (value) => value instanceof UserLoadedDump;
export const Msg$UserLoadedDump$name = (value) => value.name;
export const Msg$UserLoadedDump$0 = (value) => value.name;
export const Msg$UserLoadedDump$content = (value) => value.content;
export const Msg$UserLoadedDump$1 = (value) => value.content;

export class UserTriggerPlay extends $CustomType {}
export const Msg$UserTriggerPlay$const = new UserTriggerPlay();
export const Msg$UserTriggerPlay = () => Msg$UserTriggerPlay$const;
export const Msg$isUserTriggerPlay = (value) =>
  value instanceof UserTriggerPlay;

export class UserTriggerPause extends $CustomType {}
export const Msg$UserTriggerPause$const = new UserTriggerPause();
export const Msg$UserTriggerPause = () => Msg$UserTriggerPause$const;
export const Msg$isUserTriggerPause = (value) =>
  value instanceof UserTriggerPause;

export class UserTriggerStop extends $CustomType {}
export const Msg$UserTriggerStop$const = new UserTriggerStop();
export const Msg$UserTriggerStop = () => Msg$UserTriggerStop$const;
export const Msg$isUserTriggerStop = (value) =>
  value instanceof UserTriggerStop;

export class UserSetStereo extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const Msg$UserSetStereo = ($0) => new UserSetStereo($0);
export const Msg$isUserSetStereo = (value) => value instanceof UserSetStereo;
export const Msg$UserSetStereo$0 = (value) => value[0];

export class UserSetVolume extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const Msg$UserSetVolume = ($0) => new UserSetVolume($0);
export const Msg$isUserSetVolume = (value) => value instanceof UserSetVolume;
export const Msg$UserSetVolume$0 = (value) => value[0];

export class UserSelectTab extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const Msg$UserSelectTab = ($0) => new UserSelectTab($0);
export const Msg$isUserSelectTab = (value) => value instanceof UserSelectTab;
export const Msg$UserSelectTab$0 = (value) => value[0];

export class EngineStepUpdated extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const Msg$EngineStepUpdated = ($0) => new EngineStepUpdated($0);
export const Msg$isEngineStepUpdated = (value) =>
  value instanceof EngineStepUpdated;
export const Msg$EngineStepUpdated$0 = (value) => value[0];

export class EnginePlaybackEnded extends $CustomType {}
export const Msg$EnginePlaybackEnded$const = new EnginePlaybackEnded();
export const Msg$EnginePlaybackEnded = () => Msg$EnginePlaybackEnded$const;
export const Msg$isEnginePlaybackEnded = (value) =>
  value instanceof EnginePlaybackEnded;

export class SearchDeepSid extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const Msg$SearchDeepSid = ($0) => new SearchDeepSid($0);
export const Msg$isSearchDeepSid = (value) => value instanceof SearchDeepSid;
export const Msg$SearchDeepSid$0 = (value) => value[0];

export class DeepSidSearchResults extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const Msg$DeepSidSearchResults = ($0) => new DeepSidSearchResults($0);
export const Msg$isDeepSidSearchResults = (value) =>
  value instanceof DeepSidSearchResults;
export const Msg$DeepSidSearchResults$0 = (value) => value[0];

export class LoadDeepSidTrack extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const Msg$LoadDeepSidTrack = ($0) => new LoadDeepSidTrack($0);
export const Msg$isLoadDeepSidTrack = (value) =>
  value instanceof LoadDeepSidTrack;
export const Msg$LoadDeepSidTrack$0 = (value) => value[0];

export class DeepSidTrackDownloaded extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const Msg$DeepSidTrackDownloaded = ($0) =>
  new DeepSidTrackDownloaded($0);
export const Msg$isDeepSidTrackDownloaded = (value) =>
  value instanceof DeepSidTrackDownloaded;
export const Msg$DeepSidTrackDownloaded$0 = (value) => value[0];

export class CopySkodeToClipboard extends $CustomType {}
export const Msg$CopySkodeToClipboard$const = new CopySkodeToClipboard();
export const Msg$CopySkodeToClipboard = () => Msg$CopySkodeToClipboard$const;
export const Msg$isCopySkodeToClipboard = (value) =>
  value instanceof CopySkodeToClipboard;

export class DownloadSkodeFile extends $CustomType {}
export const Msg$DownloadSkodeFile$const = new DownloadSkodeFile();
export const Msg$DownloadSkodeFile = () => Msg$DownloadSkodeFile$const;
export const Msg$isDownloadSkodeFile = (value) =>
  value instanceof DownloadSkodeFile;

export class DismissError extends $CustomType {}
export const Msg$DismissError$const = new DismissError();
export const Msg$DismissError = () => Msg$DismissError$const;
export const Msg$isDismissError = (value) => value instanceof DismissError;
