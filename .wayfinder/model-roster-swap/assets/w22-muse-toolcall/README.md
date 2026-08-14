# W22 — Muse Glimmer's tool calls arrive corrupt in opencode

Method and artifacts for the defect found on 2026-08-13, after the map's
destination was declared reached.

## The symptom, as the user saw it

opencode showed four `⚙invalid` errors and a wall of XML fragments:

```
">
<atem:parameter name="command">git status</atem:parameter>
</atem:invoke>
</atem:function_calls>">
...
⚙invalid [tool=bash<|message|>, error=Model tried to call unavailable tool 'bash<|message|>'.]
```

## Ground truth

Recovered from opencode's own session store, not reconstructed from the paste:

```bash
sqlite3 ~/.local/share/opencode/opencode.db \
  "select data from part where data like '%bash<|message|>%';"
```

Session `ses_004dc7aa6ffewdWmdcDG7QUFEB`, message `msg_ffb238572001JaLx0i0m40ndB0`.
It was the **first** assistant message of the session — no tool history — with a
14,293-token prompt, 264 output tokens, `finish_reason=tool_calls`, and four
`invalid` tool parts all named `bash<|message|>`. Its reasoning part reads
*"Run commands in parallel: git status, git diff, git diff --cached,
git log --oneline -5."*

## What the model emitted

The chat template (`chat_template.jinja` in the model directory) frames every
message as `<|start|>assistant to=<recipient><|message|>BODY(<|eom|>|<|eot|>)`
and renders a tool call as a header naming the tool plus an XML body naming it
**again**:

```
<|start|>assistant to=bash<|message|><atem:function_calls>
<atem:invoke name="bash">
<atem:parameter name="command">git status</atem:parameter>
</atem:invoke>
</atem:function_calls><|eom|>
```

The model carried the header's `<name><|message|>` pattern into the tag:

```
<atem:invoke name="bash<|message|>">
```

That is a model slip and is not fixable from here.

## Why one stray token cost the whole turn

Two defects in `omlx/adapter/muse_glimmer.py`:

1. **`_INVOKE_RE`** captures `name="([^"]+)"` — anything but a quote — so the
   special token lands inside the tool name. The adapter **already had the right
   name**: the header's `to=bash` parsed correctly, because `_RECIPIENT_RE` uses
   `[^\s<]+` and stops at `<`. The corrupt copy wins over the good one.
2. **`_MuseChannelSplitter`** treats every `<|message|>` as a channel switch,
   including one arriving while `_channel` is already `"tool"`. The head buffer
   is empty there, so `_RECIPIENT_RE` finds no `to=`, the channel falls to
   `"text"`, and the rest of the XML streams to the user — starting at `">`,
   exactly where the tag was cut.

## `parser-repro.py` — the regression test

Feeds the reconstructed raw output straight to oMLX's adapter. No server, no
model, ~0.06 s, deterministic.

```bash
~/.omlx/venv/bin/python parser-repro.py
```

Before the patch it printed `leak matches what opencode recorded: True` — a
byte-exact match against the session store, both the four `bash<|message|>`
names and the leaked text. After the patch: four clean `bash` calls with correct
arguments and empty visible text.

Use the oMLX venv interpreter; the system `python3` cannot import the adapter
(`openai_harmony` is missing).

## `live-probe.py` — what did NOT reproduce it

Sends an opencode-shaped request to the running server and asserts a clean tool
call.

```bash
python3 live-probe.py --stream --many-tools --multi
```

Every combination **passed**: one tool, sixteen tools, streaming, and four
parallel calls under the exact wording that failed in the real session. So the
model's slip is **intermittent and was never triggered live**. The fix is proven
against the recorded output, not against a live trigger, and the frequency is
unmeasured.

## The fix

`scripts/patch-omlx-muse-toolcall.mjs`, idempotent, re-applied by `ai.sh` on
every launch, marking the build `+musetc4` so a stale server restarts itself.
The suffix carries a version because an older server and a newer source must not
look alike — without the bump the launcher leaves the old module running. The
script also stores the unpatched adapter as `muse_glimmer.py.orig-ai-cli` and
re-derives from it on every run, so the next version never has to reverse this
one's edits.

- Truncate the invoke name at the first `<`. A real tool name never contains
  one. **Not** by tightening the regex to `[^"<]+` — that makes the tag fail to
  match and drops the call, which is worse than mis-naming it.
- Ignore `<|message|>` while the channel is `"tool"`. A tool body is XML and
  holds no header, and a real next message always follows `<|eom|>`, `<|eot|>`
  or `<|start|>`, each of which closes the channel first.
