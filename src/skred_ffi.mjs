// JavaScript FFI Bridge for sid-to-skode
// Integrates Skred 0.80.0 WASM engine, in-browser siddump WASM, and Web Audio APIs

const win = typeof window !== "undefined" ? window : globalThis;

let moduleReady = false;
let engineStarted = false;
let audioUnlocked = false;
let currentMasterVolume = -6;
let isPlaybackActive = false;
let isPlaybackPaused = false;
let playbackStepCallback = null;
let playbackEndedCallback = null;
let activeSongTotalSteps = 0;
let lastReportedStep = -1;

let siddumpFactory = null;

// WASM Control Event polling setup
const MAX_EVENTS_BATCH = 64;
const EVENT_SIZE = 72;
let wasmEventsBuffer = null;
let eventPumpRunning = false;
let pumpAnimationId = null;
let currentEventSubscription = null;
const commandQueue = [];

// ---------------------------------------------------------------------------
// 1. Skred WASM Audio Engine Initialization & Device Management
// ---------------------------------------------------------------------------

function getWasmModule() {
  if (win.Module && (typeof win.Module.ccall === "function" || typeof win.Module._skred_start === "function")) {
    return win.Module;
  }
  return null;
}

function ensureAudioContext() {
  const M = win.Module;
  if (M && M.audioContext && M.audioContext.state === "suspended") {
    M.audioContext.resume().catch(() => {});
  }
  if (win.AL && win.AL.currentCtx && win.AL.currentCtx.audioCtx && win.AL.currentCtx.audioCtx.state === "suspended") {
    win.AL.currentCtx.audioCtx.resume().catch(() => {});
  }
  if (win.miniaudio && Array.isArray(win.miniaudio.devices)) {
    for (const dev of win.miniaudio.devices) {
      if (dev && dev.webaudio && dev.webaudio.state === "suspended") {
        dev.webaudio.resume().catch(() => {});
      }
    }
  }
}

export function ensureEngineRunning() {
  const M = getWasmModule();
  if (!M) return false;
  ensureAudioContext();
  if (typeof M._skred_audio_running === "function" && M._skred_audio_running()) {
    return true;
  }
  try {
    if (win.Module.FS) {
      try { win.Module.FS.mkdir("/waves"); } catch (e) {}
      try { win.Module.FS.mkdir("waves"); } catch (e) {}
    }
    if (typeof M._skred_enumerate_devices === "function") {
      M._skred_enumerate_devices(0);
    }
    if (typeof M._skred_audio_select === "function") {
      M._skred_audio_select(0, 0);
      M._skred_audio_select(1, -2);
    }
    if (typeof M._skred_start === "function") {
      const res = M._skred_start(128, 256, -1);
      console.log("[sid-to-skode] _skred_start returned:", res);
      engineStarted = (res === 0);
    }
    if (typeof M._skred_logger === "function") {
      M._skred_logger(1);
    }
    executeSkredCommand("stop");
    executeSkredCommand("Y-1");
    executeSkredCommand("S-1");
    executeSkredCommand("V" + currentMasterVolume);
    flushCommandQueue();
    return engineStarted;
  } catch (err) {
    console.warn("[sid-to-skode] ensureEngineRunning warning:", err);
  }
  return false;
}

function unlockAudio() {
  if (audioUnlocked) return;
  audioUnlocked = true;
  ensureAudioContext();
  ensureEngineRunning();
  removeAudioUnlockListeners();
}

function removeAudioUnlockListeners() {
  if (typeof win.removeEventListener === "function") {
    win.removeEventListener("pointerdown", unlockAudio);
    win.removeEventListener("touchstart", unlockAudio);
    win.removeEventListener("keydown", unlockAudio);
    win.removeEventListener("click", unlockAudio);
  }
}

if (typeof win.addEventListener === "function") {
  win.addEventListener("pointerdown", unlockAudio, { passive: true });
  win.addEventListener("touchstart", unlockAudio, { passive: true });
  win.addEventListener("keydown", unlockAudio, { passive: true });
  win.addEventListener("click", unlockAudio, { passive: true });
}

