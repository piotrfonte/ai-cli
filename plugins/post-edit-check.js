// post-edit-check.js — OpenCode plugin: enforce lint + typecheck after every edit.
//
// WHY: prompt-level instructions ("always run the linter") are advisory — a model,
// especially the local 35B Qwen, silently skips them. OpenCode's `tool.execute.after`
// hook is the only deterministic lever: it fires after the `edit`/`write` tool, and
// *throwing* from it pushes the error back into the agent loop, forcing the model to
// fix what's reported before it can finish the turn. This is the same plugin
// mechanism the repo already uses for `opencode-mem`.
//
// WHAT it does after each edit to a JS/TS file:
//   1. silent auto-fix     — prettier --write, then eslint --fix
//   2. re-check            — eslint (file-scoped) + tsc --noEmit (project, incremental)
//   3. block on remainder  — throw a concise, model-readable error list
//   4. capped retries      — after N consecutive throws for the same file+error set,
//                            fall back to warn-only so the model can't doom-loop
//
// It auto-detects each project's tooling and no-ops cleanly when ESLint / tsconfig /
// Prettier aren't present (so non-TS projects — and this bash-only repo — are unaffected).
//
// Config (env vars, see CLAUDE.md):
//   OPENCODE_LINT_ENABLED         (default true)
//   OPENCODE_LINT_CHECKS          (default "eslint,tsc,prettier")
//   OPENCODE_LINT_MAX_RETRIES     (default 3)
//   OPENCODE_LINT_TSC_DEBOUNCE_MS (default 8000)
//   OPENCODE_LINT_EXTENSIONS      (default ".ts,.tsx,.js,.jsx,.mjs,.cjs")

import { existsSync, readFileSync } from "node:fs";
import { dirname, join, resolve, extname, isAbsolute } from "node:path";

// ── config ───────────────────────────────────────────────────────────────────
const env = (k, d) => {
  const v = process.env[k];
  return v === undefined || v === "" ? d : v;
};
const ENABLED = env("OPENCODE_LINT_ENABLED", "true") !== "false";
const CHECKS = new Set(
  env("OPENCODE_LINT_CHECKS", "eslint,tsc,prettier")
    .split(",")
    .map((s) => s.trim().toLowerCase())
    .filter(Boolean),
);
const MAX_RETRIES = parseInt(env("OPENCODE_LINT_MAX_RETRIES", "3"), 10) || 3;
const EXTENSIONS = new Set(
  env("OPENCODE_LINT_EXTENSIONS", ".ts,.tsx,.js,.jsx,.mjs,.cjs")
    .split(",")
    .map((s) => s.trim().toLowerCase())
    .filter(Boolean),
);
const MAX_OUTPUT_CHARS = 6000; // keep the thrown message small enough to not blow context

// ── module-level session state (lives for the opencode session) ────────────────
const editedFiles = new Set(); // absolute paths edited this session (for tsc scoping)
const retryState = new Map(); // file -> { sig, count }

// ── small fs helpers ───────────────────────────────────────────────────────────
const findUp = (startDir, names) => {
  let dir = startDir;
  for (;;) {
    for (const n of names) {
      const p = join(dir, n);
      if (existsSync(p)) return { dir, path: p, name: n };
    }
    const parent = dirname(dir);
    if (parent === dir) return null;
    dir = parent;
  }
};

const readJson = (p) => {
  try {
    return JSON.parse(readFileSync(p, "utf8"));
  } catch {
    return null;
  }
};

// Resolve a CLI: prefer the project's local node_modules/.bin, else fall back to
// `npx --no-install` (never auto-install — that would be a surprising side effect).
const resolveBin = (root, bin) => {
  const local = join(root, "node_modules", ".bin", bin);
  if (existsSync(local)) return [local];
  return ["npx", "--no-install", bin];
};

const ESLINT_CONFIGS = [
  "eslint.config.js",
  "eslint.config.mjs",
  "eslint.config.cjs",
  "eslint.config.ts",
  ".eslintrc.js",
  ".eslintrc.cjs",
  ".eslintrc.json",
  ".eslintrc.yml",
  ".eslintrc.yaml",
  ".eslintrc",
];
const PRETTIER_CONFIGS = [
  ".prettierrc",
  ".prettierrc.json",
  ".prettierrc.js",
  ".prettierrc.cjs",
  ".prettierrc.mjs",
  ".prettierrc.yml",
  ".prettierrc.yaml",
  "prettier.config.js",
  "prettier.config.cjs",
  "prettier.config.mjs",
];

const hasDep = (pkg, name) =>
  !!pkg &&
  ((pkg.dependencies && pkg.dependencies[name]) ||
    (pkg.devDependencies && pkg.devDependencies[name]));

