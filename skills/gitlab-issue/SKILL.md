---
name: gitlab-issue
description: Read a GitLab issue (description + comments), translate from German, and summarize what needs to be done.
user-invocable: true
allowed-tools: "Bash, Read, Write, Edit"
---

# GitLab Issue Reader

Fetch a GitLab issue by URL, read the full description and comment thread, translate from German to English, and produce a structured summary of what needs to be done — ready to feed into a planning prompt.

## Usage

```
/gitlab-issue https://gitlab.ooz.ch/group/project/-/issues/42
```

The argument is a GitLab issue URL. The GitLab instance is `gitlab.ooz.ch`. Assume `glab` is already authenticated — do not suggest login or auth steps.

## Workflow

### Step 1: Parse the URL

Extract the project path and issue IID from the user-provided URL.

Supported formats:
- `https://gitlab.ooz.ch/group/project/-/issues/42`
- `https://gitlab.ooz.ch/group/subgroup/project/-/issues/42`
- `https://gitlab.ooz.ch/group/project/issues/42` (legacy format)

Extract:
- **project path** — everything between `gitlab.ooz.ch/` and `/-/issues/` (e.g., `group/subgroup/project`)
- **issue IID** — the number at the end

If the URL cannot be parsed, stop and tell the user the expected format.

### Step 2: Setup

Create a working directory in `/tmp` so it never touches the current project:

```bash
mkdir -p /tmp/.gitlab-issue
```

### Step 3: Fetch Issue Data

The project path is always extracted from the URL — never inferred from the current git repository. The issue may belong to an entirely different repo than the one you are working in.

URL-encode the project path (replace `/` with `%2F`) and fetch via `glab api`:

```bash
glab api "projects/<encoded-path>/issues/<iid>" --method GET > /tmp//tmp/.gitlab-issue/issue.json
```

If this fails with a 404, the project path or issue IID may be wrong — double-check the URL.

Then fetch all comments (notes), sorted chronologically:

```bash
glab api "projects/<encoded-path>/issues/<iid>/notes?sort=asc&per_page=100" --method GET > /tmp//tmp/.gitlab-issue/notes.json
```

If the issue has more than 100 notes, paginate by checking the response headers and fetching additional pages.

### Step 4: Extract Content

Read `/tmp/.gitlab-issue/issue.json` and extract:
- Title
- Description (body)
- Labels
- Milestone (if any)
- State (open/closed)
- Author
- Created/updated dates

Read `/tmp/.gitlab-issue/notes.json` and extract each note:
- Author
- Body text
- Whether it is a system note (skip system notes like "added label", "changed milestone", etc. — only keep human comments)

Write all extracted content to `/tmp/.gitlab-issue/raw.md` in this format:

```markdown
# <Title>

**Labels:** label1, label2
**Milestone:** milestone-name
**State:** open
**Author:** username
**Created:** 2024-01-15

## Description

<full description text>

## Comments

### Comment 1 — @username (2024-01-16)

<comment body>

### Comment 2 — @username (2024-01-17)

<comment body>
```

### Step 5: Translate and Analyze

Read `/tmp/.gitlab-issue/raw.md`. The content is likely in German. Translate everything to English and produce a structured summary.

Write the summary to `/tmp/.gitlab-issue/summary.md` in this exact format:

```markdown
# Issue Summary: <translated title>

**Source:** <original issue URL>
**Status:** <open/closed> | **Labels:** <labels> | **Milestone:** <milestone or "none">

## Background

<1-3 sentences explaining the context and what problem this issue addresses>

## Requirements

- <What needs to be done, as clear actionable bullet points>
- <Each bullet should be a concrete task or acceptance criterion>
- <Derived from both the description AND the discussion>

## Constraints

- <Any technical constraints, deadlines, or limitations mentioned>
- <Omit this section if none were discussed>

## Key Decisions

- <Important decisions or clarifications made in the comments>
- <Omit this section if the comments added nothing beyond the description>

## Open Questions

- <Unresolved questions or ambiguities from the thread>
- <Omit this section if everything is clear>
```

**Guidelines:**
- Translate ALL German text to English — titles, descriptions, comments, labels
- Preserve technical terms, class names, variable names, and code snippets as-is
- Focus on actionable information — what does a developer need to know to implement this?
- If the description references other issues or MRs, note them but do not fetch them
- If comments contradict the original description, note the latest agreed-upon direction
- Keep the summary concise but complete — it should stand on its own without reading the original issue

### Step 6: Output

Display the full contents of `/tmp/.gitlab-issue/summary.md` to the user.

### Step 7: Cleanup

Remove the working directory:

```bash
rm -rf .gitlab-issue
```

## Rules

- This skill is READ-ONLY — never modify, comment on, or close the GitLab issue
- Always translate to English, even if some parts are already in English
- Skip system-generated notes (label changes, assignments, status changes) — only include human comments
- If the issue is very long (50+ comments), focus on the most recent and most substantive comments, and note that older discussion was summarized
- Always clean up `/tmp/.gitlab-issue/` when done
