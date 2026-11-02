import * as $int from "../gleam_stdlib/gleam/int.mjs";
import * as $option from "../gleam_stdlib/gleam/option.mjs";
import { Some, Option$None$const } from "../gleam_stdlib/gleam/option.mjs";
import * as $string from "../gleam_stdlib/gleam/string.mjs";
import {
  getArgs as get_args,
  readTextFile as read_text_file,
  writeTextFile as write_text_file,
  printStdout as print_stdout,
  printStderr as print_stderr,
  exitProcess as exit_process,
} from "./cli_ffi.mjs";
import { Ok, Empty as $Empty, CustomType as $CustomType } from "./gleam.mjs";
import * as $converter from "./sid_to_skode/converter.mjs";
import * as $dump_parser from "./sid_to_skode/dump_parser.mjs";
import * as $types from "./sid_to_skode/types.mjs";
import { StereoProfile$StereoHeadphone$const } from "./sid_to_skode/types.mjs";

export class CliOptions extends $CustomType {
  constructor(input_file, output_file, show_help) {
    super();
    this.input_file = input_file;
    this.output_file = output_file;
    this.show_help = show_help;
  }
}
export const CliOptions$CliOptions = (input_file, output_file, show_help) =>
  new CliOptions(input_file, output_file, show_help);
export const CliOptions$isCliOptions = (value) => value instanceof CliOptions;
export const CliOptions$CliOptions$input_file = (value) => value.input_file;
export const CliOptions$CliOptions$0 = (value) => value.input_file;
export const CliOptions$CliOptions$output_file = (value) => value.output_file;
export const CliOptions$CliOptions$1 = (value) => value.output_file;
export const CliOptions$CliOptions$show_help = (value) => value.show_help;
export const CliOptions$CliOptions$2 = (value) => value.show_help;

function parse_cli_args(loop$args, loop$opts) {
  while (true) {
    let args = loop$args;
    let opts = loop$opts;
    if (args instanceof $Empty) {
      return opts;
    } else {
      let $ = args.head;
      if ($ === "-h") {
        let rest = args.tail;
        loop$args = rest;
        loop$opts = new CliOptions(opts.input_file, opts.output_file, true);
      } else if ($ === "--help") {
        let rest = args.tail;
        loop$args = rest;
        loop$opts = new CliOptions(opts.input_file, opts.output_file, true);
      } else if ($ === "-o") {
        let $1 = args.tail;
        if ($1 instanceof $Empty) {
          let arg = $;
          let rest = $1;
          let $2 = $string.starts_with(arg, "-");
          if ($2) {
            loop$args = rest;
            loop$opts = opts;
          } else {
            let $3 = opts.input_file;
            if ($3 instanceof Some) {
              loop$args = rest;
              loop$opts = opts;
            } else {
              loop$args = rest;
              loop$opts = new CliOptions(
                new Some(arg),
                opts.output_file,
                opts.show_help,
              );
            }
          }
        } else {
          let out = $1.head;
          let rest = $1.tail;
          loop$args = rest;
          loop$opts = new CliOptions(
            opts.input_file,
            new Some(out),
            opts.show_help,
          );
        }
      } else if ($ === "--output") {
        let $1 = args.tail;
        if ($1 instanceof $Empty) {
          let arg = $;
          let rest = $1;
          let $2 = $string.starts_with(arg, "-");
          if ($2) {
            loop$args = rest;
            loop$opts = opts;
          } else {
            let $3 = opts.input_file;
            if ($3 instanceof Some) {
              loop$args = rest;
              loop$opts = opts;
            } else {
              loop$args = rest;
              loop$opts = new CliOptions(
                new Some(arg),
                opts.output_file,
                opts.show_help,
              );
            }
          }
        } else {
          let out = $1.head;
          let rest = $1.tail;
          loop$args = rest;
          loop$opts = new CliOptions(
            opts.input_file,
            new Some(out),
            opts.show_help,
          );
        }
      } else {
        let arg = $;
        let rest = args.tail;
        let $1 = $string.starts_with(arg, "-");
        if ($1) {
          loop$args = rest;
          loop$opts = opts;
        } else {
          let $2 = opts.input_file;
          if ($2 instanceof Some) {
            loop$args = rest;
            loop$opts = opts;
          } else {
            loop$args = rest;
            loop$opts = new CliOptions(
              new Some(arg),
              opts.output_file,
              opts.show_help,
            );
          }
        }
      }
    }
  }
}

function print_help() {
  return print_stdout(
    ((((("sid2skode v0.1.0\n" + "Converts Commodore 64 SID register dumps into Skode 0.80.0 scripts\n\n") + "Usage:\n") + "  sid2skode <input.dump> [options]\n\n") + "Options:\n") + "  -o, --output <file.sk>  Specify output script filename (default: <name>.sk)\n") + "  -h, --help              Show this help message\n",
  );
}

export function main() {
  let args = get_args();
  let opts = parse_cli_args(
    args,
    new CliOptions(Option$None$const, Option$None$const, false),
  );
  let $ = opts.show_help;
  if ($) {
    print_help();
    exit_process(0);
  } else {
    undefined;
  }
  let $1 = opts.input_file;
  if ($1 instanceof Some) {
    let in_path = $1[0];
    print_stdout(("==> Reading SID dump: " + in_path) + "\n");
    let $2 = read_text_file(in_path);
    if ($2 instanceof Ok) {
      let content = $2[0];
      let title = in_path;
      let $3 = $dump_parser.parse_dump(content, title);
      if ($3 instanceof Ok) {
        let song = $3[0];
        print_stdout(
          ((("==> Parsed " + $int.to_string(song.frame_count)) + " frames (") + in_path) + ")\n",
        );
        let result = $converter.convert_song(
          song,
          StereoProfile$StereoHeadphone$const,
        );
        let _block;
        let $4 = opts.output_file;
        if ($4 instanceof Some) {
          let p = $4[0];
          _block = p;
        } else {
          let $5 = $string.ends_with(in_path, ".dump");
          if ($5) {
            _block = $string.drop_end(in_path, 5) + ".sk";
          } else {
            _block = in_path + ".sk";
          }
        }
        let out_path = _block;
        let $5 = write_text_file(out_path, result.skode_code);
        if ($5 instanceof Ok) {
          print_stdout(
            ((("==> Successfully generated Skode script: " + out_path) + " (") + $int.to_string(
              result.step_count,
            )) + " steps)\n",
          );
          return exit_process(0);
        } else {
          let write_err = $5[0];
          print_stderr(("Error writing output file: " + write_err) + "\n");
          return exit_process(1);
        }
      } else {
        let parse_err = $3[0];
        print_stderr(("Parser error: " + parse_err) + "\n");
        return exit_process(1);
      }
    } else {
      let err = $2[0];
      print_stderr(("Error reading file: " + err) + "\n");
      return exit_process(1);
    }
  } else {
    print_stderr("Error: No input .dump file specified.\n");
    print_help();
    return exit_process(1);
  }
}