// ── the plugin ──────────────────────────────────────────────────────────────────
export const PostEditCheck = async ({ $ }) => {
  const sh = (root, argv) => $`${argv}`.cwd(root).quiet().nothrow();

  return {
    "tool.execute.after": async (input, output) => {
      if (!ENABLED) return;
      if (input.tool !== "edit" && input.tool !== "write") return;

      const filePath = input.args && (input.args.filePath || input.args.path);
      if (!filePath || typeof filePath !== "string") return;
      const file = isAbsolute(filePath) ? filePath : resolve(filePath);
      if (!EXTENSIONS.has(extname(file).toLowerCase())) return;
      if (!existsSync(file)) return; // deleted / moved — nothing to check

      // Project root = nearest package.json; bail if none (no JS/TS project here).
      const pkgHit = findUp(dirname(file), ["package.json"]);
      if (!pkgHit) return;
      const root = pkgHit.dir;
      const pkg = readJson(pkgHit.path);

      editedFiles.add(file);

      // ── detect tooling (skip cleanly if absent) ───────────────────────────────
      const eslintEnabled =
        CHECKS.has("eslint") &&
        (ESLINT_CONFIGS.some((c) => existsSync(join(root, c))) ||
          (pkg && pkg.eslintConfig) ||
          hasDep(pkg, "eslint"));

      const prettierEnabled =
        CHECKS.has("prettier") &&
        (PRETTIER_CONFIGS.some((c) => existsSync(join(root, c))) ||
          (pkg && pkg.prettier) ||
          hasDep(pkg, "prettier"));

      const tsconfigHit =
        CHECKS.has("tsc") && /\.(ts|tsx)$/.test(file)
          ? findUp(dirname(file), ["tsconfig.json"])
          : null;

      // ── 1. silent auto-fix (best-effort, never blocks) ────────────────────────
      if (prettierEnabled) {
        await sh(root, [...resolveBin(root, "prettier"), "--write", file]);
      }
      if (eslintEnabled) {
        await sh(root, [...resolveBin(root, "eslint"), "--fix", file]);
      }

      // ── 2. re-check, collect remaining blocking errors ────────────────────────
      const blocking = []; // { kind, where, msg }
      const notes = []; // non-blocking info surfaced to the agent

      if (eslintEnabled) {
        const r = await sh(root, [...resolveBin(root, "eslint"), "--format", "json", file]);
        // exit 0 = clean, 1 = lint problems, 2 = eslint crashed/misconfig.
        const parsed = (() => {
          try {
            return JSON.parse(r.stdout.toString() || "[]");
          } catch {
            return null;
          }
        })();
        if (parsed) {
          for (const res of parsed) {
            for (const m of res.messages || []) {
              if (m.severity === 2) {
                blocking.push({
                  kind: "eslint",
                  where: `${file}:${m.line || 0}:${m.column || 0}`,
                  msg: `${m.ruleId || "error"}  ${m.message}`,
                });
              }
            }
          }
        } else if (r.exitCode === 2) {
          notes.push(`eslint could not run (config error?) — skipped:\n${r.stderr.toString().slice(0, 800)}`);
        }
      }

      if (tsconfigHit) {
        // Always re-run after an edit — every edit is a new state, and any
        // time-based skip risks missing the last edit of a fast burst, which
        // would break the "never leave a fresh type error" guarantee.
        // --incremental + a cached tsBuildInfoFile keeps repeat runs cheap: only
        // files changed since the last run get re-checked.
        const tsBuildInfo = join(root, "node_modules", ".cache", "opencode-tsc.tsbuildinfo");
        const r = await sh(root, [
          ...resolveBin(root, "tsc"),
          "--noEmit",
          "--pretty",
          "false",
          "--incremental",
          "--tsBuildInfoFile",
          tsBuildInfo,
          "-p",
          tsconfigHit.path,
        ]);
        const out = r.stdout.toString() + r.stderr.toString();
        const re = /^(?:\x1b\[[0-9;]*m)*(.+?)\((\d+),(\d+)\): error (TS\d+): (.*)$/gm;
        let mm;
        let matched = 0;
        while ((mm = re.exec(out)) !== null) {
          matched++;
          const [, relPath, line, col, code, message] = mm;
          const abs = isAbsolute(relPath) ? relPath : resolve(root, relPath);
          const entry = {
            kind: "tsc",
            where: `${abs}:${line}:${col}`,
            msg: `${code}  ${message}`,
          };
          // Block only on type errors in files the agent has actually touched
          // this session (the edit + any files its change broke). Pre-existing
          // type errors in untouched files are surfaced as notes, not blockers.
          if (editedFiles.has(abs)) blocking.push(entry);
          else notes.push(`(pre-existing) ${entry.where}  ${entry.msg}`);
        }
        if (r.exitCode !== 0 && matched === 0) {
          notes.push(`tsc could not run (config error?) — skipped:\n${out.slice(0, 800)}`);
        }
      }

      // ── 3. decide: clean / block / capped-warn ────────────────────────────────
      if (blocking.length === 0) {
        retryState.delete(file);
        if (notes.length) {
          output.output =
            (output.output || "") +
            `\n\n[post-edit-check] passed. notes:\n` +
            notes.slice(0, 10).join("\n");
        }
        return;
      }

      const sig = blocking
        .map((b) => `${b.kind}|${b.where}|${b.msg}`)
        .sort()
        .join("\n");
      const prev = retryState.get(file);
      const count = prev && prev.sig === sig ? prev.count + 1 : 1;
      retryState.set(file, { sig, count });

      let report = blocking.map((b) => `  ✗ [${b.kind}] ${b.where}\n      ${b.msg}`).join("\n");
      if (notes.length) report += `\n  notes:\n` + notes.slice(0, 10).map((n) => `    - ${n}`).join("\n");
      if (report.length > MAX_OUTPUT_CHARS) report = report.slice(0, MAX_OUTPUT_CHARS) + "\n  …(truncated)";

      if (count > MAX_RETRIES) {
        // Stop blocking so the local model can't loop forever on something it
        // can't fix — surface it loudly instead and let the turn proceed.
        output.output =
          (output.output || "") +
          `\n\n[post-edit-check] ⚠ ${blocking.length} unresolved error(s) in ${file} after ` +
          `${MAX_RETRIES} attempts — NOT auto-blocking further. Please resolve manually:\n${report}`;
        return;
      }

      throw new Error(
        `Post-edit checks FAILED for ${file} (attempt ${count}/${MAX_RETRIES}). ` +
          `You must fix these before finishing — do not leave them:\n${report}`,
      );
    },
  };
};
