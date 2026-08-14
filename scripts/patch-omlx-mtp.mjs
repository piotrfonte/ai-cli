#!/usr/bin/env node
// patch-omlx-mtp.mjs — enable per-model oMLX settings that aren't server flags.
//
// oMLX exposes some model behaviour only through per-model settings persisted in
// ~/.omlx/model_settings.json (read by the server at model load), NOT through
// `omlx serve` CLI flags. ai.sh enforces these on every launch.
//
// THE CURRENT ROSTER PINS NO BEHAVIOUR — only a safety rail. GLM 4.7 Flash,
// Ternary Bonsai 27B and Muse Glimmer 30B each pass their serve check at their own
// defaults: all three split reasoning_content from content correctly, so none needs
// the enable_thinking pin an earlier model did, and MTP stays off even on GLM,
// which carries an MTP head, because nothing here has measured it.
//
// What DESIRED does hold is one max_context_window per model — a rail against
// clients that never read opencode.json, not a behaviour change. See the block
// above DESIRED for why the rail must not equal the declared context.
//
// The script stays wired into ai.sh regardless. It is the only place a per-model
// setting can be asserted, it re-applies our values over an oMLX admin-panel
// toggle, and it is where a measured pin lands (a reasoning-strength cap to cut
// decode cost, or a dflash drafter). With DESIRED empty it writes nothing.
//
// It does not DELETE settings for departed models. Entries left behind by an old
// roster are inert — oMLX only reads the id it resolved a request to — and this
// script's contract is to preserve every key it did not write, including anything
// set through the admin panel.
//
// The idempotency check uses sameValue() rather than `!==` so an OBJECT-valued
// setting (e.g. chat_template_kwargs) compares by content, not by reference. With
// `!==` such a value always differs and rewrites the file on every launch.
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

// Model → the exact settings keys ai.sh must enforce. Any id added here must be
// the two-level <org>/<repo> form used in ai.sh and opencode.json; expandKeys()
// below writes the directory-leaf spelling too, which is the one oMLX matches.
//
// Each model pins max_context_window to its declared opencode context PLUS one
// 4,096-token block of headroom. The two numbers do different jobs and must not be
// equal: limit.context in opencode.json is the client's BUDGET, max_context_window
// here is a SAFETY RAIL against clients that never read opencode.json at all.
//
// Setting them equal was tried and is wrong. opencode estimates tokens with its own
// tokenizer, so a prompt it believes fits can render a few tokens longer on oMLX —
// measured: a prompt built for 32,768 arrived as 32,784 and was hard-rejected at an
// exactly-mirrored pin. One block of headroom absorbs that drift while still
// stopping the gross overruns the rail exists for.
//
// Without a pin, oMLX resolves the cap from the model's native window (server.py
// get_max_context_window, priority 2) — 202,752 for GLM, 262,144 for Bonsai,
// 131,072 for Muse. So any client that does not read opencode.json (the
// opencode-mem summarizer, smart-coding, a stray script) can send a prompt far
// past what this box can prefill, and pay minutes before it fails.
//
// For GLM the pin is load-bearing, not tidiness. W12 measured a 45,072-token cold
// prefill being ADMITTED by the memory guard and then force-stopped at 20,608
// tokens against the physical Metal cap, which unloaded the model and cost ~5
// minutes. validate_context_window (server.py:1618) runs on the tokenized prompt
// BEFORE scheduling, so the pin turns that into an instant, clean HTTP 400.
//
// Numbers come from measurement, not from the roster's old flat 65,536:
//   GLM 4.7 Flash   declares 32,768 → pin 36,864. Cold prefill of 32,783 tokens
//                   costs 116 s. 40,976 also passes (266 s), but 45,072 fails hard,
//                   so the declared number keeps real margin for the hot cache and
//                   a concurrent summarizer, and the rail still sits below the last
//                   rung measured to pass. See tickets W5 and W12.
//   Ternary Bonsai  declares 65,536 → pin 69,632. W6 reached 65,536, no warnings.
//   Muse Glimmer    declares 65,536 → pin 69,632. W7 reached 65,536, no warnings.
//
// MTP stays off everywhere, and no model carries an enable_thinking pin.
//
// GLM's pin was TRIED AND MEASURED, not skipped — W19. Do not re-try it without
// reading that ticket. It works exactly as intended at the mechanical level and
// still loses: runaways went 4/12 -> 0/12, reasoning 151,688 chars -> 0, wall
// 23.0 min -> 1.9 min. But solved went 6/12 -> 4/12, and T2 (the both-spellings
// merge this very file is the archetype of) collapsed from 2 solved to 0. The
// control's two T2 passes cost 9,431 and 26,413 reasoning chars: the reasoning
// is what produced them. GLM also reached for packages that do not exist
// (lodash-es, deepmerge) only under the pin, and produced a Bash syntax error,
// a failure class the control never produced.
//
// The cure converts wasted turns into wrong answers rather than right ones. T3
// shows it exactly: P P F -> F F F, same 0 solved. So the pin buys nothing on
// the count that matters and costs a point estimate, and it is off.
//
// The lever itself is sound if a future model needs it. GLM's template honours
// the kwarg —
//   <|assistant|>{{- '</think>' if (enable_thinking is defined and not enable_thinking) else '<think>' -}}
// — and ModelSettings.enable_thinking is a DEDICATED toggle that outranks
// chat_template_kwargs (model_settings.py merge_chat_template_request_kwargs).
//
// NOTE for anyone reverting a pin here: this script never DELETES a key (see the
// header). Removing an entry from DESIRED leaves the old value live in
// model_settings.json forever. W19 had to delete enable_thinking from that file
// by hand. Check the file, not just this map.
const DESIRED = {
  "lmstudio-community/GLM-4.7-Flash-MLX-6bit": { max_context_window: 36864 },
  "prism-ml/Ternary-Bonsai-27B-mlx-2bit": { max_context_window: 69632 },
  "mlx-community/Muse-Glimmer-30B-4bit": { max_context_window: 69632 },
};

// Deep value equality for the idempotency check. Scalars alone would let `!==`
// do the work, but chat_template_kwargs is an OBJECT: `entry[k] !== v` compares
// references, is always true, and would rewrite the file on every single launch.
const sameValue = (a, b) => {
  if (a === b) return true;
  if (a === null || b === null) return false;
  if (typeof a !== "object" || typeof b !== "object") return false;
  const ak = Object.keys(a);
  const bk = Object.keys(b);
  if (ak.length !== bk.length) return false;
  return ak.every((k) => Object.prototype.hasOwnProperty.call(b, k) && sameValue(a[k], b[k]));
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
    console.error(`[patch] ${file} unparseable — its contents are ignored`);
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
      if (!sameValue(entry[k], v)) {
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
