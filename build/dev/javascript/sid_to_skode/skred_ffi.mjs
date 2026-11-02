// JavaScript FFI Bridge for sid-to-skode
// Integrates Skred 0.80.0 WASM engine, in-browser siddump WASM, and Web Audio APIs

const win = typeof window !== "undefined" ? window : globalThis;

let moduleReady = false;
let engineStarted = false;
let audioContext = null;
let currentMasterVolume = -6;
let isPlaybackActive = false;
let isPlaybackPaused = false;
let playbackStepCallback = null;
let playbackEndedCallback = null;
let totalSongSteps = 0;
let currentStepNumber = 0;

let siddumpModule = null;

// ---------------------------------------------------------------------------
// 1. Skred WASM Audio Engine Initialization
// ---------------------------------------------------------------------------

function getWasmModule() {
  if (win.Module && (typeof win.Module.ccall === "function" || typeof win.Module._skred_start === "function")) {
    return win.Module;
  }
  return null;
}

export function executeSkredCommand(cmd) {
  const M = getWasmModule();
  if (!M) return;

  if (typeof M.ccall === "function") {
    try {
      M.ccall("skred_command", "number", ["string"], [cmd]);
    } catch (err) {
      console.warn("[sid-to-skode] Error executing skred command:", err);
    }
  } else if (typeof M._skred_command === "function" && typeof M.allocateUTF8 === "function") {
    try {
      const ptr = M.allocateUTF8(cmd);
      M._skred_command(ptr);
      if (typeof M._free === "function") M._free(ptr);
    } catch (err) {
      console.warn("[sid-to-skode] Error executing skred command ptr:", err);
    }
  }
}

export function initEngine(callback) {
  if (moduleReady) {
    if (callback) callback(true);
    return;
  }

  win.Module = win.Module || {};
  win.Module.locateFile = function (path) {
    if (typeof window !== "undefined") {
      return new URL("vendor/skred/" + path, window.location.href).href;
    }
    return "/vendor/skred/" + path;
  };

  let initializedDone = false;
  const finishInit = () => {
    if (initializedDone) return;
    initializedDone = true;
    console.log("[sid-to-skode] Skred WASM engine initialized.");
    moduleReady = true;

    try {
      if (typeof win.Module._skred_enumerate_devices === "function") {
        win.Module._skred_enumerate_devices(0);
      }
      if (typeof win.Module._skred_audio_select === "function") {
        win.Module._skred_audio_select(0, 0);
        win.Module._skred_audio_select(1, -2);
      }
      if (typeof win.Module._skred_start === "function") {
        const res = win.Module._skred_start(128, 256, -1);
        engineStarted = (res === 0);
      }
      executeSkredCommand("stop");
      executeSkredCommand("S-1");
      executeSkredCommand("V-6");
    } catch (e) {
      console.error("[sid-to-skode] Error starting audio device:", e);
    }

    if (callback) callback(true);
  };

  if (win.Module.calledRun) {
    finishInit();
  } else {
    const prevOnRuntimeInitialized = win.Module.onRuntimeInitialized;
    win.Module.onRuntimeInitialized = function () {
      if (prevOnRuntimeInitialized) prevOnRuntimeInitialized();
      finishInit();
    };
  }

  // Also load siddump WASM module
  import("#vendor/siddump_wasm.js")
    .then((mod) => {
      const factory = mod.default || mod;
      if (typeof factory === "function") {
        return factory();
      }
      return null;
    })
    .then((modInstance) => {
      if (modInstance) {
        siddumpModule = modInstance;
        console.log("[sid-to-skode] In-browser siddump WASM ready.");
      }
    })
    .catch((err) => {
      console.warn("[sid-to-skode] Note: siddump WASM loading deferred or error:", err);
    });
}

// ---------------------------------------------------------------------------
// 2. Playback Transport Controls
// ---------------------------------------------------------------------------

export function playSkode(script, steps) {
  totalSongSteps = steps;
  currentStepNumber = 0;
  isPlaybackActive = true;
  isPlaybackPaused = false;

  // Unlock audio context if needed
  if (win.Module && win.Module.audioContext && win.Module.audioContext.state === "suspended") {
    win.Module.audioContext.resume();
  }

  executeSkredCommand("stop");
  executeSkredCommand("S-1");
  executeSkredCommand(script);
  executeSkredCommand("start");
}

export function pausePlayback() {
  if (isPlaybackActive) {
    isPlaybackPaused = true;
    executeSkredCommand("pause");
  }
}

