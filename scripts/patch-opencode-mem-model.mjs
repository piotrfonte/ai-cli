#!/usr/bin/env node
// patch-opencode-mem-model.mjs — let the opencode-mem summarizer model be overridden
// by the OPENCODE_MEM_MODEL env var.
//
// opencode-mem's auto-capture summarizer is pinned (in opencode-mem.jsonc) to the
// default model. But ai.sh can launch a DIFFERENT primary model (--bonsai, --muse).
// When the summarizer then asks oMLX for the default while the session runs the
// other model, oMLX can't hold both under the 48GB guard, so it ping-pongs
// (evict/reload) and 507s the session mid-turn — observed live as a 507 retry loop.
//
// Fix: have the summarizer reuse the model the session is ALREADY running. ai.sh sets
// OPENCODE_MEM_MODEL=<session model id> on launch; this patch makes config.js honor
// it, so no second model is ever loaded for summarization (continuous batching shares
// the one resident model). memoryModel is read raw (no env resolution), hence this
// one-line override.
//
// Idempotent via a sentinel; re-applied by ai.sh on every launch. Mirrors the other
// patch-opencode-mem-*.mjs scripts.
//
// Usage: node patch-opencode-mem-model.mjs <opencode-mem-package-dir>

import { readFileSync, writeFileSync, existsSync } from "fs";
import { join } from "path";

const SENTINEL = "__OMLX_MEM_MODEL_PATCHED__";

const pkgDir = process.argv[2];
if (!pkgDir) {
  console.error("usage: patch-opencode-mem-model.mjs <opencode-mem-package-dir>");
  process.exit(2);
}

const FROM = "memoryModel: fileConfig.memoryModel,";
// ${SENTINEL}
const TO = "memoryModel: process.env.OPENCODE_MEM_MODEL || fileConfig.memoryModel, // " + SENTINEL;

function patchFile(file) {
  const path = join(pkgDir, file);
  if (!existsSync(path)) return false;
  let src = readFileSync(path, "utf8");
  if (src.includes(SENTINEL)) return "already";
  if (!src.includes(FROM)) {
    console.error(`[patch] skip (anchor not found): ${file}`);
    return false;
  }
  src = src.replace(FROM, TO);
  writeFileSync(path, src);
  return true;
}

const r = patchFile("dist/config.js");
if (r === true) console.error("[patch] opencode-mem summarizer model override applied (OPENCODE_MEM_MODEL)");
process.exit(0);
