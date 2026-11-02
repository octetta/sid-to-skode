// JavaScript FFI Bridge for CLI (supports both Node.js and QuickJS)

import { toList, Ok, Error } from "./gleam.mjs";

const isNode = typeof process !== "undefined" && process.versions && process.versions.node;

let fs = null;
if (isNode) {
  try {
    fs = await import("node:fs");
  } catch (_) {}
}

let qjsStd = null;
if (!isNode && typeof std !== "undefined") {
  qjsStd = std;
}

export function getArgs() {
  if (isNode) {
    const args = process.argv.slice(1);
    if (args.length > 0 && (args[0].endsWith(".js") || args[0].endsWith(".mjs") || args[0].includes("node_modules"))) {
      return toList(args.slice(1));
    }
    return toList(args);
  }
  if (typeof scriptArgs !== "undefined" && Array.isArray(scriptArgs)) {
    return toList(scriptArgs.slice(1));
  }
  return toList([]);
}

export function readTextFile(path) {
  try {
    if (isNode) {
      const content = fs.readFileSync(path, "utf-8");
      return new Ok(content);
    }
    if (qjsStd) {
      const f = qjsStd.open(path, "r");
      if (!f) return new Error("Could not open file: " + path);
      f.seek(0, qjsStd.SEEK_END);
      const size = f.tell();
      f.seek(0, qjsStd.SEEK_SET);
      const str = f.readAsString();
      f.close();
      return new Ok(str);
    }
    return new Error("No filesystem runtime available.");
  } catch (err) {
    return new Error(String(err));
  }
}

export function writeTextFile(path, content) {
  try {
    if (isNode) {
      fs.writeFileSync(path, content, "utf-8");
      return new Ok(undefined);
    }
    if (qjsStd) {
      const f = qjsStd.open(path, "w");
      if (!f) return new Error("Could not open file for writing: " + path);
      f.puts(content);
      f.close();
      return new Ok(undefined);
    }
    return new Error("No filesystem runtime available.");
  } catch (err) {
    return new Error(String(err));
  }
}

export function printStdout(text) {
  if (isNode) {
    process.stdout.write(text);
  } else if (typeof print !== "undefined") {
    print(text);
  }
}

export function printStderr(text) {
  if (isNode) {
    process.stderr.write(text);
  } else if (typeof print !== "undefined") {
    print(text);
  }
}

export function exitProcess(code) {
  if (isNode) {
    process.exit(code);
  } else if (qjsStd) {
    qjsStd.exit(code);
  }
}
