#!/usr/bin/env node

import { existsSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const cliPath = resolve(__dirname, "../build/dev/javascript/sid_to_skode/cli.mjs");

if (!existsSync(cliPath)) {
  console.error("sid2skode: Compiled JavaScript CLI not found at " + cliPath);
  console.error("Please run 'gleam build --target javascript' or 'make' first.");
  process.exit(1);
}

const { main } = await import("file://" + cliPath);
main();
