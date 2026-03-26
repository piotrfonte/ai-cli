---
name: git-review-commit
description: Review all git changes in the working tree, summarize findings, then commit with a short message and meaningful description.
user-invocable: true
allowed-tools: "Bash, Read"
---

# Git Review & Commit

Review all changes in the current git repository, then commit with a concise title and a meaningful description body.

## Workflow

### Step 1: Gather State

Run these commands in parallel:

```bash
git status
```

```bash
git diff
```

```bash
git diff --cached
```

```bash
git log --oneline -5
```

### Step 2: Review Changes

Analyze every changed file. For each change, consider:

- **Purpose** — what does this change accomplish?
- **Correctness** — any bugs, typos, or logic errors?
- **Security** — secrets, credentials, injection risks, or `.env` files that should not be committed?
- **Completeness** — TODO comments, debug logging, or half-finished work left behind?

If you find issues, **report them to the user before committing**. Do not commit code with problems unless the user acknowledges them.

### Step 3: Stage Files

- Stage all relevant changed files by name. Prefer `git add <file>...` over `git add -A`.
- **Never stage** files that look like secrets (`.env`, credentials, tokens, private keys).
- If there are untracked files, ask the user whether to include them.

### Step 4: Commit

Write the commit message using a HEREDOC:

```bash
git commit -m "$(cat <<'EOF'
<short imperative summary, ≤72 chars>

<description: what changed and why, wrapped at 72 chars>
EOF
)"
```

**Title line rules:**
- Imperative mood ("Add", "Fix", "Update", not "Added", "Fixes", "Updates")
- No period at the end
- ≤72 characters

**Description rules:**
- Blank line after the title
- Explain *what* changed and *why* — not a file-by-file list
- Wrap lines at 72 characters
- Keep it concise but informative — a few sentences is usually enough

## Rules

- Do not commit if `git status` shows no changes
- Do not add `Co-Authored-By` footers
- Do not amend previous commits — always create a new commit
- If the review surfaces real problems, stop and discuss before committing
- Match the tone/style of recent commits in the repo when possible