- **Repair a dotted invoke name** (added 2026-08-13, below).
- **Read the header the same way the splitter reads it** (added 2026-08-13).
- **Accept a loose tag** — optional namespace prefix, optional quotes (below).
- **Never let a turn reach the client empty** (added 2026-08-13).

Run `parser-regress.py` for all of it; `parser-repro.py` stays as the byte-exact
record of the original symptom.

---

# The loose end was real — the empty turn, 2026-08-13

This README first recorded a "loose end, deliberately not chased": a multi-turn
request that returned a **completely empty response** — `finish_reason: stop`,
no content, no reasoning, no tool calls — and guessed it might be a flaw in the
probe. It was not. The same thing killed a real session that evening.

## The symptom

A `/init` run in `hr-client` (session `ses_003a2dc65ffeIEQaOQkHRXKhU1`) read six
files over eight turns and then stopped without writing `AGENTS.md`. The user saw
the agent simply stop.

## Ground truth, from three places at once

- **opencode DB** — the last assistant message holds only `step-start` and
  `step-finish` (`reason: "stop"`). No text part, no reasoning part, no tool
  part. All eight earlier turns hold four parts each.
- **`opencode.log`** — `loop step=9`, then `exiting loop`. opencode leaves the
  loop when a turn carries no tool call.
- **oMLX log** — `56 tokens in 13.09s (4.3 tok/s), prompt: 20366,
  finish_reason=stop`.

**That tok/s figure is the proof, and it is the only trace oMLX leaves.** Every
other turn in the session reads ~25 tok/s, because `omlx/server.py:4688` divides
by decode time only, and it takes that time from `first_token_time` — which
`omlx/server.py:4408` sets **only when `output.new_text` is not empty**. Turn 9
prints 56 / 13.09 = 4.28, the full wall clock. So no token ever left the server.
Muse decoded 56 tokens and the parser discarded every one.

## Cause

`_MuseChannelSplitter` finds the recipient with `_RECIPIENT_RE.search`, so `to=`
may sit **anywhere** in the header. `_extract_tool_calls` demanded
`assistant\s+to=`, so `to=` had to come **first**, after at least one space.

The model opened its first message with **no space** after the generation
prompt's `<|start|>assistant`, emitting `to=read<|message|>…`. The splitter read
that as a tool channel and suppressed the body; the extractor matched no message
at all. Neither half was wrong on its own. Together they lost the turn.

Two observations pin it down, with no need for the raw bytes:

1. opencode recorded **no `invalid` tool part** for turn 9, so the extractor did
   not produce a mis-named call — it produced nothing.
2. The patched parser builds a **valid** call from the same tokens, and the body
   capture is unchanged, so the body was well-formed all along. Only the message
   match failed.

## Replayed against the server

`replay-step9.py` rebuilds the exact 8-turn tool history from the session store
and asks for turn 9 again:

```
run 1: finish=tool_calls tokens=56 calls=1  -> read(src/setupProxy.js)
run 2: finish=tool_calls tokens=56 calls=1  -> read(src/setupProxy.js)
run 3: finish=tool_calls tokens=56 calls=1  -> read(src/setupProxy.js)
```

**56 tokens, three times out of three** — the same count the dead turn produced,
now yielding the call the model intended. Compare the live v1 measurement in the
session store: same model, same prompt, same 56 tokens, nothing at all.

## Frequency

Rare, and it was never going to be found by watching. Across opencode's whole
database, five assistant messages hold only `step-start`/`step-finish` with
reason `stop`. One is Muse — this one. The other four are older models from March
and April. Muse made 135 assistant turns that day: about **1 in 135**.

## The other defect the same session showed

Turn 1 was lost to a dotted invoke name: the model called `read.filePath`, and
opencode answered `Model tried to call unavailable tool`. The model's own
template teaches `to=example_tool_name.example_function_name`, so it pairs the
tool with one of its **parameter** names. Seen twice live (`read.filePath`,
`webfetch.url`). The repair uses the tool name only when the full name is unknown
**and** the segment before the first `.` is a declared tool, so a tool genuinely
named with a dot is never rewritten and an unknown prefix is never guessed at.

## It happened again the same evening, and the rail was too narrow

Session `ses_0036f0a62ffew6TjN3Tgxwc0eu`, 21:26. The user asked *"what Can you do
for me?"*, opencode showed **`Thought: 6.0s`** and nothing else. The assistant
message holds a `reasoning` part and **no text part**. The reasoning ends:

> *"Instruction says if user asks in second person … first use WebFetch tool …
> So we need to webfetch https://opencode.ai to gather information. Then answer.
> **Let's webfetch.**"*

