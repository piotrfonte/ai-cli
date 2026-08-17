#!/usr/bin/env node
// patch-smart-coding-excludes.mjs — keep third-party trees out of the RAG index.
//
// smart-coding-mcp resolves the final exclude list in lib/config.js as
//     config.excludePatterns = [...ProjectDetector.getSmartIgnorePatterns(), ...config.json]
// which *discards* its own DEFAULT_CONFIG.excludePatterns entirely — and the detector
// only emits a language's ignore patterns when it detects that language. Meanwhile
// "py" sits unconditionally in fileExtensions. So a JavaScript repo that merely
// happens to contain a Python virtualenv gets 501 JS-only ignore patterns, none of
// them matching venv/site-packages, and indexes the entire virtualenv as if it were
// first-party source.
//
// Measured on one client repo (a React app with a stray .venv): .venv accounted for
// 133,011 of 140,703 chunks — 94.5% of the index — and a 750 MB embeddings.db. Because
// the embedder issues one HTTP request per chunk, that pinned oMLX at ~12 embeddings/s
// and >100% CPU for hours at a stretch, with no LLM even loaded.
//
// smart-coding-mcp has ~20 SMART_CODING_* env overrides but none for excludePatterns.
// This patch adds one, applied last in loadConfig() so it wins over both sources:
//
//   SMART_CODING_EXCLUDE_PATTERNS   colon-separated extra globs, appended
//   SMART_CODING_EXCLUDE_DEFAULTS   "false" to skip the built-in virtualenv set below
//
// The built-in set alone fixes the problem with zero configuration; the env var is
// the escape hatch for repo-specific noise (vendored SDKs, i18n locale dumps, …).
//
// Idempotent via a sentinel; re-applied by ai.sh on every launch so an `npm update`
// of the private copy can't silently revert it. Mirrors patch-smart-coding-omlx.mjs.
//
// Usage: node patch-smart-coding-excludes.mjs <smart-coding-mcp-package-dir>

import { readFileSync, writeFileSync, existsSync } from "fs";
import { join } from "path";

const SENTINEL = "__OMLX_SC_EXCLUDES_PATCHED__";

const pkgDir = process.argv[2];
if (!pkgDir) {
  console.error("usage: patch-smart-coding-excludes.mjs <smart-coding-mcp-package-dir>");
  process.exit(2);
}

// Python virtualenv + tool-cache trees. These are never first-party source, and the
// upstream detector only excludes them when it positively identifies a Python
// project — which is exactly the case that fails. Deliberately omits "**/env/**":
// too likely to collide with a legitimate src/env directory.
//
// IMPORTANT — these are not glob-matched. features/index-codebase.js#discoverFiles
// reduces every pattern to a bare directory name via
//     pattern.match(/\\*\\*\\/([^/*]+)\\/?\\*?\\*?$/)
// and hands the set to fdir().exclude((dirName) => set.has(dirName)) — an exact
// basename match at any depth. So a pattern only has any effect if it is literally
// "**/<name>/**" with no wildcard inside <name>. "**/*.egg-info/**" extracts nothing
// and would sit here doing silently nothing, so it is left out rather than shipped
// as a no-op. Anything added via SMART_CODING_EXCLUDE_PATTERNS is subject to the
// same rule — a file-level glob like "**/*.min.js" cannot work here.
const BUILTIN_EXCLUDES = [
  "**/.venv/**",
  "**/venv/**",
  "**/.virtualenv/**",
  "**/virtualenv/**",
  "**/site-packages/**",
  "**/dist-packages/**",
  "**/__pycache__/**",
  "**/.eggs/**",
  "**/.tox/**",
  "**/.nox/**",
  "**/.mypy_cache/**",
  "**/.pytest_cache/**",
  "**/.ruff_cache/**",
  "**/.ipynb_checkpoints/**",
];

const INJECT = `
// ${SENTINEL} — extra RAG excludes (injected by ai.sh)
const __OMLX_SC_BUILTIN_EXCLUDES = ${JSON.stringify(BUILTIN_EXCLUDES)};
function __omlxApplyExtraExcludes(config) {
  const extra = [];
  if ((process.env.SMART_CODING_EXCLUDE_DEFAULTS || "").trim().toLowerCase() !== "false") {
    extra.push(...__OMLX_SC_BUILTIN_EXCLUDES);
  }
  extra.push(
    ...(process.env.SMART_CODING_EXCLUDE_PATTERNS || "")
      .split(":")
      .map((s) => s.trim())
      .filter(Boolean)
  );
  if (extra.length === 0) return config;

  const current = Array.isArray(config.excludePatterns) ? config.excludePatterns : [];
  const seen = new Set(current);
  const merged = current.slice();
  for (const p of extra) {
    if (seen.has(p)) continue;
    seen.add(p);
    merged.push(p);
  }
  const added = merged.length - current.length;
  config.excludePatterns = merged;
  if (added > 0) {
    console.error(\`[Config] oMLX: +\${added} exclude patterns (virtualenv/third-party)\`);
  }
  return config;
}
`;

// Anchored on the tail of loadConfig(). "return config;" alone is not unique — it also
// ends getConfig() — so match the surrounding block. Applying it here, after every
// SMART_CODING_* override and after the smartIndexing merge, is what makes it win.
const ANCHOR = "\n  return config;\n}\n\nexport function getConfig() {";
const REPLACEMENT =
  "\n  __omlxApplyExtraExcludes(config);\n  return config;\n}\n\nexport function getConfig() {";

function patchFile(file) {
  const path = join(pkgDir, file);
  if (!existsSync(path)) {
    console.error(`[patch] skip (missing): ${file}`);
    return false;
  }
  let src = readFileSync(path, "utf8");
  if (src.includes(SENTINEL)) return "already";

  if (!src.includes(ANCHOR)) {
    console.error(`[patch] skip (anchor not found in ${file}) — smart-coding-mcp layout changed`);
    return false;
  }
  src = src.replace(ANCHOR, REPLACEMENT);

  const lastImport = src.lastIndexOf("\nimport ");
  const insertAt = src.indexOf("\n", lastImport) + 1;
  src = src.slice(0, insertAt) + INJECT + src.slice(insertAt);

  writeFileSync(path, src);
  return true;
}

const r = patchFile("lib/config.js");
if (r === true) console.error("[patch] smart-coding-mcp exclude patterns extended");
process.exit(0);
