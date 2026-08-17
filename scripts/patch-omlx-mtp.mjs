#!/usr/bin/env node
// patch-omlx-mtp.mjs — enable per-model oMLX settings that aren't server flags.
//
// oMLX exposes some model behaviour only through per-model settings persisted in
// ~/.omlx/model_settings.json (read by the server at model load), NOT through
// `omlx serve` CLI flags. ai.sh enforces these on every launch.
//
// THE ROSTER PINS ONE BEHAVIOUR, ON ONE MODEL: Qwen3.8's reasoning_effort, at
// medium. Everything else here is a safety rail. GLM 4.7 Flash, Ternary Bonsai 27B,
// Muse Glimmer 30B and Qwen3.8 27B each pass their serve check at their own
// defaults: all four split reasoning_content from content correctly, so none needs
// the enable_thinking pin an earlier model did, and MTP stays off even on GLM,
// which carries an MTP head, because nothing here has measured it.
//
// What DESIRED also holds is one max_context_window per model — a rail against
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
//   Qwen3.8 27B     declares 65,536 → pin 69,632. NOTE the two ticket ids above are
//                   from the model-roster-swap map; this entry comes from the
//                   qwen-profile map's own W6, a different ticket.
//
// Qwen3.8's number is NOT a measured 65,536 rung — nothing has prefilled it past
// ~28.3k, and its fitted curve puts 65,536 at 614 s. It is declared to match its
// architecture twin. Qwen3.8 IS Ternary Bonsai at 4 bits: same qwen3_5, same 64
// layers, same 16 KV layers, same head_dim 256 and 4 KV heads (~64 KB/token), same
// 2,048 cache block, same 262,144 native window, and a patience ceiling of 21,127
// tokens against Bonsai's ~21,000 — within 1 %. So the KV arithmetic that drives a
// memory-guard abort is identical to Bonsai's, which reaches 65,536 with no
// warning. 614 s is a WAIT, not a failure, and it is paid only by a cold prompt
// arriving whole at that size; a session that GROWS to 65k pays the 62 s door
// charge once and then re-prefills 512–1,359 fresh tokens per turn.
//
// The second reason is the comparison itself: --qwen exists to price Bonsai's
// 2-bit quant, so the two profiles must differ in ONE variable. A different
// context cap would add a second and weaken the verdict.
//
// No model carries an enable_thinking pin.
//
// Do NOT write an mtp_enabled entry for Qwen3.8 or Bonsai. That setting is the
// NATIVE route: it attaches a head found inside the checkpoint, and neither
// checkpoint has one — both declare mtp_num_hidden_layers: 1 and carry 0 of 2180
// MTP tensors, and oMLX detects the empty head and skips attachment on its own.
//
// BUT READ THE NEXT SENTENCE BEFORE CONCLUDING THESE MODELS HAVE NO MTP HEAD.
// The head is missing from OUR ARTIFACT, not from the model. The MLX conversion
// stripped it; the GGUF of the same weights kept it (qwen35.nextn_predict_layers=1,
// blk.64.nextn.{eh_proj,enorm,hnorm,shared_head_norm}). oMLX names this exact class
// of export at omlx/utils/model_loading.py:797. So MTP is reachable on this
// architecture — through a SEPARATE setting and a separate artifact, below.
//
// QWEN3.8'S vlm_mtp GATE — the external-drafter route, under measurement (W2).
// vlm_mtp_enabled attaches an EXTERNAL drafter whose model_type is qwen3_5_mtp,
// which is a different mechanism from mtp_enabled above and is not blocked by our
// checkpoint's empty head. engine_pool.py:1971 attaches it and is FAIL-SOFT: a
// drafter that will not load logs a warning and leaves the target engine alone.
//
// THE VALUE MUST BE THE DIRECTORY LEAF. This is the opposite of the key rule below
// and getting it wrong is actively harmful, not merely inert:
//   - engine_pool.py:1980 does a plain self._entries.get(drafter_id). It never
//     calls resolve_model_id, so it gets NO strip-and-rematch.
//   - _entries is keyed by the directory leaf ("Qwen3.8-27B-MTP-4bit").
//   - On a miss, drafter_path falls back to the raw string, and
//     mlx_vlm.utils.get_model_path resolves a non-existent local path by calling
//     snapshot_download.
// So a two-level id makes the SERVER fetch 266 MB into the HF blob layout at model
// load — a SECOND COPY of the weights, which is the one thing the weight-sharing
// contract exists to prevent. Verified: discovery over --model-dir returns the leaf.
//
// The drafter pairs with our target, and that is measured rather than assumed. Its
// card pairs it with mlx-community/Qwen3.8-27B-4bit, not our lmstudio-community
// build. Three facts close the gap: validate_drafter_compatibility compares
// hidden_size ONLY and says it "intentionally uses architecture/config fields
// instead of repository names, so quantized MLX conversions ... remain accepted";
// both read 5120, vocab 248320, affine 4-bit group 64, base Qwen/Qwen3.8-27B; and
// the two tokenizer.json files are BYTE-IDENTICAL, which is the hard requirement
// oMLX's own validate_mtp_donor_pair enforces on a donor pair. Note that oMLX never
// CALLS validate_drafter_compatibility on this path — load_vlm_mtp_drafter goes
// straight to load_drafter(path, kind=None) — so that check is evidence we rely on,
// not a guard the server runs.
//
// WHY AN ENV GATE AND NOT A LITERAL. This script never DELETES a key, so an "off"
// state has to be WRITTEN as false, never removed. AI_QWEN_MTP flips exactly one
// boolean between arms, which is what a clean A/B needs, and it leaves the declined
// state explicit in the file instead of absent. vlm_mtp_draft_model is written in
// both states: it records the pairing, and it lets oMLX keep the drafter out of
// /v1/models as a helper (server.py:2552).
//
// oMLX reads this file at MODEL LOAD, and a settings change does NOT move the build
// id — so ai.sh will NOT restart a running server when this flips. Restart by hand
// (or via the W2 arm harness) or the old value stays live.
//
// DRAFT DEPTH — AI_QWEN_MTP_DEPTH, unset by default, which reproduces today's
// behaviour exactly. Note that mtp_num_draft_tokens belongs to the mtp_enabled
// route, NOT this one; the knob here is vlm_mtp_draft_block_size.
//
// Unset, oMLX takes the DRAFTER'S OWN config.json value of 3, which is 2 drafted
// tokens plus 1 bonus. W2's verification phase read exactly that: rounds=13 with
// accepted=22/26 is 13 x 2. That 3 is not a measurement — mlx-vlm derives it at
// mlx_vlm/speculative/drafters/qwen3_5_mtp/config.py:41 as mtp_num_hidden_layers + 2,
// i.e. 1 + 2, which is an export rule about the head's shape.
//
// The head is NOT limited to that depth. qwen3_5_mtp.py:459 chains the one MTP layer
// autoregressively (`while len(tokens) < block_size - 1`), so a deeper block costs
// more drafter forwards and nothing else. The mlxfast contest drafts ~3.9 tokens per
// round against our 2, with a ceiling of 8, which is why this knob now exists.
//
// FOR THIS DRAFTER CLASS THE REQUESTED DEPTH APPLIES DIRECTLY. mlx-vlm normally treats
// a requested block larger than the configured one as a ceiling and only grows into it
// when the recent prefix-hit rate clears 65 % (_effective_mtp_block_size, mtp.py:447).
// qwen3_5_mtp sets `prefer_requested_block_size = True` (qwen3_5_mtp.py:16), so
// _mtp_next_block_size returns min(requested, remaining budget) and that gate never
// runs. The number written here is the depth, not a hint.
//
// DEEPER IS NOT AUTOMATICALLY FASTER, and this is the one place to remember it: the
// llama.cpp report's whole unlock was the ACCEPTANCE THRESHOLD, and it measured
// drafting harder as slower than no speculation at all. Each extra drafted token pays
// one drafter forward (~239 MB) plus its share of the target's lm_head (~0.64 GB over
// vocab 248,320) — together about 5 % of a 16.05 GB target pass — whether or not the
// verify accepts it. The knob exists so W2 can price that; it is not a recommendation.
//
// Written as null when unset, never omitted, for the same reason vlm_mtp_enabled is
// written as false: this script does not DELETE keys, so an absent entry cannot
// express "declined" and a swept value would otherwise stay live forever.
//
// QWEN3.8'S reasoning_effort PIN — measured, and the opposite of GLM's below.
// Its chat template resolves the kwarg to one of three values and injects a
// different instruction for each: xhigh (its default) asks the model to "validate
// key assumptions, consider plausible alternatives", low asks for brevity, and
// MEDIUM INJECTS NOTHING AT ALL. Medium is the absence of the xhigh paragraph,
// not a shorter one — so this pin removes an instruction rather than adding a cap.
//
// At xhigh the model spent the whole 8,192-token budget and answered NOTHING on
// 7 of 12 runs, 6 of those 6 attempts at the two one-shot code tasks (W8). At
// medium, over two arms of 12: 12/12 and 11/12 pass@1, 12/12 pass@<=2 in both,
// ZERO runaways in 24 runs, and the wall clock fell 64.2 -> 21.8 min (min per
// solved task 12.84 -> 1.81). Both arms passed the client-vs-server contamination
// check at 0.98x and 0.99x. See qwen-profile W12.
//
// The pin is a DEFAULT, not a lock: merge_chat_template_kwargs takes
// settings.chat_template_kwargs as its lowest precedence layer, so a client that
// sends chat_template_kwargs itself still wins. Do not add forced_ct_kwargs.
//
// Proved to arrive rather than assumed: prompt_tokens on a fixed prompt read 59
// at xhigh, 47 at low and 17 at medium, and 17 with no kwarg sent once the pin was
// written. W5 found `tools` silently dropped on this same VLM lane, so a pin that
// is not proved is not measured. The probe is pin-arrival.py in W12's assets.
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

