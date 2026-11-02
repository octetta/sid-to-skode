//// Standalone CLI runner for sid-to-skode
//// Converts C64 SID dump files into Skode 0.80.0 scripts (.sk)

import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/string
import sid_to_skode/converter
import sid_to_skode/dump_parser
import sid_to_skode/types.{StereoHeadphone}

@external(javascript, "./cli_ffi.mjs", "getArgs")
fn get_args() -> List(String)

@external(javascript, "./cli_ffi.mjs", "readTextFile")
fn read_text_file(path: String) -> Result(String, String)

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
    show_help: Bool,
  )
}

fn parse_cli_args(args: List(String), opts: CliOptions) -> CliOptions {
  case args {
    [] -> opts
    ["-h", ..rest] | ["--help", ..rest] ->
      parse_cli_args(rest, CliOptions(..opts, show_help: True))
    ["-o", out, ..rest] | ["--output", out, ..rest] ->
      parse_cli_args(rest, CliOptions(..opts, output_file: Some(out)))
    [arg, ..rest] -> {
      case string.starts_with(arg, "-") {
        True -> parse_cli_args(rest, opts)
        False ->
          case opts.input_file {
            None ->
              parse_cli_args(rest, CliOptions(..opts, input_file: Some(arg)))
            Some(_) -> parse_cli_args(rest, opts)
          }
      }
    }
  }
}

fn print_help() {
  print_stdout(
    "sid2skode v0.1.0\n"
    <> "Converts Commodore 64 SID register dumps into Skode 0.80.0 scripts\n\n"
    <> "Usage:\n"
    <> "  sid2skode <input.dump> [options]\n\n"
    <> "Options:\n"
    <> "  -o, --output <file.sk>  Specify output script filename (default: <name>.sk)\n"
    <> "  -h, --help              Show this help message\n",
  )
}

pub fn main() {
  let args = get_args()
  let opts =
    parse_cli_args(
      args,
      CliOptions(input_file: None, output_file: None, show_help: False),
    )

  case opts.show_help {
    True -> {
      print_help()
      exit_process(0)
    }
    False -> Nil
  }

  case opts.input_file {
    None -> {
      print_stderr("Error: No input .dump file specified.\n")
      print_help()
      exit_process(1)
    }
    Some(in_path) -> {
      print_stdout("==> Reading SID dump: " <> in_path <> "\n")
      case read_text_file(in_path) {
        Error(err) -> {
          print_stderr("Error reading file: " <> err <> "\n")
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
              print_stdout(
                "==> Parsed "
                <> int.to_string(song.frame_count)
                <> " frames ("
                <> in_path
                <> ")\n",
              )

              let result = converter.convert_song(song, StereoHeadphone)
              let out_path = case opts.output_file {
                Some(p) -> p
                None -> {
                  case string.ends_with(in_path, ".dump") {
                    True -> string.drop_end(in_path, 5) <> ".sk"
                    False -> in_path <> ".sk"
                  }
                }
              }

              case write_text_file(out_path, result.skode_code) {
                Error(write_err) -> {
                  print_stderr(
                    "Error writing output file: " <> write_err <> "\n",
                  )
                  exit_process(1)
                }
                Ok(_) -> {
                  print_stdout(
                    "==> Successfully generated Skode script: "
                    <> out_path
                    <> " ("
                    <> int.to_string(result.step_count)
                    <> " steps)\n",
                  )
                  exit_process(0)
                }
              }
            }
          }
        }
      }
    }
  }
}
