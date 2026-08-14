---
id: W22
title: Repair Muse Glimmer's tool calls in opencode
map: model-roster-swap
labels: [wayfinder:task]
status: closed
assignee: claude
blocked_by: []
---

## Question

The destination says each roster model is **proven to carry a real coding turn**.
Muse Glimmer is the default, and in a real opencode session it emitted four
`⚙invalid` errors and a wall of raw XML instead of running four `bash` commands.
Every tool call was named `bash<|message|>`, which opencode rejects as an unknown
tool.

Is this the model, the parser, or the launcher — and can the turn be recovered?

## Resolution (2026-08-13)

**The model makes a small, recurring slip; oMLX's parser turns it into a dead
turn, twice over. The slip is not fixable here. The parser's response to it is,
and now is.** Method and artifacts:
[assets/w22-muse-toolcall](../assets/w22-muse-toolcall/).

### What the model does

Muse Glimmer's chat template frames every message as
`<|start|>assistant to=<recipient><|message|>BODY(<|eom|>|<|eot|>)` and renders a
tool call as a header naming the tool plus an ATEM XML body naming it **again**.
The model sometimes carries the header's `<name><|message|>` pattern into the
tag:

```
<atem:invoke name="bash<|message|>">
```

Everything else in the call is well-formed — the arguments parse, the header is
correct.

### Why one stray token costs the whole turn

Two defects in `omlx/adapter/muse_glimmer.py`, and the first is the galling one:

1. **`_INVOKE_RE` captures `name="([^"]+)"`** — anything but a quote — so the
   special token becomes part of the tool name. **The adapter already had the
   right name**: the header's `to=bash` parsed correctly, because
   `_RECIPIENT_RE` uses `[^\s<]+` and stops at `<`. oMLX holds a good copy and a
   corrupt copy of the same name, and the corrupt one wins.
2. **`_MuseChannelSplitter` honours every `<|message|>`**, including one arriving
   while `_channel` is already `"tool"`. The head buffer is empty at that point,
   so no `to=` is found, the channel falls to `"text"`, and the rest of the tool
   XML streams to the user as visible output — beginning at `">`, exactly where
   the tag was cut.

### The evidence is byte-exact, and it came from the session store

Ground truth was read out of opencode's own SQLite, not reconstructed from the
screenshot: session `ses_004dc7aa6ffewdWmdcDG7QUFEB`, the **first** assistant
message of the session (so no tool history), 14,293-token prompt, 264 output
tokens, `finish_reason=tool_calls`.

`parser-repro.py` feeds the reconstructed raw output to oMLX's own adapter — no
server, no model, ~0.06 s, deterministic. Before the patch it reported
`leak matches what opencode recorded: True`, matching both the four
`bash<|message|>` names and the leaked text exactly. After: four clean `bash`
calls with correct arguments and empty visible text.

### The fix

`scripts/patch-omlx-muse-toolcall.mjs` — idempotent, re-applied by `ai.sh` on
every launch, appending `+musetc` to the build string so the state-file check
restarts a stale server on its own (oMLX is an editable install, so a live
process keeps the old module).

- **Truncate the invoke name at the first `<`.** A real tool name never contains
  one, so this is lossless for well-formed output and recovers the name from
  malformed output. Deliberately **not** done by tightening the regex to
  `[^"<]+`: that makes the tag fail to match and **drops the call entirely**,
  which is worse than mis-naming it — the arguments are fine and the header
  already said which tool it was.
- **Ignore `<|message|>` while the channel is `"tool"`.** A tool body is XML and
  never contains a header, and a genuine next message always arrives after
  `<|eom|>`, `<|eot|>` or `<|start|>`, each of which closes the channel first, so
  the guard cannot swallow a real header.

Blast radius is one model: this adapter is selected for `muse_glimmer` alone, so
GLM 4.7 Flash and Ternary Bonsai never load it.

### Three findings worth carrying

- **The launcher's warn is keyed on the model, not the profile.** Muse Glimmer
  serves both bare `ai` (`profile=""`) and `--muse`, so testing the flag would
  leave **the default** silently unguarded. This is the same trap W18 caught on
  the GLM MLA fail-safe, and it was live again in the first draft of this block.
- **The defect never reproduced live.** `live-probe.py` passed every
  combination — one tool, sixteen tools, streaming, and four parallel calls under
  the exact wording that failed — so the slip is intermittent and its
  **frequency is unmeasured**. The fix is proven against the recorded output, not
  against a live trigger.
- **Nothing on this map would have caught it.** W7's serve check asserts that *a*
  tool call parses, and W14's capability suite graded code, not wire format. Both
  ran at short prompts with simple tool use; this failed on four parallel calls at
  14.3k. A serve check that proves a model *runs* does not prove its tool calls
  survive an agent turn.

### Loose end, recorded not chased

A request whose history carries a prior tool call returns a completely empty
response — `finish_reason: stop`, no content, no reasoning, no tool calls — with
`arguments` sent as a JSON string **and** as a dict. That is the multi-turn path,
i.e. every turn after the first. It may be a flaw in the probe's message shape
rather than a real defect, since real sessions do work multi-turn. It is not this
ticket's symptom and is left in the map's fog.
