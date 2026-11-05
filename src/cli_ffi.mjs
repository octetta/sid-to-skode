// JavaScript FFI Bridge for CLI (supports both Node.js and QuickJS)

import { toList, Ok, Error } from "./gleam.mjs";

const isNode = typeof process !== "undefined" && Boolean(process.versions && process.versions.node);

let fs = null;
let path = null;
let fileURLToPath = null;
if (isNode) {
  try {
    fs = await import("node:fs");
    path = await import("node:path");
    const urlMod = await import("node:url");
    fileURLToPath = urlMod.fileURLToPath;
  } catch (_) {}
}

let qjsStd = null;
if (!isNode && typeof std !== "undefined") {
  qjsStd = std;
}

export function getArgs() {
  if (isNode) {
    return toList(process.argv.slice(2));
  }
  if (typeof scriptArgs !== "undefined" && Array.isArray(scriptArgs)) {
    return toList(scriptArgs.slice(1));
  }
  return toList([]);
}

let cachedSiddumpFactory = null;
let cachedVendorDir = null;

function findVendorDir() {
  if (cachedVendorDir) return cachedVendorDir;
  let curr = "";
  try {
    if (fileURLToPath && import.meta && import.meta.url) {
      curr = path.dirname(fileURLToPath(import.meta.url));
    }
  } catch (_) {}
  if (!curr) curr = process.cwd();

  for (let i = 0; i < 8; i++) {
    const candidate = path.join(curr, "vendor", "siddump_wasm.js");
    if (fs.existsSync(candidate)) {
      cachedVendorDir = path.join(curr, "vendor");
      return cachedVendorDir;
    }
    const parent = path.dirname(curr);
    if (parent === curr) break;
    curr = parent;
  }

  // Also check cwd
  curr = process.cwd();
  for (let i = 0; i < 8; i++) {
    const candidate = path.join(curr, "vendor", "siddump_wasm.js");
    if (fs.existsSync(candidate)) {
      cachedVendorDir = path.join(curr, "vendor");
      return cachedVendorDir;
    }
    const parent = path.dirname(curr);
    if (parent === curr) break;
    curr = parent;
  }
  return null;
}

async function runSiddumpNode(bytes, filename, durationSeconds, subtune) {
  const vendorDir = findVendorDir();
  if (!vendorDir) {
    throw new Error("Could not locate vendor/siddump_wasm.js directory.");
  }
  const jsPath = path.join(vendorDir, "siddump_wasm.js");
  if (!cachedSiddumpFactory) {
    const mod = await import("file://" + jsPath);
    cachedSiddumpFactory = mod.default || mod;
  }

  let output = "";
  const inst = await cachedSiddumpFactory({
    locateFile: (p) => path.join(vendorDir, p),
    noInitialRun: true,
    print: (text) => {
      output += text + "\n";
    },
    printErr: (text) => {
      // Emscripten debug/warning output
    },
  });

  const virtualFile = "tune.sid";
  inst.FS.writeFile(virtualFile, bytes);

  const dur = typeof durationSeconds === "number" && durationSeconds > 0 ? durationSeconds : 210;
  const args = [virtualFile, "-t" + dur];
  if (typeof subtune === "number" && subtune >= 0) {
    args.push("-a" + subtune);
  }

  try {
    inst.callMain(args);
  } catch (_) {
    // Normal exit in Emscripten
  }

  return output;
}

export function dumpSidOrRead(filePath, duration, subtune, callback) {
  try {
    if (!isNode) {
      if (qjsStd) {
        const f = qjsStd.open(filePath, "r");
        if (!f) {
          callback(new Error("Could not open file: " + filePath));
          return;
        }
        f.seek(0, qjsStd.SEEK_END);
        const size = f.tell();
        f.seek(0, qjsStd.SEEK_SET);
        const str = f.readAsString();
        f.close();
        callback(new Ok(str));
        return;
      }
      callback(new Error("No filesystem runtime available."));
      return;
    }

    if (!fs.existsSync(filePath)) {
      callback(new Error("File not found: " + filePath));
      return;
    }

    const isTextDump = filePath.endsWith(".dump") || filePath.endsWith(".txt");
    if (isTextDump) {
      const content = fs.readFileSync(filePath, "utf-8");
      callback(new Ok(content));
      return;
    }

    // Binary .sid file
    const bytes = fs.readFileSync(filePath);
    if (bytes.length < 4) {
      callback(new Error("File is too small to be a valid SID file: " + filePath));
      return;
    }
    const magic = String.fromCharCode(bytes[0], bytes[1], bytes[2], bytes[3]);
    if (magic !== "PSID" && magic !== "RSID") {
      // Check if it might be an unadorned text dump
      try {
        const asText = bytes.toString("utf-8");
        if (asText.includes("| Frame |") || asText.includes("Middle C")) {
          callback(new Ok(asText));
          return;
        }
      } catch (_) {}
      callback(
        new Error(
          "Invalid SID file format (expected PSID or RSID magic header, got '" +
            magic +
            "'): " +
            filePath
        )
      );
      return;
    }

    runSiddumpNode(bytes, filePath, duration, subtune)
      .then((output) => {
        if (!output || output.trim().length === 0) {
          callback(new Error("siddump produced empty output for " + filePath));
        } else {
          callback(new Ok(output));
        }
      })
      .catch((err) => {
        callback(new Error("SID emulation failed: " + (err.message || String(err))));
      });
  } catch (err) {
    callback(new Error(String(err)));
  }
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
