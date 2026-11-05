//// Standalone CLI runner for sid-to-skode
//// Converts Commodore 64 SID files (.sid) or register dumps (.dump) into Skode 0.80.0 scripts (.sk)

import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import sid_to_skode/converter
import sid_to_skode/dump_parser
import sid_to_skode/types.{
  type ConversionResult, type DumpSong, type StereoMode, StereoHeadphone,
  StereoMono, StereoWide,
}

@external(javascript, "./cli_ffi.mjs", "getArgs")
fn get_args() -> List(String)

@external(javascript, "./cli_ffi.mjs", "dumpSidOrRead")
fn dump_sid_or_read(
  path: String,
  duration: Int,
  subtune: Int,
  callback: fn(Result(String, String)) -> Nil,
) -> Nil

@external(javascript, "./cli_ffi.mjs", "writeTextFile")
fn write_text_file(path: String, content: String) -> Result(Nil, String)

@external(javascript, "./cli_ffi.mjs", "printStdout")
fn print_stdout(text: String) -> Nil

@external(javascript, "./cli_ffi.mjs", "printStderr")
fn print_stderr(text: String) -> Nil

@external(javascript, "./cli_ffi.mjs", "exitProcess")
fn exit_process(code: Int) -> Nil

pub type CliOptions {
  CliOptions(
    input_file: Option(String),
    output_file: Option(String),
    duration: Int,
    subtune: Int,
    stereo: StereoMode,
    dac_crunch: Bool,
    show_help: Bool,
    show_version: Bool,
  )
}

fn parse_cli_args(args: List(String), opts: CliOptions) -> CliOptions {
  case args {
    [] -> opts
    ["-h", ..rest] | ["--help", ..rest] ->
      parse_cli_args(rest, CliOptions(..opts, show_help: True))
    ["-v", ..rest] | ["--version", ..rest] ->
      parse_cli_args(rest, CliOptions(..opts, show_version: True))
    ["-o", out, ..rest] | ["--output", out, ..rest] ->
      parse_cli_args(rest, CliOptions(..opts, output_file: Some(out)))
    ["-t", dur_str, ..rest] | ["--time", dur_str, ..rest] -> {
      let dur = result.unwrap(int.parse(dur_str), opts.duration)
      parse_cli_args(rest, CliOptions(..opts, duration: dur))
    }
    ["-a", sub_str, ..rest] | ["--subtune", sub_str, ..rest] -> {
      let sub = result.unwrap(int.parse(sub_str), opts.subtune)
      parse_cli_args(rest, CliOptions(..opts, subtune: sub))
    }
    ["--stereo", mode_str, ..rest] -> {
      let mode = case string.lowercase(mode_str) {
        "mono" -> StereoMono
        "wide" -> StereoWide
        _ -> StereoHeadphone
      }
      parse_cli_args(rest, CliOptions(..opts, stereo: mode))
    }
    ["--dac-crunch", ..rest] ->
      parse_cli_args(rest, CliOptions(..opts, dac_crunch: True))
    ["--no-dac-crunch", ..rest] ->
      parse_cli_args(rest, CliOptions(..opts, dac_crunch: False))
    [arg, ..rest] -> {
      case string.starts_with(arg, "--output=") {
        True -> {
          let out = string.drop_start(arg, 9)
          parse_cli_args(rest, CliOptions(..opts, output_file: Some(out)))
        }
        False ->
          case string.starts_with(arg, "--time=") {
            True -> {
              let dur_str = string.drop_start(arg, 7)
              let dur = result.unwrap(int.parse(dur_str), opts.duration)
              parse_cli_args(rest, CliOptions(..opts, duration: dur))
            }
            False ->
              case string.starts_with(arg, "--subtune=") {
                True -> {
                  let sub_str = string.drop_start(arg, 10)
                  let sub = result.unwrap(int.parse(sub_str), opts.subtune)
                  parse_cli_args(rest, CliOptions(..opts, subtune: sub))
                }
                False ->
                  case string.starts_with(arg, "--stereo=") {
                    True -> {
                      let mode_str = string.drop_start(arg, 9)
                      let mode = case string.lowercase(mode_str) {
                        "mono" -> StereoMono
                        "wide" -> StereoWide
                        _ -> StereoHeadphone
                      }
                      parse_cli_args(rest, CliOptions(..opts, stereo: mode))
                    }
                    False ->
                      case string.starts_with(arg, "-") {
                        True -> parse_cli_args(rest, opts)
                        False ->
                          case opts.input_file {
                            None ->
                              parse_cli_args(
                                rest,
                                CliOptions(..opts, input_file: Some(arg)),
                              )
                            Some(_) -> parse_cli_args(rest, opts)
                          }
                      }
                  }
              }
          }
      }
    }
  }
}

