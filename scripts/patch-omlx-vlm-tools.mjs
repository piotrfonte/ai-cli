#!/usr/bin/env node
// patch-omlx-vlm-tools.mjs — deliver the request's tool list to the VLM
// engine's output parser.
//
// oMLX builds a protocol output-parser session per request, and hands it the
// tools the client declared:
//
//   omlx/scheduler.py  _get_output_parser_session()
//       create_with_tools(self.tokenizer, request.tools if request ...)
//
// `Request.tools` exists (omlx/request.py), and `engine_core.add_request()`
// accepts `tools=` and forwards it into the Request. Every link is in place
// EXCEPT the last one on the VLM lane: `VLMBatchedEngine.chat()` and
// `.stream_chat()` take `tools` as an explicit parameter — so it is not in
// **kwargs — and then call `.generate()` / `.stream_generate()` WITHOUT it.
// `stream_generate()` is what calls `add_request`, and it passes no tools.
//
// So on the VLM lane `request.tools` is always None, and every parser built
// there is blind to the tool list. Two consequences on Muse Glimmer:
//
//   - The dotted-invoke-name repair in patch-omlx-muse-toolcall.mjs is DEAD.
//     It only rewrites `webfetch.webfetch` to `webfetch` when it can prove the
//     prefix is a real tool, and with no tool list it can prove nothing. The
//     turn is lost to `⚙invalid` exactly as if the repair did not exist.
//     Measured live on 2026-08-13: `tool=webfetch.webfetch` on a patched
//     server, one wasted round trip of a three-round-trip, 2m21s answer.
//   - Parameter coercion loses its schemas, so `_coerce_param_value` falls
//     back to JSON-decoding every value. A string parameter that looks like a
//     number ("5", "true", "null") reaches the client with the wrong type.
//
// Both models on the VLM lane are affected — Muse Glimmer and Ternary Bonsai.
// The batched lane (GLM) builds its Request elsewhere and is untouched.
//
// THREE edits, all forwarding an argument that already exists:
//
//   1  chat()          -> generate(..., tools=tools)
//   2  stream_chat()   -> stream_generate(..., tools=tools)
//   3  stream_generate() -> engine.add_request(..., tools=kwargs.get("tools"))
//   4  generate()        -> self._engine.generate(..., tools=kwargs.get("tools"))
//
// 3 carries the streaming lane, 4 the non-streaming one. They are separate
// engine-core entry points and BOTH had to be fixed: with only 3 applied, a
// probe read the schema correctly when streaming and lost it when not.
//
// generate() already forwards **kwargs to stream_generate, so edit 1 reaches
// edit 3 through it. `tools` is an explicit parameter of chat/stream_chat and
// therefore never already in **kwargs, so no call can receive it twice.
//
// This is an upstream defect, not an oMLX design choice: the scheduler reads
// `request.tools` on every lane and the plumbing exists on this one. Worth
// reporting; patched here because without it a repair this repo depends on
// silently does nothing.
//
// oMLX is installed editable from ~/.omlx/src, so the patched source IS what
// runs — but only from the next server start. ai.sh appends "+vlmtools" to the
// recorded build string when this succeeds, so the state-file check restarts a
// stale server on its own.
//
// Idempotent via a sentinel; re-applied by ai.sh on every launch.
//
// Exit codes:
//   0  patched now, or already patched
//   2  usage error
//   3  anchor not found or ambiguous — the upgrade moved the code. ai.sh warns.
//
// Usage: node patch-omlx-vlm-tools.mjs <omlx-src-dir>

import { readFileSync, writeFileSync, existsSync } from "fs";
import { join } from "path";

const SENTINEL = "__OMLX_VLM_TOOLS_PATCHED__";
const VERSION = "__OMLX_VLM_TOOLS_V2__";
const TARGET = join("omlx", "engine", "vlm.py");
// The unpatched engine, kept beside it, so a later version of this script
// re-derives instead of reversing this one's edits. Refreshed whenever the
// target is found unpatched — which is what an oMLX upgrade leaves behind.
const PRISTINE = TARGET + ".orig-ai-cli";

const srcDir = process.argv[2];
if (!srcDir) {
  console.error("usage: patch-omlx-vlm-tools.mjs <omlx-src-dir>");
  process.exit(2);
}

const path = join(srcDir, TARGET);
if (!existsSync(path)) {
  console.error(`[patch] skip (no such file): ${path}`);
  process.exit(3);
}

const HEAD = `            prompt=prompt,
            max_tokens=max_tokens,
            temperature=temperature,
            top_p=top_p,
            top_k=top_k,
            min_p=min_p,
            repetition_penalty=repetition_penalty,
            presence_penalty=presence_penalty,
`;

