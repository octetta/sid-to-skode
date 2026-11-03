// JavaScript FFI Bridge for sid-to-skode
// Integrates Skred 0.80.0 WASM engine, in-browser siddump WASM, and Web Audio APIs
import { createReplDom, toggleRepl, appendReplOutput } from "./repl.mjs";

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
    executeSkredCommand("Z0");
    executeSkredCommand("Y-1");
    executeSkredCommand("S-1");
    executeSkredCommand("V" + currentMasterVolume);
    executeSkredCommand("[stop]: /cer 0 Z0 O DQ ?ce!;");
    executeSkredCommand("[play]: ?ce! /cer 1 Z0 Z! y0 z1 y1 z1 y2 z1 y3 z1 y127 z1;");
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

export function executeSkredCommand(rawCmd) {
  let cmd = rawCmd;
  if (typeof cmd === "string") {
    const trimmed = cmd.trim().toLowerCase();
    if (trimmed === "stop") {
      cmd = "/cer 0 Z0 O DQ ?ce!; S-1; Y-1";
    } else if (trimmed === "play") {
      cmd = "?ce! /cer 1 Z0 Z! y0 z1 y1 z1 y2 z1 y3 z1 y127 z1";
    }
  }

  const M = getWasmModule();
  if (!M) {
    commandQueue.push(cmd);
    return 0;
  }

  ensureAudioContext();
  if (typeof M._skred_logger === "function") {
    try { M._skred_logger(1); } catch (e) {}
  }

  let res = 0;
  if (typeof M.ccall === "function") {
    try {
      res = M.ccall("skred_command", "number", ["string"], [cmd]);
    } catch (err) {
      console.warn("[sid-to-skode] Error executing skred command:", err);
      return -1;
    }
  } else if (typeof M._skred_command === "function" && typeof M.allocateUTF8 === "function") {
    try {
      const ptr = M.allocateUTF8(cmd);
      res = M._skred_command(ptr);
      if (typeof M._free === "function") M._free(ptr);
    } catch (err) {
      console.warn("[sid-to-skode] Error executing skred command ptr:", err);
      return -1;
    }
  }

  if (typeof M._skred_log === "function" && typeof M.UTF8ToString === "function") {
    try {
      const logPtr = M._skred_log();
      if (logPtr) {
        const text = M.UTF8ToString(logPtr);
        if (text && text.trim().length > 0) {
          appendReplOutput("out", text.trim());
        }
      }
    } catch (e) {}
  }

  return res;
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

  createReplDom();

  const prevPrint = win.Module.print;
  win.Module.print = function (text) {
    if (prevPrint) prevPrint(text);
    appendReplOutput("out", text);
    console.log("[skred]", text);
  };

  const prevPrintErr = win.Module.printErr;
  win.Module.printErr = function (text) {
    if (prevPrintErr) prevPrintErr(text);
    appendReplOutput("err", text);
    console.warn("[skred]", text);
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
  executeSkredCommand("/cer 0 Z0 O DQ ?ce!; S-1; Y-1");

  // 2. Write script to VFS and load it cleanly via /ls
  try {
    if (M.FS) {
      try { M.FS.writeFile("/song.sk", script); } catch (e) {}
      try { M.FS.writeFile("song.sk", script); } catch (e) {}
      executeSkredCommand("[song.sk] /ls");
      executeSkredCommand("y0 yc1; y1 yc1; y2 yc1; y3 yc1;");
      executeSkredCommand("V" + currentMasterVolume);
      executeSkredCommand("?ce! /cer 1 Z0 Z! y0 z1 y1 z1 y2 z1 y3 z1 y127 z1");
    } else {
      executeSkredCommand(script);
      executeSkredCommand("y0 yc1; y1 yc1; y2 yc1; y3 yc1;");
      executeSkredCommand("V" + currentMasterVolume);
      executeSkredCommand("?ce! /cer 1 Z0 Z! y0 z1 y1 z1 y2 z1 y3 z1 y127 z1");
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
  executeSkredCommand("/cer 0 Z0 O DQ ?ce!; S-1; Y-1");
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
        const dumpText = await runSidDumpWasm(new Uint8Array(buffer), name, 210);
        if (dumpText && callback) {
          callback(name, dumpText, "📁 Local File Drop: " + name, "");
        }
      } else {
        const text = new TextDecoder().decode(buffer);
        if (callback) callback(name, text, "📁 Local Dump File: " + name, "");
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

  // Check URL parameters for initial song loading (like mod-to-skode)
  setTimeout(() => {
    checkInitialUrlParams(callback);
  }, 100);
}

export async function runSidDumpWasm(bytes, filename, durationSeconds) {
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

    // If duration not specified, default to 210s (3.5 minutes) rather than 90s!
    const dur = typeof durationSeconds === "number" && durationSeconds > 0 ? durationSeconds : 210;
    try {
      instance.callMain([virtualFile, "-t" + dur]);
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
// 4. Online HVSC Catalog & Dynamic Web Fetcher (No Pre-Download Needed)
// ---------------------------------------------------------------------------

export const HVSC_CATALOG = [
  // Rob Hubbard
  {
    title: "Commando",
    author: "Rob Hubbard",
    filename: "commando.sid",
    hvscPath: "MUSICIANS/H/Hubbard_Rob/Commando.sid",
    duration: 236,
    source: "Elite (1985)",
  },
  {
    title: "Monty on the Run",
    author: "Rob Hubbard",
    filename: "monty_on_the_run.sid",
    hvscPath: "MUSICIANS/H/Hubbard_Rob/Monty_on_the_Run.sid",
    duration: 350,
    source: "Gremlin Graphics (1985)",
  },
  {
    title: "Sanxion",
    author: "Rob Hubbard",
    filename: "sanxion.sid",
    hvscPath: "MUSICIANS/H/Hubbard_Rob/Sanxion.sid",
    duration: 218,
    source: "Thalamus (1986)",
  },
  {
    title: "Delta",
    author: "Rob Hubbard",
    filename: "delta.sid",
    hvscPath: "MUSICIANS/H/Hubbard_Rob/Delta.sid",
    duration: 216,
    source: "Thalamus (1987)",
  },
  {
    title: "International Karate",
    author: "Rob Hubbard",
    filename: "international_karate.sid",
    hvscPath: "MUSICIANS/H/Hubbard_Rob/International_Karate.sid",
    duration: 240,
    source: "System 3 (1986)",
  },
  {
    title: "Crazy Comets",
    author: "Rob Hubbard",
    filename: "crazy_comets.sid",
    hvscPath: "MUSICIANS/H/Hubbard_Rob/Crazy_Comets.sid",
    duration: 276,
    source: "Martech (1985)",
  },
  {
    title: "Lightforce",
    author: "Rob Hubbard",
    filename: "lightforce.sid",
    hvscPath: "MUSICIANS/H/Hubbard_Rob/Lightforce.sid",
    duration: 250,
    source: "Faster Than Light (1986)",
  },
  {
    title: "Thrust",
    author: "Rob Hubbard",
    filename: "thrust.sid",
    hvscPath: "MUSICIANS/H/Hubbard_Rob/Thrust.sid",
    duration: 210,
    source: "Firebird (1986)",
  },
  {
    title: "Auf Wiedersehen Monty",
    author: "Rob Hubbard",
    filename: "auf_wiedersehen_monty.sid",
    hvscPath: "MUSICIANS/H/Hubbard_Rob/Auf_Wiedersehen_Monty.sid",
    duration: 220,
    source: "Gremlin Graphics (1987)",
  },
  {
    title: "Action Biker",
    author: "Rob Hubbard",
    filename: "action_biker.sid",
    hvscPath: "MUSICIANS/H/Hubbard_Rob/Action_Biker.sid",
    duration: 210,
    source: "Mastertronic (1985)",
  },
  {
    title: "Flash Gordon",
    author: "Rob Hubbard",
    filename: "flash_gordon.sid",
    hvscPath: "MUSICIANS/H/Hubbard_Rob/Flash_Gordon.sid",
    duration: 200,
    source: "Mastertronic (1986)",
  },
  {
    title: "Chimera",
    author: "Rob Hubbard",
    filename: "chimera.sid",
    hvscPath: "MUSICIANS/H/Hubbard_Rob/Chimera.sid",
    duration: 210,
    source: "Firebird (1985)",
  },

  // Martin Galway
  {
    title: "Comic Bakery",
    author: "Martin Galway",
    filename: "comic_bakery.sid",
    hvscPath: "MUSICIANS/G/Galway_Martin/Comic_Bakery.sid",
    duration: 189,
    source: "Imagine (1986)",
  },
  {
    title: "Arkanoid",
    author: "Martin Galway",
    filename: "arkanoid.sid",
    hvscPath: "MUSICIANS/G/Galway_Martin/Arkanoid.sid",
    duration: 142,
    source: "Imagine (1987)",
  },
  {
    title: "Wizball",
    author: "Martin Galway",
    filename: "wizball.sid",
    hvscPath: "MUSICIANS/G/Galway_Martin/Wizball.sid",
    duration: 215,
    source: "Ocean (1987)",
  },
  {
    title: "Rambo: First Blood Part II",
    author: "Martin Galway",
    filename: "rambo.sid",
    hvscPath: "MUSICIANS/G/Galway_Martin/Rambo_First_Blood_Part_II.sid",
    duration: 240,
    source: "Ocean (1985)",
  },
  {
    title: "Ocean Loader 2",
    author: "Martin Galway",
    filename: "ocean_loader_2.sid",
    hvscPath: "MUSICIANS/G/Galway_Martin/Ocean_Loader_2.sid",
    duration: 253,
    source: "Ocean (1985)",
  },
  {
    title: "Green Beret",
    author: "Martin Galway",
    filename: "green_beret.sid",
    hvscPath: "MUSICIANS/G/Galway_Martin/Green_Beret.sid",
    duration: 213,
    source: "Imagine (1986)",
  },
  {
    title: "Miami Vice",
    author: "Martin Galway",
    filename: "miami_vice.sid",
    hvscPath: "MUSICIANS/G/Galway_Martin/Miami_Vice.sid",
    duration: 195,
    source: "Ocean (1986)",
  },
  {
    title: "Parallax",
    author: "Martin Galway",
    filename: "parallax.sid",
    hvscPath: "MUSICIANS/G/Galway_Martin/Parallax.sid",
    duration: 230,
    source: "Ocean (1986)",
  },
  {
    title: "Terra Cresta",
    author: "Martin Galway",
    filename: "terra_cresta.sid",
    hvscPath: "MUSICIANS/G/Galway_Martin/Terra_Cresta.sid",
    duration: 200,
    source: "Imagine (1986)",
  },

  // Jeroen Tel / Maniacs of Noise
  {
    title: "Cybernoid",
    author: "Jeroen Tel",
    filename: "cybernoid.sid",
    hvscPath: "MUSICIANS/T/Tel_Jeroen/Cybernoid.sid",
    duration: 240,
    source: "Hewson (1988)",
  },
  {
    title: "Cybernoid II",
    author: "Jeroen Tel",
    filename: "cybernoid_2.sid",
    hvscPath: "MUSICIANS/T/Tel_Jeroen/Cybernoid_II.sid",
    duration: 240,
    source: "Hewson (1988)",
  },
  {
    title: "Turbo Outrun",
    author: "Jeroen Tel",
    filename: "turbo_outrun.sid",
    hvscPath: "MUSICIANS/T/Tel_Jeroen/Turbo_Outrun.sid",
    duration: 220,
    source: "Sega / US Gold (1989)",
  },
  {
    title: "Supremacy",
    author: "Jeroen Tel",
    filename: "supremacy.sid",
    hvscPath: "MUSICIANS/T/Tel_Jeroen/Supremacy.sid",
    duration: 260,
    source: "Virgin (1990)",
  },
  {
    title: "Myth: History in the Making",
    author: "Jeroen Tel",
    filename: "myth.sid",
    hvscPath: "MUSICIANS/T/Tel_Jeroen/Myth.sid",
    duration: 240,
    source: "System 3 (1989)",
  },
  {
    title: "Rubicon",
    author: "Jeroen Tel",
    filename: "rubicon.sid",
    hvscPath: "MUSICIANS/T/Tel_Jeroen/Rubicon.sid",
    duration: 250,
    source: "21st Century (1991)",
  },
  {
    title: "Afterburner",
    author: "Jeroen Tel",
    filename: "afterburner.sid",
    hvscPath: "MUSICIANS/T/Tel_Jeroen/Afterburner.sid",
    duration: 210,
    source: "Activision (1988)",
  },
  {
    title: "Eliminator",
    author: "Jeroen Tel",
    filename: "eliminator.sid",
    hvscPath: "MUSICIANS/T/Tel_Jeroen/Eliminator.sid",
    duration: 200,
    source: "Hewson (1988)",
  },
  {
    title: "Hawkeye",
    author: "Jeroen Tel",
    filename: "hawkeye.sid",
    hvscPath: "MUSICIANS/T/Tel_Jeroen/Hawkeye.sid",
    duration: 215,
    source: "Thalamus (1988)",
  },

  // Chris Hülsbeck
  {
    title: "The Great Giana Sisters",
    author: "Chris Hülsbeck",
    filename: "great_giana_sisters.sid",
    hvscPath: "MUSICIANS/H/Huelsbeck_Chris/Great_Giana_Sisters.sid",
    duration: 222,
    source: "Rainbow Arts (1987)",
  },
  {
    title: "Katakis",
    author: "Chris Hülsbeck",
    filename: "katakis.sid",
    hvscPath: "MUSICIANS/H/Huelsbeck_Chris/Katakis.sid",
    duration: 240,
    source: "Rainbow Arts (1988)",
  },
  {
    title: "R-Type",
    author: "Chris Hülsbeck",
    filename: "r_type.sid",
    hvscPath: "MUSICIANS/H/Huelsbeck_Chris/R-Type.sid",
    duration: 210,
    source: "Rainbow Arts (1988)",
  },

  // Matt Gray
  {
    title: "Last Ninja 2",
    author: "Matt Gray",
    filename: "last_ninja_2.sid",
    hvscPath: "MUSICIANS/G/Gray_Matt/Last_Ninja_2.sid",
    duration: 267,
    source: "System 3 (1988)",
  },
  {
    title: "Treasure Island Dizzy",
    author: "Matt Gray",
    filename: "treasure_island_dizzy.sid",
    hvscPath: "MUSICIANS/G/Gray_Matt/Treasure_Island_Dizzy.sid",
    duration: 180,
    source: "Codemasters (1989)",
  },
  {
    title: "Dominator",
    author: "Matt Gray",
    filename: "dominator.sid",
    hvscPath: "MUSICIANS/G/Gray_Matt/Dominator.sid",
    duration: 210,
    source: "System 3 (1989)",
  },

  // Ben Daglish
  {
    title: "The Last Ninja",
    author: "Ben Daglish",
    filename: "last_ninja.sid",
    hvscPath: "MUSICIANS/D/Daglish_Ben/Last_Ninja.sid",
    duration: 250,
    source: "System 3 (1987)",
  },
  {
    title: "Deflektor",
    author: "Ben Daglish",
    filename: "deflektor.sid",
    hvscPath: "MUSICIANS/D/Daglish_Ben/Deflektor.sid",
    duration: 210,
    source: "Vortex (1987)",
  },
  {
    title: "Trap",
    author: "Ben Daglish",
    filename: "trap.sid",
    hvscPath: "MUSICIANS/D/Daglish_Ben/Trap.sid",
    duration: 230,
    source: "Alligata (1986)",
  },
  {
    title: "Cobra",
    author: "Ben Daglish",
    filename: "cobra.sid",
    hvscPath: "MUSICIANS/D/Daglish_Ben/Cobra.sid",
    duration: 190,
    source: "Ocean (1986)",
  },

  // Tim Follin
  {
    title: "Ghouls 'n Ghosts",
    author: "Tim Follin",
    filename: "ghouls_n_ghosts.sid",
    hvscPath: "MUSICIANS/F/Follin_Tim/Ghouls_n_Ghosts.sid",
    duration: 270,
    source: "Capcom / US Gold (1989)",
  },
  {
    title: "Bionic Commando",
    author: "Tim Follin",
    filename: "bionic_commando.sid",
    hvscPath: "MUSICIANS/F/Follin_Tim/Bionic_Commando.sid",
    duration: 230,
    source: "Capcom / Go! (1988)",
  },

  // David Whittaker
  {
    title: "Glider Rider",
    author: "David Whittaker",
    filename: "glider_rider.sid",
    hvscPath: "MUSICIANS/W/Whittaker_David/Glider_Rider.sid",
    duration: 240,
    source: "Quicksilva (1986)",
  },
  {
    title: "Speedball",
    author: "David Whittaker",
    filename: "speedball.sid",
    hvscPath: "MUSICIANS/W/Whittaker_David/Speedball.sid",
    duration: 200,
    source: "Image Works (1988)",
  },
  {
    title: "Lazy Jones",
    author: "David Whittaker",
    filename: "lazy_jones.sid",
    hvscPath: "MUSICIANS/W/Whittaker_David/Lazy_Jones.sid",
    duration: 220,
    source: "Terminal Software (1984)",
  },

  // Johannes Bjerregaard & Reyn Ouwehand
  {
    title: "Shape",
    author: "Johannes Bjerregaard",
    filename: "shape.sid",
    hvscPath: "MUSICIANS/B/Bjerregaard_Johannes/Shape.sid",
    duration: 210,
    source: "Censor (1989)",
  },
  {
    title: "Flimbo's Quest",
    author: "Johannes Bjerregaard",
    filename: "flimbos_quest.sid",
    hvscPath: "MUSICIANS/B/Bjerregaard_Johannes/Flimbos_Quest_main.sid",
    duration: 220,
    source: "System 3 (1990)",
  },
  {
    title: "Last Ninja 3",
    author: "Reyn Ouwehand",
    filename: "last_ninja_3.sid",
    hvscPath: "MUSICIANS/O/Ouwehand_Reyn/Last_Ninja_3.sid",
    duration: 240,
    source: "System 3 (1991)",
  },
];

export async function fetchRandomSid(onSuccess, onError) {
  try {
    const idx = Math.floor(Math.random() * HVSC_CATALOG.length);
    const item = HVSC_CATALOG[idx];
    console.log(
      "[sid-to-skode] Fetching random SID from HVSC:",
      item.title,
      "by",
      item.author,
      "(" + item.hvscPath + ")",
    );
    return loadDemoSid(
      item.hvscPath,
      item.filename,
      item.title,
      item.author,
      onSuccess,
      onError,
      item.duration,
    );
  } catch (err) {
    console.error("[sid-to-skode] Error loading random SID:", err);
    if (onError) onError(err.message || "Failed to load random SID");
  }
}

export async function loadDemoSid(
  url,
  filename,
  title,
  author,
  onSuccess,
  onError,
  targetDuration,
) {
  try {
    let resolvedHvscPath = "";
    let sourceDesc = "🌐 HVSC Public Archive";

    let cleanUrl = (url || "").trim();
    if (cleanUrl.startsWith("/")) cleanUrl = cleanUrl.slice(1);

    if (
      cleanUrl.startsWith("MUSICIANS/") ||
      cleanUrl.startsWith("GAMES/") ||
      cleanUrl.startsWith("DEMOS/")
    ) {
      resolvedHvscPath = cleanUrl;
      sourceDesc = "🌐 HVSC Online: /" + cleanUrl;
    } else if (cleanUrl.startsWith("demos/")) {
      const match = HVSC_CATALOG.find(
        (c) => c.filename === filename || cleanUrl.endsWith(c.filename),
      );
      if (match) {
        resolvedHvscPath = match.hvscPath;
        sourceDesc = "🌐 HVSC Online: /" + match.hvscPath;
        if (!targetDuration) targetDuration = match.duration;
      } else if (
        cleanUrl.includes("commando") ||
        filename.toLowerCase().includes("commando")
      ) {
        resolvedHvscPath = "MUSICIANS/H/Hubbard_Rob/Commando.sid";
        sourceDesc = "📁 Bundled Demo: " + filename;
      }
    } else if (cleanUrl.startsWith("http")) {
      sourceDesc = "🌐 Web SID: " + cleanUrl;
    }

    // Attempt retrieval sequence:
    // 1. Direct public CORS CDN (GitHub raw / jsdelivr HVSC mirror)
    // 2. Vite local dev proxy (/hvsc/)
    // 3. Bundled Commando fallback ONLY when specifically requesting Commando
    let buf = null;
    const candidates = [];

    if (resolvedHvscPath) {
      candidates.push({
        url:
          "https://raw.githubusercontent.com/Rodartist/C64Music/master/" +
          resolvedHvscPath,
        desc: "🌐 HVSC GitHub CDN: /" + resolvedHvscPath,
      });
      candidates.push({
        url:
          "https://cdn.jsdelivr.net/gh/Rodartist/C64Music@master/" +
          resolvedHvscPath,
        desc: "🌐 HVSC jsDelivr: /" + resolvedHvscPath,
      });
      candidates.push({
        url: "/hvsc/" + resolvedHvscPath,
        desc: "🌐 HVSC Local Proxy: /" + resolvedHvscPath,
      });
    } else if (cleanUrl.startsWith("http")) {
      candidates.push({ url: cleanUrl, desc: "🌐 Direct URL: " + cleanUrl });
    }

    // Bundled fallback ONLY when Commando was explicitly requested
    if (
      cleanUrl.includes("commando") ||
      filename.toLowerCase().includes("commando")
    ) {
      const fallbackDemoUrl =
        typeof window !== "undefined"
          ? new URL("demos/commando.sid", window.location.href).href
          : "demos/commando.sid";
      candidates.push({
        url: fallbackDemoUrl,
        desc: "📁 Bundled Demo: commando.sid",
      });
    }

    let lastError = null;
    for (const cand of candidates) {
      try {
        const res = await fetch(cand.url);
        if (res.ok) {
          buf = await res.arrayBuffer();
          sourceDesc = cand.desc;
          break;
        }
      } catch (e) {
        lastError = e;
      }
    }

    if (!buf || buf.byteLength < 32) {
      throw new Error(
        "Could not load SID tune from public archive or fallback (" +
          (lastError?.message || "network error") +
          ")"
      );
    }

    const dur =
      typeof targetDuration === "number" && targetDuration > 0
        ? targetDuration
        : 210;

    const dumpText = await runSidDumpWasm(new Uint8Array(buf), filename, dur);
    if (!dumpText || dumpText.length < 100) {
      throw new Error("Could not dump SID registers for " + filename);
    }

    // Update browser URL query parameter with shareable ?url=...
    if (typeof window !== "undefined" && window.history && window.history.replaceState) {
      try {
        const paramVal = resolvedHvscPath ? "/" + resolvedHvscPath : filename;
        const newUrl = new URL(window.location.href);
        newUrl.searchParams.set("url", paramVal);
        newUrl.searchParams.delete("file");
        newUrl.searchParams.delete("sid");
        newUrl.searchParams.delete("tune");
        newUrl.searchParams.delete("id");
        window.history.replaceState(null, "", newUrl.toString());
      } catch (e) {}
    }

    if (onSuccess) {
      onSuccess(
        filename,
        dumpText,
        title || filename,
        author || "Unknown",
        sourceDesc,
        resolvedHvscPath,
      );
    }
  } catch (err) {
    console.error("[sid-to-skode] Error loading demo SID:", err);
    if (onError) onError(err.message || "Failed to load demo");
  }
}

export async function checkInitialUrlParams(callback) {
  if (typeof window === "undefined" || !window.location) return false;

  const searchParams = new URLSearchParams(window.location.search);
  let target =
    searchParams.get("url") ||
    searchParams.get("file") ||
    searchParams.get("sid") ||
    searchParams.get("tune") ||
    searchParams.get("id");

  if (!target && window.location.hash) {
    const hash = window.location.hash.replace(/^#/, "");
    if (hash.includes("=")) {
      const hashParams = new URLSearchParams(hash);
      target =
        hashParams.get("url") ||
        hashParams.get("file") ||
        hashParams.get("sid") ||
        hashParams.get("tune") ||
        hashParams.get("id");
    } else if (hash.length > 1 && !hash.startsWith("/")) {
      target = hash;
    }
  }

  // If no URL parameter specified, do NOT auto-load any song on startup
  if (!target) {
    return false;
  }

  target = decodeURIComponent(target).trim();
  console.log("[sid-to-skode] Resolving startup URL parameter:", target);

  let resolvedUrl = target;
  let filename = "tune.sid";
  let title = "Web SID";
  let author = "C64 Composer";

  // Check if target is a DeepSID URL (e.g. https://deepsid.chordian.net/?file=/MUSICIANS/W/Whittaker_David/Glider_Rider.sid)
  if (target.includes("deepsid.chordian.net") || target.includes("?file=") || target.includes("&file=")) {
    const match = target.match(/[?&]file=([^&#]+)/);
    if (match) {
      resolvedUrl = decodeURIComponent(match[1]).replace(/^\/+/, "");
    }
  } else if (target.startsWith("/")) {
    resolvedUrl = target.replace(/^\/+/, "");
  }

  // Check against HVSC catalog (by filename, title, or path)
  const normTarget = target.toLowerCase().replace(/[^a-z0-9]/g, "");
  const normResolved = resolvedUrl.toLowerCase().replace(/[^a-z0-9]/g, "");
  const match = HVSC_CATALOG.find((c) => {
    const cNormTitle = c.title.toLowerCase().replace(/[^a-z0-9]/g, "");
    const cNormFile = c.filename.toLowerCase().replace(/[^a-z0-9]/g, "");
    const cNormPath = c.hvscPath.toLowerCase().replace(/[^a-z0-9]/g, "");
    return (
      cNormTitle === normTarget ||
      cNormFile === normTarget ||
      cNormPath.includes(normResolved) ||
      normResolved.includes(cNormFile)
    );
  });

  if (match) {
    resolvedUrl = match.hvscPath;
    filename = match.filename;
    title = match.title;
    author = match.author;
  } else {
    const lastSlash = resolvedUrl.lastIndexOf("/");
    filename = lastSlash !== -1 ? resolvedUrl.slice(lastSlash + 1) : resolvedUrl;
    if (!filename.toLowerCase().endsWith(".sid")) filename += ".sid";
    title = filename.replace(/\.sid$/i, "").replace(/_/g, " ");
  }

  return loadDemoSid(
    resolvedUrl,
    filename,
    title,
    author,
    callback,
    (err) => {
      console.warn("[sid-to-skode] Failed to load URL tune:", err);
    },
  );
}

export { toggleRepl } from "./repl.mjs";

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
