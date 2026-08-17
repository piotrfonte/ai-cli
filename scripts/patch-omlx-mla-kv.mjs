#!/usr/bin/env node
// patch-omlx-mla-kv.mjs — correct oMLX's MLA KV-cache estimate for GLM 4.7 Flash.
//
// oMLX sizes a model's KV cache to decide whether a prefill fits under the memory
// guard. For MLA models it has a dedicated estimator,
// estimate_mla_kv_bytes_per_token() in omlx/memory_monitor.py, which counts the
// layers that hold a main MLA cache. That count is wrong for GLM 4.7 Flash.
//
// The estimator needs a live cache list to count those layers, and for GLM 4.7 Flash
// it never gets one. `mlx_lm/models/glm4_moe_lite.py` defines NO `make_cache` method,
// so the scheduler's `if not hasattr(self.model, "make_cache")` branch leaves
// cache_list_for_tq at None (scheduler.py:11580), and the estimator returns None at
// its `if cache_list is None` check — before reaching any layer counting. The caller
// then falls back to the uniform MHA formula. Measured (.scratch W5): oMLX charges
// 47 x 20 heads x 102 head_dim x 2 x 2 B = ~374 KB/token against a real
// 47 x (512 + 64) x 2 B = 52.9 KB/token — a 7.08x over-count. The prefill guard then
// rejects a 65,536-token prompt in 5.1 s with the model alone in memory, and the
// scheduler throttles the prefill chunk from 2048 to ~900 from ~25k tokens up.
//
// TWO fixes, because two checks stand in the way:
//
//   1/2  No cache list: derive the layer count from the config instead of giving up.
//        glm4_moe_lite is uniform full attention — no layer_types, no sliding_window,
//        one MLA cache per layer — so num_hidden_layers IS the main-cache count. The
//        indexer term is carried too, so a DSA-style model reaching this branch
//        over-counts rather than under-counts; GLM 4.7 Flash has no index_head_dim,
//        so it contributes 0 there.
//   2/2  A cache list of bare KVCache: count each as that layer's main MLA cache.
//        Not needed today, because fix 1 fires first, but it closes the same hole if
//        mlx-lm later gives this model a make_cache returning bare KVCaches.
//
// Both directions of error are not equal. Over-counting costs context; under-counting
// costs a hard Metal fault instead of a clean rejection. Every fallback here rounds
// UP for that reason.
//
// oMLX's VENDORED glm_moe_dsa (omlx/patches/glm_moe_dsa/glm_moe_dsa_model.py:501)
// does define make_cache, so GLM-5.2 keeps the original CacheList path untouched.
//
// Blast radius is one model. The function returns None before this loop unless the
// config carries BOTH `kv_lora_rank` and `qk_rope_head_dim` — i.e. MLA models only.
// Verified on the roster: GLM has both (512 / 64); Ternary Bonsai (`qwen3_5`) and
// Muse Glimmer (`muse_glimmer`) have neither and never reach the patched lines.
//
// oMLX is installed editable from ~/.omlx/src, so there is exactly ONE file to
// patch — unlike the opencode-mem scripts, which patch two install locations.
//
// oMLX reads this at import, so a running server keeps the old code. ai.sh appends
// "+mlakv" to the recorded build string when this succeeds, which makes the existing
// state-file build check restart a stale server on its own.
//
// Idempotent via a sentinel; re-applied by ai.sh on every launch. Mirrors the other
// patch-*.mjs scripts.
//
// Exit codes:
//   0  patched now, or already patched
//   2  usage error
//   3  anchor not found — the upgrade moved the code. ai.sh treats this as a
//      degrade signal and caps GLM's advertised context for the session.
//
// Usage: node patch-omlx-mla-kv.mjs <omlx-src-dir>

import { readFileSync, writeFileSync, existsSync } from "fs";
import { join } from "path";

const SENTINEL = "__OMLX_MLA_KV_PATCHED__";
const TARGET = join("omlx", "memory_monitor.py");

const srcDir = process.argv[2];
if (!srcDir) {
  console.error("usage: patch-omlx-mla-kv.mjs <omlx-src-dir>");
  process.exit(2);
}

const path = join(srcDir, TARGET);
if (!existsSync(path)) {
  console.error(`[patch] skip (no such file): ${path}`);
  process.exit(3);
}

const FROM = `    if cache_list is None:
        return None

    main_cache_layers = 0
    indexer_cache_layers = 0
    try:
        for layer_cache in cache_list:
            caches = getattr(layer_cache, "caches", None)
            if caches is None:
                continue
`;

const TO = `    if cache_list is None:
        # ${SENTINEL} (1/2) — no cache list, so count layers from the config
        # rather than give up. mlx_lm's glm4_moe_lite (GLM 4.7 Flash) defines no
        # make_cache, so the scheduler passes None here and this function used to
        # return None — handing the caller the uniform MHA formula, which charges
        # ~374 KB/token against a real 52.9. That 7.08x over-count put 65,536
        # context out of reach on a 64 GB box. The model is uniform full attention
        # (no layer_types, no sliding_window), so num_hidden_layers IS the
        # main-cache count. index_head_dim is carried so a DSA-style model landing
        # here over-counts rather than under-counts; GLM 4.7 Flash has none.
        # See .scratch/model-roster-swap tickets W5 and W12.
        _layers = _cfg_get(config, "num_hidden_layers") or _cfg_get(config, "n_layer")
        if not _pos_int(_layers):
            return None
        _idx_dim = _cfg_get(config, "index_head_dim", 0) or 0
        if not _pos_int(_idx_dim):
            _idx_dim = 0
        return float(_layers * (kv_lora_rank + rope_dim + _idx_dim)) * float(dtype_size)

    main_cache_layers = 0
    indexer_cache_layers = 0
    try:
        for layer_cache in cache_list:
            caches = getattr(layer_cache, "caches", None)
            if caches is None:
                # ${SENTINEL} (2/2) — a bare KVCache IS this layer's main MLA
                # cache. Only GLM-5.2's DSA indexer wraps layer caches in a
                # CacheList. Unreachable for GLM 4.7 Flash today (1/2 fires
                # first), but it closes the same hole if mlx-lm ever gives this
                # model a make_cache that returns bare KVCaches.
                main_cache_layers += 1
                continue
`;

let src = readFileSync(path, "utf8");

if (src.includes(SENTINEL)) {
  process.exit(0);
}

const hits = src.split(FROM).length - 1;
if (hits === 0) {
  console.error(`[patch] MLA KV anchor not found in ${TARGET} — oMLX has moved it`);
  process.exit(3);
}
if (hits > 1) {
  console.error(`[patch] MLA KV anchor is ambiguous in ${TARGET} (${hits} matches) — not patching`);
  process.exit(3);
}

src = src.replace(FROM, TO);
writeFileSync(path, src);
console.error("[patch] oMLX MLA KV estimate corrected (GLM 4.7 Flash: ~374 -> 52.9 KB/token)");
process.exit(0);