export function resumePlayback() {
  if (isPlaybackActive && isPlaybackPaused) {
    isPlaybackPaused = false;
    executeSkredCommand("start");
  }
}

export function stopPlayback() {
  isPlaybackActive = false;
  isPlaybackPaused = false;
  executeSkredCommand("stop");
  executeSkredCommand("S-1");
  if (playbackEndedCallback) playbackEndedCallback();
}

export function setVolume(volDb) {
  currentMasterVolume = volDb;
  executeSkredCommand("V" + volDb);
}

export function setStereoProfile(mode) {
  // mode: 0 = Headphone, 1 = Amiga Hardware, 2 = Mono
  if (mode === 0) {
    executeSkredCommand("v0 p-0.6; v1 p0.6; v2 p0.0");
  } else if (mode === 1) {
    executeSkredCommand("v0 p-1.0; v1 p1.0; v2 p0.0");
  } else {
    executeSkredCommand("v0 p0.0; v1 p0.0; v2 p0.0");
  }
}

export function registerPlaybackListener(onStep, onEnd) {
  playbackStepCallback = onStep;
  playbackEndedCallback = onEnd;
}

// ---------------------------------------------------------------------------
// 3. File Loading & DeepSID Client
// ---------------------------------------------------------------------------

export function registerFileDrop(callback) {
  if (typeof window === "undefined") return;

  const handleDrop = async (e) => {
    e.preventDefault();
    e.stopPropagation();

    const files = e.dataTransfer ? e.dataTransfer.files : e.target.files;
    if (!files || files.length === 0) return;

    const file = files[0];
    const name = file.name;

    if (name.endsWith(".sid") || name.endsWith(".SID")) {
      const buffer = await file.arrayBuffer();
      const dumpText = await runSidDumpWasm(new Uint8Array(buffer), name);
      if (dumpText && callback) {
        callback(name, dumpText);
      }
    } else {
      const text = await file.text();
      if (callback) callback(name, text);
    }
  };

  window.addEventListener("dragover", (e) => e.preventDefault());
  window.addEventListener("drop", handleDrop);
}

export function runSidDumpWasm(bytes, filename) {
  return new Promise((resolve) => {
    if (!siddumpModule) {
      console.warn("[sid-to-skode] siddump WASM not loaded, attempting fallback...");
      import("#vendor/siddump_wasm.js")
        .then(m => (m.default || m)())
        .then(mod => {
          siddumpModule = mod;
          resolve(executeDumpOnModule(mod, bytes, filename));
        })
        .catch(err => {
          console.error("Failed to execute siddump WASM:", err);
          resolve("");
        });
      return;
    }
    resolve(executeDumpOnModule(siddumpModule, bytes, filename));
  });
}

function executeDumpOnModule(mod, bytes, filename) {
  try {
    const virtualName = "tune.sid";
    mod.FS.writeFile(virtualName, bytes);
    let output = "";
    mod.print = (text) => { output += text + "\n"; };
    mod.printErr = (text) => { console.warn("[siddump]", text); };
    // Dump up to 90 seconds (4500 frames)
    mod.callMain([virtualName, "-t90"]);
    return output;
  } catch (err) {
    console.error("[sid-to-skode] Error running siddump WASM:", err);
    return "";
  }
}

export function fetchRandomDeepSid(onSuccess, onError) {
  fetch("https://deepsid.chordian.net/php/radio_random_file.php")
    .then(r => r.json())
    .then(data => {
      if (data.status === "ok" && data.path) {
        const fileUrl = "https://deepsid.chordian.net/music/" + encodeURI(data.path);
        const fileName = data.path.split("/").pop();
        return fetch(fileUrl)
          .then(r => r.arrayBuffer())
          .then(async (ab) => {
            const dumpText = await runSidDumpWasm(new Uint8Array(ab), fileName);
            if (dumpText && onSuccess) {
              onSuccess(fileName, dumpText);
            } else if (onError) {
              onError("Failed to generate SID dump for: " + fileName);
            }
          });
      } else if (onError) {
        onError("DeepSID returned empty track.");
      }
    })
    .catch(err => {
      if (onError) onError(String(err));
    });
}

export function copyToClipboard(text) {
  if (typeof navigator !== "undefined" && navigator.clipboard) {
    navigator.clipboard.writeText(text);
  }
}

export function downloadFile(filename, content) {
  if (typeof window === "undefined") return;
  const blob = new Blob([content], { type: "text/plain;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}