const TAIL = `            vlm_inputs_embeds=vlm_embeds,
            vlm_extra_kwargs=vlm_kwargs,
            vlm_image_hash=image_hash,
            vlm_cache_key_start=image_cache_key_start,
            vlm_cache_key_ranges=image_cache_key_ranges,
            **kwargs,
`;

// 1 — chat() -> generate()
const FROM_CHAT = `        return await self.generate(
${HEAD}${TAIL}        )
`;
const TO_CHAT = `        return await self.generate(
${HEAD}${TAIL}            # ${SENTINEL} — the parser session is built from request.tools,
            # and without this the VLM lane never sets it. See
            # scripts/patch-omlx-vlm-tools.mjs.
            tools=tools,
        )
`;

// 2 — stream_chat() -> stream_generate()
const FROM_STREAM_CHAT = `        async for output in self.stream_generate(
${HEAD}${TAIL}        ):
`;
const TO_STREAM_CHAT = `        async for output in self.stream_generate(
${HEAD}${TAIL}            # ${SENTINEL} — see 1.
            tools=tools,
        ):
`;

// 4 — generate() -> engine_core.generate(), the non-streaming lane
const FROM_ENGINE_GENERATE = `        output = await self._engine.generate(
            prompt=prompt,
            sampling_params=sampling_params,
            vlm_inputs_embeds=vlm_inputs_embeds,
            vlm_extra_kwargs=vlm_extra_kwargs,
            vlm_image_hash=vlm_image_hash,
            vlm_cache_key_start=vlm_cache_key_start,
            vlm_cache_key_ranges=vlm_cache_key_ranges,
            **specprefill_kwargs,
        )
`;
const TO_ENGINE_GENERATE = `        output = await self._engine.generate(
            prompt=prompt,
            sampling_params=sampling_params,
            vlm_inputs_embeds=vlm_inputs_embeds,
            vlm_extra_kwargs=vlm_extra_kwargs,
            vlm_image_hash=vlm_image_hash,
            vlm_cache_key_start=vlm_cache_key_start,
            vlm_cache_key_ranges=vlm_cache_key_ranges,
            # ${SENTINEL} ${VERSION} — the NON-streaming lane, which reaches
            # add_request through engine_core.generate rather than through
            # stream_generate. Fixing only the streaming one leaves this half
            # blind: a probe then reads the parameter schema correctly when
            # streaming and loses it when not.
            tools=kwargs.get("tools"),
            **specprefill_kwargs,
        )
`;

// 3 — stream_generate() -> add_request()
const FROM_ADD = `            skip_cache_store=bool(kwargs.get("skip_cache_store", False)),
            **specprefill_kwargs,
        )
`;
const TO_ADD = `            skip_cache_store=bool(kwargs.get("skip_cache_store", False)),
            # ${SENTINEL} — engine_core.add_request already forwards this into
            # Request(tools=...), which the scheduler reads to build the output
            # parser session. Only this call site was missing it. Arrives via
            # **kwargs because stream_generate declares no \`tools\` parameter.
            tools=kwargs.get("tools"),
            **specprefill_kwargs,
        )
`;

const pristinePath = join(srcDir, PRISTINE);
let src = readFileSync(path, "utf8");

if (src.includes(VERSION)) {
  process.exit(0);
}

if (!src.includes(SENTINEL)) {
  writeFileSync(pristinePath, src);
} else if (existsSync(pristinePath)) {
  src = readFileSync(pristinePath, "utf8");
  if (src.includes(SENTINEL)) {
    console.error(`[patch] ${PRISTINE} is not a clean engine — not patching`);
    process.exit(3);
  }
} else {
  console.error(`[patch] ${TARGET} carries an older ${SENTINEL} edit and no ${PRISTINE} to fall back on.`);
  console.error(`[patch] Restore it (git -C ${srcDir} checkout -- ${TARGET}) and re-run.`);
  process.exit(3);
}

const FIXES = [
  ["chat", FROM_CHAT, TO_CHAT],
  ["stream-chat", FROM_STREAM_CHAT, TO_STREAM_CHAT],
  ["add-request", FROM_ADD, TO_ADD],
  ["engine-generate", FROM_ENGINE_GENERATE, TO_ENGINE_GENERATE],
];

for (const [label, from] of FIXES) {
  const hits = src.split(from).length - 1;
  if (hits === 0) {
    console.error(`[patch] VLM tools ${label} anchor not found in ${TARGET} — oMLX has moved it`);
    process.exit(3);
  }
  if (hits > 1) {
    console.error(`[patch] VLM tools ${label} anchor is ambiguous in ${TARGET} (${hits} matches) — not patching`);
    process.exit(3);
  }
}

for (const [, from, to] of FIXES) {
  src = src.replace(from, to);
}

writeFileSync(path, src);
console.error("[patch] oMLX VLM engine now forwards the tool list to the output parser");
process.exit(0);