fn print_help() {
  print_stdout(
    "sid2skode v0.1.0\n"
    <> "Converts Commodore 64 SID tunes (.sid) or register dumps (.dump) into Skode 0.80.0 scripts\n\n"
    <> "Usage:\n"
    <> "  sid2skode <input.sid|input.dump> [options]\n\n"
    <> "Options:\n"
    <> "  -o, --output <file.sk>      Output script filename ('-' for stdout, default: <name>.sk)\n"
    <> "  -t, --time <seconds>        Emulation playback duration in seconds (default: 210)\n"
    <> "  -a, --subtune <num>         Subtune index (0-based, default: 0)\n"
    <> "  --stereo <mode>             Stereo panning: mono | headphone | wide (default: headphone)\n"
    <> "  --dac-crunch                Enable 4-bit DAC crunch mode (bc6) for digi samples (default: on)\n"
    <> "  --no-dac-crunch             Disable 4-bit DAC crunch mode\n"
    <> "  -v, --version               Show version information\n"
    <> "  -h, --help                  Show this help message\n\n"
    <> "Examples:\n"
    <> "  sid2skode commando.sid                    Convert to commando.sk (210s, headphone stereo)\n"
    <> "  sid2skode commando.sid -t 120 -o out.sk   Convert 120 seconds to out.sk\n"
    <> "  sid2skode commando.sid -a 1               Convert subtune 1\n"
    <> "  sid2skode commando.sid --stereo wide      Convert with wide stereo panning\n"
    <> "  sid2skode commando.sid -o - > out.sk      Stream Skode script directly to stdout\n",
  )
}

fn print_version() {
  print_stdout("sid2skode v0.1.0 (Skode 0.80.0 target)\n")
}

fn format_duration(seconds: Float) -> String {
  let total_sec = case seconds <. 0.0 {
    True -> 0
    False -> float.round(seconds)
  }
  let mins = total_sec / 60
  let secs = total_sec % 60
  let mins_str = case mins < 10 {
    True -> "0" <> int.to_string(mins)
    False -> int.to_string(mins)
  }
  let secs_str = case secs < 10 {
    True -> "0" <> int.to_string(secs)
    False -> int.to_string(secs)
  }
  mins_str
  <> ":"
  <> secs_str
  <> " ("
  <> converter.format_float(seconds, 2)
  <> "s)"
}

fn default_output_filename(in_path: String) -> String {
  case string.ends_with(in_path, ".sid") {
    True -> string.drop_end(in_path, 4) <> ".sk"
    False -> {
      case string.ends_with(in_path, ".dump") {
        True -> string.drop_end(in_path, 5) <> ".sk"
        False -> in_path <> ".sk"
      }
    }
  }
}

pub fn main() {
  let args = get_args()
  let opts =
    parse_cli_args(
      args,
      CliOptions(
        input_file: None,
        output_file: None,
        duration: 210,
        subtune: 0,
        stereo: StereoHeadphone,
        dac_crunch: True,
        show_help: False,
        show_version: False,
      ),
    )

  case opts.show_help {
    True -> {
      print_help()
      exit_process(0)
    }
    False -> Nil
  }

  case opts.show_version {
    True -> {
      print_version()
      exit_process(0)
    }
    False -> Nil
  }

  case opts.input_file {
    None -> {
      print_stderr("Error: No input .sid or .dump file specified.\n\n")
      print_help()
      exit_process(1)
    }
    Some(in_path) -> {
      let is_stdout = case opts.output_file {
        Some("-") -> True
        _ -> False
      }

      case is_stdout {
        False ->
          print_stdout(
            "==> Loading and processing: "
            <> in_path
            <> " (duration: "
            <> int.to_string(opts.duration)
            <> "s, subtune: "
            <> int.to_string(opts.subtune)
            <> ")\n",
          )
        True -> Nil
      }

      dump_sid_or_read(in_path, opts.duration, opts.subtune, fn(read_result) {
        case read_result {
          Error(err) -> {
            print_stderr("Error reading/emulating file: " <> err <> "\n")
            exit_process(1)
          }
          Ok(content) -> {
            let title = in_path
            case dump_parser.parse_dump(content, title) {
              Error(parse_err) -> {
                print_stderr("Parser error: " <> parse_err <> "\n")
                exit_process(1)
              }
              Ok(song) -> {
                case is_stdout {
                  False ->
                    print_stdout(
                      "==> Parsed "
                      <> int.to_string(song.frame_count)
                      <> " frames ("
                      <> in_path
                      <> ")\n",
                    )
                  True -> Nil
                }

                case
                  converter.convert_song_full(
                    song,
                    opts.stereo,
                    opts.dac_crunch,
                    0.0,
                  )
                {
                  Error(conv_err) -> {
                    print_stderr("Conversion error: " <> conv_err <> "\n")
                    exit_process(1)
                  }
                  Ok(result) -> {
                    case opts.output_file {
                      Some("-") -> {
                        print_stdout(result.skode_text)
                        exit_process(0)
                      }
                      Some(out_path) -> {
                        write_output_file(out_path, in_path, song, result)
                      }
                      None -> {
                        let out_path = default_output_filename(in_path)
                        write_output_file(out_path, in_path, song, result)
                      }
                    }
                  }
                }
              }
            }
          }
        }
      })
    }
  }
}

fn write_output_file(
  out_path: String,
  in_path: String,
  song: DumpSong,
  result: ConversionResult,
) -> Nil {
  let _ = in_path
  case write_text_file(out_path, result.skode_text) {
    Error(write_err) -> {
      print_stderr("Error writing output file: " <> write_err <> "\n")
      exit_process(1)
    }
    Ok(_) -> {
      print_stdout(
        "==> Successfully generated Skode script: "
        <> out_path
        <> " ("
        <> int.to_string(result.total_steps)
        <> " steps)\n",
      )
      print_stdout("==> Duration: " <> format_duration(result.duration_seconds) <> "\n")
      let digi_count = list.length(song.digi_samples)
      case digi_count > 0 {
        True ->
          print_stdout(
            "==> Included "
            <> int.to_string(digi_count)
            <> " digi sample wavetable(s) (w310+)\n",
          )
        False -> Nil
      }
      exit_process(0)
    }
  }
}