export function executeSkredCommand(cmd) {
  const M = getWasmModule();
  if (!M) {
    commandQueue.push(cmd);
    return;
  }

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

export function sendCommand(cmd) {
  executeSkredCommand(cmd);
}

export function setMasterVolume(volDb) {
  currentMasterVolume = volDb;
  executeSkredCommand("V" + volDb);
}

export function panicEngine() {
  stopPlayback();
  executeSkredCommand("S-1");
  executeSkredCommand("Y-1");
}

function flushCommandQueue() {
  const M = getWasmModule();
  if (!M || !engineStarted) return;
  while (commandQueue.length > 0) {
    const cmd = commandQueue.shift();
    try {
      M.ccall("skred_command", "number", ["string"], [cmd]);
    } catch (e) {
      console.error("[sid-to-skode] Error executing queued command:", cmd, e);
    }
  }
}

function startWasmEventPump(M) {
  if (!M || typeof M._skred_control_event_poll !== "function") return;
  if (!wasmEventsBuffer && typeof M._malloc === "function") {
    wasmEventsBuffer = M._malloc(MAX_EVENTS_BATCH * EVENT_SIZE);
  }
  if (eventPumpRunning) return;
  eventPumpRunning = true;

  function pump() {
    if (!isPlaybackActive) {
      eventPumpRunning = false;
      pumpAnimationId = null;
      return;
    }

    if (
      M &&
      typeof M._skred_control_event_poll === "function" &&
      wasmEventsBuffer &&
      M.HEAPU8
    ) {
      try {
        const count = M._skred_control_event_poll(wasmEventsBuffer, MAX_EVENTS_BATCH);
        if (count > 0) {
          const events = [];
          const view = new DataView(M.HEAPU8.buffer, wasmEventsBuffer, count * EVENT_SIZE);
          for (let i = 0; i < count; i++) {
            const base = i * EVENT_SIZE;
            const t = view.getUint32(base + 0, true);
            const opcode = view.getUint32(base + 4, true);
            const sample = Number(view.getBigUint64(base + 8, true));
            const seq = Number(view.getBigUint64(base + 16, true));
            const v = view.getInt32(base + 24, true);
            const p = view.getInt32(base + 28, true);
            const s = view.getInt32(base + 32, true);
            const tag = view.getInt32(base + 36, true);
            const id = view.getInt32(base + 40, true);
            const value_count = view.getUint32(base + 44, true);
            const vals = [
              view.getFloat64(base + 48, true),
              view.getFloat64(base + 56, true),
              view.getFloat64(base + 64, true),
            ];
            events.push({ t, opcode, sample, seq, v, p, s, tag, id, value_count, vals });

            // Real-time Step Tracking: event type 9 (SKRED_CONTROL_EVENT_PATTERN_STEP) on pattern 0
            if (isPlaybackActive && t === 9 && p === 0) {
              if (s !== lastReportedStep && s >= 0) {
                if (lastReportedStep >= activeSongTotalSteps - 2 && s === 0 && activeSongTotalSteps > 2) {
                  stopPlayback();
                  if (playbackEndedCallback) playbackEndedCallback();
                  return;
                }
                lastReportedStep = s;
                if (playbackStepCallback) {
                  playbackStepCallback(s, activeSongTotalSteps);
                }
              }
            }

            // Song Completion: explicit end-of-song marker event 4 (USER id 127)
            if (isPlaybackActive && t === 4 && id === 127) {
              stopPlayback();
              if (playbackEndedCallback) playbackEndedCallback();
              return;
            }
          }
          if (currentEventSubscription) {
            currentEventSubscription(events);
          }
        }
      } catch (err) {
        console.error("[sid-to-skode] Event pump error:", err);
      }
    }
    pumpAnimationId = requestAnimationFrame(pump);
  }
  pumpAnimationId = requestAnimationFrame(pump);
}

function stopWasmEventPump() {
  eventPumpRunning = false;
  if (pumpAnimationId !== null) {
    cancelAnimationFrame(pumpAnimationId);
    pumpAnimationId = null;
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
    console.log("[sid-to-skode] Skred WASM runtime initialized.");
    moduleReady = true;

    if (callback) callback(true);
  };

  const prevInit = win.Module.onRuntimeInitialized;
  win.Module.onRuntimeInitialized = function () {
    if (prevInit) prevInit();
    finishInit();
  };

  if (
    win.Module.calledRun ||
    (win.Module.HEAPU32 && typeof win.Module.ccall === "function") ||
    typeof win.Module._skred_start === "function"
  ) {
    finishInit();
  }
}

// ---------------------------------------------------------------------------
// 2. Playback Transport Controls
// ---------------------------------------------------------------------------

export function playSkode(script, steps) {
  activeSongTotalSteps = typeof steps === "number" ? steps : 0;
  isPlaybackActive = true;
  isPlaybackPaused = false;
  lastReportedStep = -1;

  unlockAudio();
  ensureAudioContext();
  ensureEngineRunning();

  const M = getWasmModule();
  if (!M) {
    console.warn("[sid-to-skode] WASM module not ready for playback.");
    return;
  }

  // 1. Halt previous playback, reset patterns and voices
  executeSkredCommand("stop");
  executeSkredCommand("Y-1");
  executeSkredCommand("S-1");

  // 2. Write script to VFS and load it cleanly via /ls
  try {
    if (M.FS) {
      try { M.FS.writeFile("/song.sk", script); } catch (e) {}
      try { M.FS.writeFile("song.sk", script); } catch (e) {}
      executeSkredCommand("[song.sk] /ls");
      executeSkredCommand("y0 yc1; y1 yc1; y2 yc1; y3 yc1;");
      executeSkredCommand("V" + currentMasterVolume);
      executeSkredCommand("play");
    } else {
      executeSkredCommand(script);
      executeSkredCommand("y0 yc1; y1 yc1; y2 yc1; y3 yc1;");
      executeSkredCommand("V" + currentMasterVolume);
      executeSkredCommand("play");
    }
    startWasmEventPump(M);
  } catch (err) {
    console.error("[sid-to-skode] Error starting playback:", err);
  }
}

export function pausePlayback() {
  if (!isPlaybackActive) return;
  isPlaybackPaused = true;
  stopWasmEventPump();
  const M = win.Module;
  if (M && M.audioContext && M.audioContext.state === "running") {
    M.audioContext.suspend().catch(() => {});
  }
  executeSkredCommand("Z2");
}

export function resumePlayback() {
  if (!isPlaybackActive) return;
  isPlaybackPaused = false;
  ensureAudioContext();
  executeSkredCommand("Z3");
  const M = getWasmModule();
  if (M) startWasmEventPump(M);
}

export function stopPlayback() {
  isPlaybackActive = false;
  isPlaybackPaused = false;
  lastReportedStep = -1;
  stopWasmEventPump();
  ensureAudioContext();
  executeSkredCommand("stop");
  executeSkredCommand("Y-1");
  executeSkredCommand("S-1");
}

export function setStereoProfile(mode) {
  // mode: 0 = Headphone (75%), 1 = Wide (100%), 2 = Mono (0%)
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
// 3. File Loading & In-Browser SID Emulation (siddump WASM)
// ---------------------------------------------------------------------------

export function registerFileDrop(callback) {
  if (typeof window === "undefined") return;

  async function handleFile(file) {
    if (!file) return;
    const name = file.name;
    try {
      const buffer = await file.arrayBuffer();
      if (name.toLowerCase().endsWith(".sid")) {
        const dumpText = await runSidDumpWasm(new Uint8Array(buffer), name);
        if (dumpText && callback) {
          callback(name, dumpText);
        }
      } else {
        const text = new TextDecoder().decode(buffer);
        if (callback) callback(name, text);
      }
    } catch (err) {
      console.error("[sid-to-skode] Error reading file:", err);
    }
  }

  window.addEventListener("dragover", (e) => {
    e.preventDefault();
    const zone = document.getElementById("drop-zone");
    if (zone) zone.classList.add("drag-over");
  });

  window.addEventListener("dragleave", (e) => {
    if (e.target === document.body || e.clientX <= 0 || e.clientY <= 0) {
      const zone = document.getElementById("drop-zone");
      if (zone) zone.classList.remove("drag-over");
    }
  });

  window.addEventListener("drop", (e) => {
    e.preventDefault();
    const zone = document.getElementById("drop-zone");
    if (zone) zone.classList.remove("drag-over");
    const files = e.dataTransfer ? e.dataTransfer.files : null;
    if (files && files.length > 0) {
      handleFile(files[0]);
    }
  });

  document.addEventListener("change", (e) => {
    if (e.target && e.target.id === "file-input" && e.target.files && e.target.files[0]) {
      handleFile(e.target.files[0]);
    }
  });
}

export async function runSidDumpWasm(bytes, filename) {
  try {
    if (!siddumpFactory) {
      const mod = await import("#vendor/siddump_wasm.js");
      siddumpFactory = mod.default || mod;
    }

    let output = "";
    const instance = await siddumpFactory({
      locateFile: (p) => {
        if (typeof window !== "undefined") {
          return new URL("vendor/" + p, window.location.href).href;
        }
        return "/vendor/" + p;
      },
      noInitialRun: true,
      print: (text) => {
        output += text + "\n";
      },
      printErr: (text) => {
        console.warn("[siddump]", text);
      },
    });

    const virtualFile = "tune.sid";
    instance.FS.writeFile(virtualFile, bytes);

    // Dump up to 90 seconds (4500 frames) of subtune 0 (default song)
    try {
      instance.callMain([virtualFile, "-t90"]);
    } catch (_) {
      // Emscripten exits with ExitStatus upon normal completion
    }
    return output;
  } catch (err) {
    console.error("[sid-to-skode] Error executing siddump WASM on " + filename + ":", err);
    return "";
  }
}

// ---------------------------------------------------------------------------
// 4. Curated Demo Catalog & Random SID Loader
// ---------------------------------------------------------------------------

export const SID_CATALOG = [
  {
    title: "Commando",
    author: "Rob Hubbard",
    filename: "commando.sid",
    url: "demos/commando.sid",
    source: "Elite (1985)",
  },
  {
    title: "Monty on the Run",
    author: "Rob Hubbard",
    filename: "monty_on_the_run.sid",
    url: "demos/monty_on_the_run.sid",
    source: "Gremlin Graphics (1985)",
  },
  {
    title: "Sanxion",
    author: "Rob Hubbard",
    filename: "sanxion.sid",
    url: "demos/sanxion.sid",
    source: "Thalamus (1986)",
  },
  {
    title: "Delta",
    author: "Rob Hubbard",
    filename: "delta.sid",
    url: "demos/delta.sid",
    source: "Thalamus (1987)",
  },
  {
    title: "International Karate",
    author: "Rob Hubbard",
    filename: "international_karate.sid",
    url: "demos/international_karate.sid",
    source: "System 3 (1986)",
  },
  {
    title: "Crazy Comets",
    author: "Rob Hubbard",
    filename: "crazy_comets.sid",
    url: "demos/crazy_comets.sid",
    source: "Martech (1985)",
  },
  {
    title: "Lightforce",
    author: "Rob Hubbard",
    filename: "lightforce.sid",
    url: "demos/lightforce.sid",
    source: "Faster Than Light (1986)",
  },
  {
    title: "Comic Bakery",
    author: "Martin Galway",
    filename: "comic_bakery.sid",
    url: "demos/comic_bakery.sid",
    source: "Imagine (1986)",
  },
  {
    title: "Arkanoid",
    author: "Martin Galway",
    filename: "arkanoid.sid",
    url: "demos/arkanoid.sid",
    source: "Imagine (1987)",
  },
  {
    title: "Wizball",
    author: "Martin Galway",
    filename: "wizball.sid",
    url: "demos/wizball.sid",
    source: "Ocean (1987)",
  },
  {
    title: "Rambo: First Blood Part II",
    author: "Martin Galway",
    filename: "rambo.sid",
    url: "demos/rambo.sid",
    source: "Ocean (1985)",
  },
  {
    title: "Ocean Loader 2",
    author: "Martin Galway",
    filename: "ocean_loader_2.sid",
    url: "demos/ocean_loader_2.sid",
    source: "Ocean (1985)",
  },
  {
    title: "Green Beret",
    author: "Martin Galway",
    filename: "green_beret.sid",
    url: "demos/green_beret.sid",
    source: "Imagine (1986)",
  },
  {
    title: "Cybernoid",
    author: "Jeroen Tel",
    filename: "cybernoid.sid",
    url: "demos/cybernoid.sid",
    source: "Hewson (1988)",
  },
  {
    title: "Cybernoid II",
    author: "Jeroen Tel",
    filename: "cybernoid_2.sid",
    url: "demos/cybernoid_2.sid",
    source: "Hewson (1988)",
  },
  {
    title: "The Great Giana Sisters",
    author: "Chris Hülsbeck",
    filename: "great_giana_sisters.sid",
    url: "demos/great_giana_sisters.sid",
    source: "Rainbow Arts (1987)",
  },
  {
    title: "Last Ninja 2",
    author: "Matt Gray",
    filename: "last_ninja_2.sid",
    url: "demos/last_ninja_2.sid",
    source: "System 3 (1988)",
  },
];

export async function fetchRandomSid(onSuccess, onError) {
  try {
    const idx = Math.floor(Math.random() * SID_CATALOG.length);
    const item = SID_CATALOG[idx];
    return loadDemoSid(item.url, item.filename, item.title, item.author, onSuccess, onError);
  } catch (err) {
    console.error("[sid-to-skode] Error loading random SID:", err);
    if (onError) onError(err.message || "Failed to load demo");
  }
}

export async function loadDemoSid(url, filename, title, author, onSuccess, onError) {
  try {
    // 1. Instant loading: Try fetching pre-dumped file directly (.dump) to avoid WASM CPU overhead
    const dumpUrl = url.replace(/\.sid$/i, ".dump");
    const targetDumpUrl =
      typeof window !== "undefined"
        ? new URL(dumpUrl, window.location.href).href
        : dumpUrl;

    try {
      const dumpRes = await fetch(targetDumpUrl);
      if (dumpRes.ok) {
        const dumpText = await dumpRes.text();
        if (dumpText && dumpText.length > 100) {
          if (onSuccess) onSuccess(filename, dumpText, title, author);
          return;
        }
      }
    } catch (_) {
      // Fallback to WASM emulation below if .dump fetch fails
    }

    // 2. Emulation fallback: Fetch raw .sid binary and emulate via siddump WASM
    const targetUrl =
      typeof window !== "undefined"
        ? new URL(url, window.location.href).href
        : url;
    const res = await fetch(targetUrl);
    if (!res.ok) throw new Error("HTTP " + res.status);
    const buf = await res.arrayBuffer();
    const dumpText = await runSidDumpWasm(new Uint8Array(buf), filename);
    if (!dumpText) throw new Error("Could not dump SID tune.");
    if (onSuccess) {
      onSuccess(filename, dumpText, title, author);
    }
  } catch (err) {
    console.error("[sid-to-skode] Error loading demo SID:", err);
    if (onError) onError(err.message || "Failed to load demo");
  }
}

// ---------------------------------------------------------------------------
// 5. Utility Helpers (Download & Clipboard)
// ---------------------------------------------------------------------------

export function copyToClipboard(text) {
  if (navigator && navigator.clipboard && navigator.clipboard.writeText) {
    navigator.clipboard.writeText(text).catch(() => {});
  }
}

export function downloadFile(filename, text) {
  if (typeof document === "undefined") return;
  const blob = new Blob([text], { type: "text/plain;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  setTimeout(() => {
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  }, 100);
}
