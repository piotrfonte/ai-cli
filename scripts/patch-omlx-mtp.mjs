#!/usr/bin/env node
// patch-omlx-mtp.mjs — enable per-model oMLX settings that aren't server flags.
//
// oMLX exposes some model behaviour only through per-model settings persisted in
// ~/.omlx/model_settings.json (read by the server at model load), NOT through
// `omlx serve` CLI flags. ai.sh needs one such setting on every launch:
//
//   • mtp_enabled=true for the oQ6-mtp build (ai -l) — multi-token prediction /
//     speculative decode. It's OFF by default in oMLX even when the weights carry
//     MTP heads (the `-mtp` build), so without this the build's MTP tensors are
//     dead weight. (mtp_enabled is mutually exclusive with turboquant_kv / dflash,
//     neither of which ai.sh enables, so there's no conflict.)
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
// the model ids in ai.sh (_model_lite) and opencode.json.
const DESIRED = {
  "Jundot/Qwen3.6-35B-A3B-oQ6-mtp": { mtp_enabled: true },
  // Gemma 4 12B (ai -g) — force thinking OFF. Its chat template defaults to
  // off (`enable_thinking | default(false)`) and oMLX's own
  // detect_thinking_default() correctly reports False for it, but that
  // detection is NOT wired into the /v1/chat/completions path: enable_thinking
  // is only injected into the template kwargs when a thinking budget is set,
  // and the endpoint ends up thinking anyway. Measured: an unqualified chat
  // request returns 100% reasoning_content and EMPTY content, running to the
  // max_tokens cap without ever answering (verified at 400 / 600 / 2000
  // tokens). The same prompt rendered by hand and sent to /v1/completions
  // answers directly — so this is the chat endpoint's default, not the weights.
  // ms.enable_thinking takes precedence over chat_template_kwargs
  // (omlx/server.py), which makes this the one reliable place to pin it.
  "mlx-community/gemma-4-12B-it-qat-OptiQ-4bit": { enable_thinking: false },
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

// oMLX keys its settings by the id it RESOLVED the request to, which is the
// model's directory name under --model-dir — the bare leaf, not the two-level
// <namespace>/<name> id we send. EnginePool.resolve_model_id() looks the
// incoming id up in its entries, misses on "mlx-community/foo", then strips the
// text before the first "/" and retries — matching the entry "foo". So a
// settings entry keyed by the two-level id is NEVER consulted (verified live:
// enable_thinking under the two-level key had no effect; under the leaf it took
// hold). Write both spellings: the leaf is what actually matches today, and the
// two-level key is harmless insurance if oMLX ever registers namespaced ids.
const expandKeys = (id) => (id.includes("/") ? [id, id.slice(id.indexOf("/") + 1)] : [id]);

let changed = false;
for (const [modelId, keys] of Object.entries(DESIRED)) {
  for (const alias of expandKeys(modelId)) {
    const entry = data.models[alias] || {};
    for (const [k, v] of Object.entries(keys)) {
      if (entry[k] !== v) {
        entry[k] = v;
        changed = true;
      }
    }
    data.models[alias] = entry;
  }
}

if (!changed) {
  process.exit(0);
}

mkdirSync(dirname(file), { recursive: true });
writeFileSync(file, JSON.stringify(data, null, 2) + "\n");
console.error(`[patch] oMLX per-model settings applied → ${file}`);
process.exit(0);
