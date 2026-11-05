// JavaScript FFI Bridge for QuickJS Native CLI with Direct C Linkage

if (typeof globalThis.TextEncoder === "undefined") {
  globalThis.TextEncoder = class TextEncoder {
    encode(str) {
      const arr = [];
      for (let i = 0; i < str.length; i++) {
        let code = str.charCodeAt(i);
        if (code < 0x80) {
          arr.push(code);
        } else if (code < 0x800) {
          arr.push(0xc0 | (code >> 6), 0x80 | (code & 0x3f));
        } else if (code < 0xd800 || code >= 0xe000) {
          arr.push(0xe0 | (code >> 12), 0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f));
        } else {
          i++;
          code = 0x10000 + (((code & 0x3ff) << 10) | (str.charCodeAt(i) & 0x3ff));
          arr.push(0xf0 | (code >> 18), 0x80 | ((code >> 12) & 0x3f), 0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f));
        }
      }
      return new Uint8Array(arr);
    }
  };
}

if (typeof globalThis.TextDecoder === "undefined") {
  globalThis.TextDecoder = class TextDecoder {
    decode(bytes) {
      let s = "";
      for (let i = 0; i < bytes.length; i++) {
        s += String.fromCharCode(bytes[i]);
      }
      return s;
    }
  };
}

import * as std from "std";
import * as os from "os";
import * as siddumpNative from "siddump_native";
import { toList, Ok, Error } from "./gleam.mjs";

export function getArgs() {
  if (typeof scriptArgs !== "undefined" && Array.isArray(scriptArgs)) {
    return toList(scriptArgs.slice(1));
  }
  return toList([]);
}

export function dumpSidOrRead(filePath, duration, subtune) {
  try {
    // If it is a pre-dumped text file
    if (filePath.endsWith(".dump") || filePath.endsWith(".txt")) {
      const f = std.open(filePath, "r");
      if (!f) {
        return new Error("Could not open file: " + filePath);
      }
      f.seek(0, std.SEEK_END);
      const size = f.tell();
      f.seek(0, std.SEEK_SET);
      const str = f.readAsString();
      f.close();
      return new Ok(str);
    }

    // Direct C linkage: call into native C 6502 emulator linked in this binary!
    const dumpText = siddumpNative.emulateSid(filePath, duration, subtune);
    if (!dumpText || dumpText.length === 0) {
      return new Error("SID emulation produced empty output for " + filePath);
    }
    return new Ok(dumpText);
  } catch (err) {
    return new Error(String(err));
  }
}

export function writeTextFile(path, content) {
  try {
    const f = std.open(path, "w");
    if (!f) return new Error("Could not open file for writing: " + path);
    f.puts(content);
    f.close();
    return new Ok(undefined);
  } catch (err) {
    return new Error(String(err));
  }
}

export function printStdout(text) {
  std.out.puts(text);
  std.out.flush();
}

export function printStderr(text) {
  std.err.puts(text);
  std.err.flush();
}

export function exitProcess(code) {
  std.exit(code);
}