The model reached for a tool, the tool message was suppressed, and nothing came
out of it. `153 tokens in 15.05s (25.5 tok/s)` — a normal decode rate this time,
because the reasoning *was* emitted, which is precisely why the first version of
the rail stayed silent: it asked whether **anything** had been emitted.

**Reasoning reaches the client, so it must not count as an answer.** A turn that
only thinks and then stops is exactly the turn the user sees as dead. The rail
now tracks the **text** channel alone.

Note the server was already running the header-scan fix at 21:26, so that was a
second, independent way to lose the message — the tag itself.

## Two defects trace to the model's own prompt

Read `chat_template.jinja` before blaming the model:

- `add_generation_prompt` renders exactly `'<|start|>assistant'` — **no trailing
  space**. The space before `to=` is the model's to emit, and its to forget.
- The system meta advertises `# Valid recipients: "self", "read.*",
  "webfetch.*", …`, built as `fn.name.split('.')[0] + ".*"`. That is why the
  model writes `read.filePath`: the prompt tells it the recipient is `read.*`.
- The tool-definition block states the payload "is not expected to be valid XML
  and is parsed with regular expressions". Taken at its word, the model drops the
  `atem:` prefix or swaps the quotes.

So the namespace prefix and the quotes are now optional in `_INVOKE_RE` and
`_PARAM_RE`. **Widening cannot invent a call**: tag, name and arguments must all
still be present, an unknown name is still reported as unknown, and these
patterns only ever run over tool-channel bodies — never over reasoning, never
over the visible answer.

## The rail

A turn can still fail to parse for a reason nobody has seen yet. The splitter now
keeps what it suppresses, header included, because the header carries the
recipient — the one piece of evidence naming the tool the model was reaching for.
When no tool call parses out of it the adapter **always** logs it at WARNING, and
when the turn would otherwise carry no answer it surfaces it as visible text.

Before this, oMLX recorded raw model output nowhere, so a silent turn was
undiagnosable after the fact — the tok/s arithmetic above was the only evidence,
and it says nothing about *why*. The flush follows the rule the module already
applied to an unclassified header: nothing the model produced is ever dropped.

## The repair that shipped dead — `webfetch.webfetch`, 2026-08-13

On an already-patched server (`+musetc4`), a turn still burned a round trip:

```
⚙invalid [tool=webfetch.webfetch, error=Model tried to call unavailable tool 'webfetch.webfetch'.]
```

`webfetch.webfetch` is precisely what the dotted-name repair exists to fix. It
did nothing, and the reason is not in this adapter at all.

**oMLX builds the parser session from `request.tools`** (`scheduler.py`,
`_get_output_parser_session`). `Request.tools` exists, and
`engine_core.add_request()` accepts `tools=` and forwards it into the Request.
Every link is in place except the last one on the VLM lane:
`VLMBatchedEngine.chat()` and `.stream_chat()` take `tools` as an **explicit
parameter** — so it is not in `**kwargs` — and then call `generate()` /
`stream_generate()` without it.

So `request.tools` was always `None` there, and the parser was blind to the tool
list. The repair only rewrites a name when it can prove the prefix is a declared
tool; with nothing to check against it proves nothing. It was dead code from the
moment it was written.

Two symptoms, one cause:

- the dotted-name repair never fires;
- `_coerce_param_value` loses its schemas and JSON-decodes every value, so a
  string parameter holding `5` reaches the client as the integer `5`.

`scripts/patch-omlx-vlm-tools.mjs` forwards it. **Both engine entry points
needed fixing**: the streaming lane reaches `add_request` through
`stream_generate`, the non-streaming lane through `engine_core.generate`. With
only the first patched the probe below passed streaming and failed
non-streaming — a split that no log would ever have shown.

Bonsai rides the same lane and gains the same fix. GLM is on the batched lane
and is unaffected.

### `tools-reach-parser.py` — because the failure is invisible

A blind parser logs nothing. It simply stops repairing. The one signal that
escapes is parameter coercion, so the probe declares a **string**-typed
parameter and asks the model to fill it with `5`:

```
count = '5'  (str)   schema applied     -> the tool list arrived     PASS
count = 5    (int)   JSON-decoded       -> it did not                FAIL
```

```bash
~/.omlx/venv/bin/python tools-reach-parser.py            # non-streaming
~/.omlx/venv/bin/python tools-reach-parser.py --stream   # streaming
```

**Run both.** That is how the second entry point was found.

## Reproduction is not reliable — do not wait for it

Six live attempts across two directories (`opencode run`, the same question, and
a docs question that forces the webfetch path) produced six clean answers and
**zero** rail warnings. One of them shows a correct `WebFetch` call. The failures
are rare and sampling-dependent, which is why the rail matters more than the
individual repairs: the next occurrence logs its own bytes.
