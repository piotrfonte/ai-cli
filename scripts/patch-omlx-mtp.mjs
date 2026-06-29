#!/usr/bin/env node
// patch-omlx-mtp.mjs — enable per-model oMLX settings that aren't server flags.
//
// oMLX exposes some model behaviour only through per-model settings persisted in
// ~/.omlx/model_settings.json (read by the server at model load), NOT through
// `omlx serve` CLI flags. ai.sh needs two such settings on every launch:
//
//   • mtp_enabled=true for the oQ6-mtp build (ai -light) — multi-token prediction /
//     speculative decode. It's OFF by default in oMLX even when the weights carry
//     MTP heads (the `-mtp` build), so without this the build's MTP tensors are
//     dead weight. (mtp_enabled is mutually exclusive with turboquant_kv / dflash,
//     neither of which ai.sh enables, so there's no conflict.)
//   • reasoning_parser="qwen" for Qwopus — splits its <think>…</think> block into
//     a separate reasoning_content field instead of leaving raw tags inline in the
//     opencode chat.
//
// File schema (see omlx/model_settings.py): {"version":1,"models":{<id>:{…}}}.
// ModelSettings.from_dict() filters to known fields and defaults the rest, so a
// PARTIAL entry (just the keys below) is valid — we never have to write a full
// settings object, and oMLX expands defaults on its next save.
//
// Idempotent + non-destructive: merges our keys into the existing file, preserves
// every other model and key (e.g. anything set via the oMLX admin panel), and
// only rewrites when a value actually differs. Re-applied by ai.sh each launch so
// an admin-panel toggle or a fresh install can't silently disable MTP/reasoning.
//
// Usage: node patch-omlx-mtp.mjs [path/to/model_settings.json]
//        (defaults to ~/.omlx/model_settings.json)

import { readFileSync, writeFileSync, existsSync, mkdirSync } from "fs";
import { dirname } from "path";
import { homedir } from "os";

const SETTINGS_VERSION = 1;

// Model → the exact settings keys ai.sh must enforce. Keep these ids in sync with
// the model ids in ai.sh (_model_light / _model_qwopus) and opencode.json.
const DESIRED = {
  "Jundot/Qwen3.6-35B-A3B-oQ6-mtp": { mtp_enabled: true },
  "mlx-community/Qwen3.5-27B-Claude-4.6-Opus-Distilled-MLX-6bit": {
    reasoning_parser: "qwen",
  },
};

const file = process.argv[2] || `${homedir()}/.omlx/model_settings.json`;

// Load existing settings, tolerating absent/empty/corrupt files (oMLX itself
// falls back to empty on a JSON error, so a malformed file is non-fatal here too).
let data = { version: SETTINGS_VERSION, models: {} };
if (existsSync(file)) {
  try {
    const parsed = JSON.parse(readFileSync(file, "utf8"));
    if (parsed && typeof parsed === "object") {
      data = parsed;
      if (typeof data.version !== "number") data.version = SETTINGS_VERSION;
      if (!data.models || typeof data.models !== "object") data.models = {};
    }
  } catch {
    console.error(`[patch] ${file} unparseable — recreating from scratch`);
  }
}

let changed = false;
for (const [modelId, keys] of Object.entries(DESIRED)) {
  const entry = data.models[modelId] || {};
  for (const [k, v] of Object.entries(keys)) {
    if (entry[k] !== v) {
      entry[k] = v;
      changed = true;
    }
  }
  data.models[modelId] = entry;
}

if (!changed) {
  process.exit(0);
}

mkdirSync(dirname(file), { recursive: true });
writeFileSync(file, JSON.stringify(data, null, 2) + "\n");
console.error(`[patch] oMLX per-model settings applied → ${file}`);
process.exit(0);