// The drafter's DIRECTORY LEAF, never its two-level id. See the block above.
const QWEN_MTP_DRAFTER = "Qwen3.8-27B-MTP-4bit";

// Truthy only for an explicit opt-in. Anything else — unset, empty, "0", "off" —
// writes vlm_mtp_enabled: false, so the declined state is recorded rather than absent.
const QWEN_MTP_ON = /^(1|true|yes|on)$/i.test(process.env.AI_QWEN_MTP ?? "");

// Draft depth. null (unset) = the drafter's own configured 3. Anything not a whole
// number of at least 2 is refused loudly rather than rounded: a depth of 1 or 0 means
// "draft nothing", which is a silently disabled MTP wearing an enabled toggle.
const parseDepth = (raw) => {
  if (raw === undefined || raw.trim() === "") return null;
  const n = Number(raw);
  if (!Number.isInteger(n) || n < 2) {
    console.error(`[patch] AI_QWEN_MTP_DEPTH=${raw} is not a whole number >= 2`);
    process.exit(1);
  }
  return n;
};
const QWEN_MTP_DEPTH = parseDepth(process.env.AI_QWEN_MTP_DEPTH);

const DESIRED = {
  "lmstudio-community/GLM-4.7-Flash-MLX-6bit": { max_context_window: 36864 },
  "prism-ml/Ternary-Bonsai-27B-mlx-2bit": { max_context_window: 69632 },
  "mlx-community/Muse-Glimmer-30B-4bit": { max_context_window: 69632 },
  "lmstudio-community/Qwen3.8-27B-MLX-4bit": {
    max_context_window: 69632,
    chat_template_kwargs: { reasoning_effort: "medium" },
    vlm_mtp_enabled: QWEN_MTP_ON,
    vlm_mtp_draft_model: QWEN_MTP_DRAFTER,
    vlm_mtp_draft_block_size: QWEN_MTP_DEPTH,
  },
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
