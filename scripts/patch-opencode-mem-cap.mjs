#!/usr/bin/env node
// patch-opencode-mem-cap.mjs — cap the opencode-mem auto-capture summarizer input.
//
// The auto-capture summarizer (opencode-mem) is a raw OpenAI client pointed at
// the local oMLX server (memoryApiUrl), so it BYPASSES opencode.json's context
// limit. It builds its prompt in buildMarkdownContext() from the full, uncapped
// assistant text of a turn — and when captures fall behind, the message slice
// spans much of the conversation. In practice this produced ~120k-token
// summarizer prefills whose KV cache saturated oMLX's memory guard: interactive
// coding turns got throttled (a 3.8k-token turn took 340s) and concurrent
// bge-m3 embedding loads were rejected with 507 (memory ceiling exceeded). The
// agent appeared to "choke" mid-task.
//
// The plugin exposes no config knob to bound this, so we patch its compiled
// buildMarkdownContext() to cap the assembled context to a character budget
// (head + tail kept, middle elided — preserves the User Request framing and the
// Tools-Used tail while dropping a runaway AI-response middle). A summary only
// needs a few thousand chars; the default 24000 (~6k tokens) keeps the
// summarizer's KV cache tiny and out of memory contention.
//
// Budget override: OPENCODE_MEM_MAX_CONTEXT_CHARS (chars; default 24000).
//
// Invoked by ai.sh on every launch (idempotent via a sentinel marker), so an
// `npm update`/plugin re-download that reverts the package is auto-re-patched.
//
// Usage: node patch-opencode-mem-cap.mjs <opencode-mem-package-dir>

import { readFileSync, writeFileSync, existsSync } from "fs";
import { join } from "path";

const SENTINEL = "__OMLX_MEM_CAP_PATCHED__";

const pkgDir = process.argv[2];
if (!pkgDir) {
  console.error("usage: patch-opencode-mem-cap.mjs <opencode-mem-package-dir>");
  process.exit(2);
}

// Helper injected verbatim after the import block. Keeps the head (request
// framing) and tail (tool list / outcome) of the context, elides the middle.
const INJECT = `
// ${SENTINEL} — cap auto-capture summarizer input (injected by ai.sh)
const __OMLX_MEM_MAX_CHARS = (() => {
  const v = parseInt(process.env.OPENCODE_MEM_MAX_CONTEXT_CHARS || "", 10);
  return Number.isFinite(v) && v > 0 ? v : 24000;
})();
function __omlxCapContext(s) {
  if (typeof s !== "string" || s.length <= __OMLX_MEM_MAX_CHARS) return s;
  const head = Math.floor(__OMLX_MEM_MAX_CHARS * 0.55);
  const tail = __OMLX_MEM_MAX_CHARS - head;
  const dropped = s.length - __OMLX_MEM_MAX_CHARS;
  return s.slice(0, head) +
    "\\n\\n... [omlx: truncated " + dropped + " chars of summarizer context to protect oMLX memory] ...\\n\\n" +
    s.slice(s.length - tail);
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

  // 1) Wrap buildMarkdownContext's return so the assembled context is capped.
  //    (Single, unique occurrence in this file.)
  if (!src.includes("return sections.join(\"\\n\");")) {
    console.error(`[patch] skip (anchor not found): ${file}`);
    return false;
  }
  src = src.replace(
    "return sections.join(\"\\n\");",
    "return __omlxCapContext(sections.join(\"\\n\"));"
  );

  // 2) Inject the helper after the last top-level import.
  const lastImport = src.lastIndexOf("\nimport ");
  const insertAt = src.indexOf("\n", lastImport) + 1;
  src = src.slice(0, insertAt) + INJECT + src.slice(insertAt);

  writeFileSync(path, src);
  return true;
}

const r = patchFile("dist/services/auto-capture.js");
if (r === true) {
  console.error("[patch] opencode-mem summarizer input capped");
}
process.exit(0);
