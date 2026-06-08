#!/usr/bin/env node
// patch-smart-coding-omlx.mjs — route smart-coding-mcp embeddings to oMLX.
//
// smart-coding-mcp (v2.3.x) only embeds in-process via @huggingface/transformers
// (transformers.js + ONNX, CPU/WASM). It has no remote-endpoint option. This
// script idempotently rewrites its two embedder files so the feature-extraction
// "pipeline" is backed by oMLX's OpenAI-compatible /v1/embeddings (MLX/Metal)
// when the SMART_CODING_EMBEDDING_API_URL env var is set — and falls back to the
// original in-process path when it isn't (so an unpatched env still works).
//
// It's invoked by ai.sh on every launch, so a `brew upgrade`/`npm update` that
// reverts the global package is automatically re-patched. Idempotent via a
// sentinel marker.
//
// Usage: node patch-smart-coding-omlx.mjs <smart-coding-mcp-package-dir>

import { readFileSync, writeFileSync, existsSync } from "fs";
import { join } from "path";

const SENTINEL = "__OMLX_PATCHED__";

const pkgDir = process.argv[2];
if (!pkgDir) {
  console.error("usage: patch-smart-coding-omlx.mjs <smart-coding-mcp-package-dir>");
  process.exit(2);
}

// The oMLX-backed extractor + a pipeline shim, injected verbatim into each file.
// __omlxMakeExtractor returns null when no endpoint is configured → the shim
// then delegates to the real transformers.js pipeline (original behaviour).
const INJECT = `
// ${SENTINEL} — oMLX embedding backend (injected by ai.sh)
function __omlxMakeExtractor(modelName) {
  const url = process.env.SMART_CODING_EMBEDDING_API_URL;
  if (!url) return null;
  const apiModel = process.env.SMART_CODING_EMBEDDING_API_MODEL || modelName;
  const apiKey = process.env.SMART_CODING_EMBEDDING_API_KEY || "mlx";
  const base = url.replace(/\\/+$/, "");
  return async function (text) {
    const inputs = Array.isArray(text) ? text : [text];
    const resp = await fetch(base + "/embeddings", {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: "Bearer " + apiKey },
      body: JSON.stringify({ model: apiModel, input: inputs }),
    });
    if (!resp.ok) {
      throw new Error("oMLX embeddings failed: " + resp.status + " " + (await resp.text()));
    }
    const json = await resp.json();
    const dim = json.data[0].embedding.length;
    const flat = new Float32Array(inputs.length * dim);
    json.data.forEach((d, i) => flat.set(d.embedding, i * dim));
    // Always L2-normalize so index- and query-time vectors are unit length
    // (cosine search), regardless of whether oMLX normalized them.
    return new Tensor("float32", flat, [inputs.length, dim]).normalize(2, -1);
  };
}
async function __omlxPipeline(task, modelName, opts) {
  const ex = __omlxMakeExtractor(modelName);
  if (ex) return ex;
  return await pipeline(task, modelName, opts);
}
`;

function patchFile(file) {
  const path = join(pkgDir, file);
  if (!existsSync(path)) {
    console.error(`[patch] skip (missing): ${file}`);
    return false;
  }
  let src = readFileSync(path, "utf8");
  if (src.includes(SENTINEL)) {
    return "already";
  }

  // 1) Ensure Tensor is imported alongside pipeline/layer_norm.
  src = src.replace(
    /import\s*\{([^}]*)\}\s*from\s*(['"])@huggingface\/transformers\2/,
    (m, names, q) => {
      if (/\bTensor\b/.test(names)) return m;
      return `import {${names.replace(/\s*$/, "")}, Tensor } from ${q}@huggingface/transformers${q}`;
    }
  );

  // 2) Redirect the literal feature-extraction pipeline call sites to the shim.
  src = src.replace(/\bpipeline\((['"])feature-extraction\1/g, "__omlxPipeline($1feature-extraction$1");

  // 3) Inject the shim after the import block (after the last top-level import).
  const lastImport = src.lastIndexOf("\nimport ");
  const insertAt = src.indexOf("\n", lastImport) + 1;
  src = src.slice(0, insertAt) + INJECT + src.slice(insertAt);

  writeFileSync(path, src);
  return true;
}

let any = false;
for (const f of ["lib/embedding-worker.js", "lib/mrl-embedder.js"]) {
  const r = patchFile(f);
  if (r === true) {
    console.error(`[patch] patched ${f}`);
    any = true;
  } else if (r === "already") {
    // quiet on the common case
  }
}
if (any) console.error("[patch] smart-coding-mcp → oMLX embeddings enabled");
process.exit(0);
