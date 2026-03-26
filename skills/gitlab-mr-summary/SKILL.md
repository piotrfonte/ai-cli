---
name: gitlab-mr-summary
description: Fetch the open GitLab merge request for the current branch and update its description with a summary of all major changes. Uses chunked file-based analysis to handle large diffs.
user-invocable: true
allowed-tools: "Bash, Read, Write, Edit, Glob"
---

# GitLab MR Summary

Fetch the open merge request for the current branch, analyze all changes in manageable chunks, and update the MR description with a comprehensive summary.

Uses a `.mr-summary/` working directory to store intermediate files so large diffs never blow up the context window.

## Workflow

### Step 1: Setup

Create the working directory:

```bash
mkdir -p .mr-summary/chunks
```

Fetch MR metadata for the current branch:

```bash
glab mr view --output json
```

If this fails, stop and tell the user:
- If `glab` is not found: suggest `brew install glab`
- If no MR exists: suggest `glab mr create`
- If not authenticated: suggest `glab auth login`

Extract the **target branch** from the JSON output (`.target_branch` field). Write MR metadata (title, target branch, URL, existing description) to `.mr-summary/meta.md`.

Then fetch the diff stat and commit log, writing each to a file:

```bash
git diff <target_branch>...HEAD --stat > .mr-summary/stats.md
```

```bash
git log <target_branch>...HEAD --oneline >> .mr-summary/meta.md
```

### Step 2: Chunk the Diff

Read `.mr-summary/stats.md` to see all changed files. Group related files by directory or logical area into chunks of **10–15 files each**. For each chunk, write a scoped diff to its own file:

```bash
git diff <target_branch>...HEAD -- path/to/file1 path/to/file2 ... > .mr-summary/chunks/01-<area>.diff
```

Name chunks descriptively: `01-api-routes.diff`, `02-ui-components.diff`, `03-tests.diff`, etc.

### Step 3: Analyze Chunks

Initialize the findings file:

```markdown
# MR Findings
```

Write this to `.mr-summary/findings.md`.

Then, for **each** chunk file in `.mr-summary/chunks/` (process one at a time):

1. **Read** the chunk diff file
2. **Analyze**: what changed, why, and how significant it is
3. **Append** a section to `.mr-summary/findings.md` summarizing that chunk:

```markdown
## <Area Name>

- Change 1: what and why
- Change 2: what and why
```

**Critical**: Do NOT read multiple chunk files at once. Read one, analyze it, write findings, then move to the next. This keeps context usage low.

### Step 4: Synthesize Description

Read `.mr-summary/findings.md` and `.mr-summary/meta.md`. Compose the full MR description following this structure:

```markdown
## Summary

- Bullet point summarizing each major change (2-5 bullets)

## Changes

### <Area or purpose>

Brief explanation of what changed and why.

### <Another area>

Brief explanation.

## Testing

- Suggested verification steps or test plan
```

Write the result to `.mr-summary/description.md`.

**Guidelines:**
- Lead with the most important changes
- Be concise — a few sentences per section is usually enough
- Focus on *what* and *why*, not *how* (the diff shows the how)
- Group by purpose, not file-by-file

### Step 5: Preview and Confirm

Show the user the full contents of `.mr-summary/description.md`.

If the MR already had a description (from `meta.md`), show it too so the user can compare.

**Ask the user to confirm before making any changes. Do not proceed without explicit approval.**

### Step 6: Update MR

Only after user approval:

```bash
glab mr update --description "$(cat .mr-summary/description.md)"
```

Confirm success by showing the MR URL.

### Step 7: Cleanup

Remove the working directory:

```bash
rm -rf .mr-summary
```

If `.mr-summary` is not in the project's `.gitignore`, suggest adding it:

```
echo '.mr-summary/' >> .gitignore
```

## Rules

- Do not update the MR without showing the description and getting user confirmation first
- Do not modify the MR title unless the user explicitly asks
- Do not close, merge, rebase, or otherwise change MR state
- Always use the MR's actual target branch as the diff base — never hardcode `main` or `master`
- Process diff chunks one at a time — never load the full diff into context
- Clean up `.mr-summary/` when done
