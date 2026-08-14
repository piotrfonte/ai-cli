# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A Bash tool (`ai.sh`) that launches a local [oMLX](https://github.com/jundot/omlx) inference
server and connects [opencode](https://opencode.ai) (the sst/opencode build) to it.

oMLX is a native Apple-Silicon server. Two properties earn it the job:

- **A two-tier KV cache** (hot RAM + cold SSD) that restores a recurring prompt prefix from
  disk instead of recomputing it. This is what makes a long agentic session affordable — the
  cold prefill is paid once per directory visit, not once per turn.
- **One process serves the LLM *and* the embedding model** (`bge-m3`), with continuous
  batching, so the memory plugin's summarizer and embeddings share the machine with the
  coding turn instead of fighting it.

opencode has persistent cross-session memory through the `opencode-mem` plugin (local
SQLite; embeddings and summarizer both on oMLX — see Memory).

Designed for Apple Silicon. Every number in this file was measured on **one M4 Max with
64 GB, on AC power with Low Power Mode off**; treat them as properties of this box, not of the
models.

**Check the power state before you believe any timing.** On battery with Low Power Mode on
(macOS enables it by itself as the battery runs down), prefill and decode both drop to about
**40%** of the figures below — measured 2026-08-13: decode 26 → ~10 tok/s, prefill ~190 → ~87
tok/s, turning a two-round-trip answer into 4m48s. The slowdown is uniform across prefill and
decode, which is what tells you it is clocks rather than code; a regression in this repo would
almost never move both by the same factor. Two commands:

```bash
pmset -g | grep powermode     # 1 = Low Power Mode on
pmset -g ps                   # 'Battery Power' vs 'AC Power'
```

## Usage

```bash
bash ai.sh              # Ternary Bonsai 27B 2-bit — the default
bash ai.sh --bonsai     # the same model, named explicitly
bash ai.sh --muse       # Muse Glimmer 30B 4-bit — the short-prompt one
bash ai.sh --glm        # GLM 4.7 Flash 6-bit — the fast one
bash ai.sh -k           # Kill the local server
bash ai.sh -h           # Show help
bash ai.sh -- --flag    # Pass args through to the frontend
source ai.sh && ai      # Source as a function
```

**`ai.sh` never downloads a model.** You download models by hand in LM Studio; the launcher
verifies and links them. See The weight-sharing contract.

**Retired flags fail loudly.** `-l`, `-g` and `--macaw` exit 1 and print the current roster.
They are never remapped to a surviving model: the old flags and this roster share no model,
so a silent substitution would run a whole session on a model you did not choose.

## The roster

Three models, and no others. Every model id is the two-level `<org>/<repo>` form — it is the
directory `ai.sh` symlinks under `--model-dir`, the id `opencode.json` declares, and the id
opencode sends.

| Profile | Model | Store | Resident | Door charge | Decode (short / 17–22k) | pass@1 | min/solved | Context |
|---|---|---|---|---|---|---|---|---|
| `ai` (`--bonsai`) | `prism-ml/Ternary-Bonsai-27B-mlx-2bit` | 7.9 GB | **8.44 GB** | 58.6 s | 38 / ~12.5 tok/s | 5/12 | 4.09 | 65,536 |
| `--muse` | `mlx-community/Muse-Glimmer-30B-4bit` | 18 GB | 18.59 GB | 64.5 s | 26 / **~11** tok/s | **9/12** | **3.46** | 65,536 |
| `--glm` | `lmstudio-community/GLM-4.7-Flash-MLX-6bit` | 23 GB | 22.89 GB | **21.8 s** | **68 / ~23** tok/s | 6/12 | 3.83 | 32,768 |

"Door charge" is the cold prefill of a ~12.8k-token agentic prompt (see Door charge vs
per-turn prefill). `pass@1` is over 12 real coding runs. `min/solved` is each model's own
wall-clock divided by the tasks it actually solved.

**Both `pass@1` and `min/solved` are short-prompt numbers, and the default holds the worst of
each.** That is not an oversight. The ranking they carry does not survive an agentic context,
where the same suite makes Bonsai the cheapest of the three per solved task — see Why the
default is Bonsai.

Resident, decode and door charge are **measured**. GLM's door charge is **computed** from its
measured ~590 tok/s — the direct measurement was 14,909 tokens in 24.93 s.

**Decode has two numbers, and the agentic one is the one you feel.** Every rate this repo
quoted before W21 was measured on a short prompt. At a 17–22k context — what an agent turn
actually holds — **all three models lose about two-thirds of it**. The ranking is unchanged,
so `--glm` is still the fast profile at any size, but a per-turn estimate built on the short
number is about **3× too optimistic**. `pass@1` and `min/solved` in this table were both
computed at ~1.5k prompts; see Capability at agentic context for what happens to them at
17.6k.

### Which profile to use

The table prices the three models. This is the rule for choosing between them.

**Stay on bare `ai`.** Bonsai is the cheapest of the three per solved task at the context an
agent turn actually holds — 2.31 min against Muse's 3.19 — it degrades least with length
(1.12× against Muse's 1.39× and GLM's 1.73×), it takes feedback best (5/12 → 8/12 with one
repair turn), and at 8.44 GB it leaves the most memory to the hot cache, the summarizer and
the OS. Switch for one of the two reasons below, and for nothing else.

**Reach for `--muse` when the prompt is short and the task is hard.** It leads 9/12 to 5/12 on
the short-prompt suite, it never ran away in 12 runs, and it is the only model that repaired a
real Bash defect when shown the failure output. It costs 2.2× the resident footprint, and it
decodes slowest on the roster — ~11 tok/s in a real agent turn, so a 500-token answer takes
about 45 s.

**Reach for `--glm` when the door charge dominates** — a fresh directory, one large cold file,
a first read. It prefills ~3× faster than anything else, and it re-uses its cache in 256-token
blocks against the others' 2048, so its per-turn re-prefill is near zero. **Do not give it work
you expect to iterate on.** It never once acted on an error message (0 of 12), and this repo's
`post-edit-check` throws errors back at the model.

Five rules apply to every profile:

- **Pay the door charge once, then stay in the session.** A new directory costs 20–65 s to the
  first token; later turns cost seconds. See Door charge vs per-turn prefill.
- **Do not switch profile inside a task.** A switch restarts the server and orphans the whole
  KV cache — one switch logged `skipped_incompatible=399 blocks (5.15 GB)`.
- **Run one opencode client per model.** A leftover session on another model makes oMLX load
  both, and two large models thrash under the memory guard. See The two-model thrash.
- **Budget the agentic decode rate, not the short one.** That is ~12.5 tok/s on the default, so
  a 500-token answer takes about 40 s.
- **Keep a cold open under ~21,000 tokens on the default, ~22,800 on `--muse`, and under
  ~32,000 on `--glm`.** Past that you wait more than two minutes for the first token, on every
  profile — switching profile is not a workaround. See Context windows.

And review Bash by hand on every profile: all three models scored 0/9 first-shot on a real
`ai.sh`-shaped defect, and `post-edit-check` lints JS/TS only.

**These rules pick on cost, memory and repair behaviour — not on a measured capability lead.**
At ~17.6k the pass@1 spread is 7 / 8 / 6 in the table's order, and every gap sits inside the
noise band, so the three models are not separable at the context this repo actually runs. Only
the short-prompt suite ranks them, and the default comes last on that one.

### Why the default is Bonsai

**Moved on 2026-08-14, by decision and not by a measured capability lead.** Say that first,
because it is the honest reading: at the context this repo runs at, no model on this roster
measurably out-codes another.

What the evidence does say, all of it from this repo's own runs:

- **At ~17.6k the three stop separating.** pass@1 is 7 / 8 / 6 (Bonsai / Muse / GLM), and Muse
  and Bonsai **tie at 8/9** on pass@≤2. Every gap sits inside the noise band.
- **Bonsai is the cheapest per solved task there** — 2.31 min against Muse's 3.19 and GLM's
  3.64 — and it degrades least from short to long (1.12× against 1.39× and 1.73×).
- **It is less than half the resident footprint**: 8.44 GB against 18.59. That margin is what
  the 8 GB hot tier, a summarizer capture and the OS all draw on.
- **It takes feedback best of the three** — 5/12 → 8/12 with one repair turn, three real
  recoveries — which is what `post-edit-check` demands of a model.

And the price, stated plainly: **at short prompts Muse still leads 9/12 to 5/12**, at 3.46 min
per solved task against Bonsai's 4.09. That is the largest measured capability gap on this
roster, and this default gives it up. It is one flag away at `--muse`.

**The metric this section used to argue still stands: minutes per solved task, not tok/s.** W18
built it to unseat GLM, whose speed hid its waste — GLM spent **18.2 of its 23.0 measured
minutes producing nothing usable**, against Muse's 5.3 of 38.1. A rate in tok/s prices only the
turns that work, because **a wasted turn is fast**. The same metric is what now favours Bonsai
at agentic length.

**W18's floor is not met, and that is recorded rather than argued away.** W18 fixed in writing
that a challenger must lead the incumbent by three tasks to take the default; Bonsai only drew
level. The default moved anyway, weighing footprint and cost per solved task at agentic length,
where capability no longer separates. Read W18 and W21 before re-opening this — and re-open it
with a measurement, not with a preference.

### Capability is measured, and it inverts the speed order

A **serve check** proves a model *runs*: `finish_reason: stop`, non-empty `content`, reasoning
split out, and a tool call that parses. It says nothing about how well the model writes code.
All three models pass it at their own defaults.

Capability was then measured directly: four multi-turn coding tasks, 3 repeats each, every run
graded by **executing** the model's own output.

| | pass@1 | with one repair turn | Runaways | Recovered from a real error |
|---|---|---|---|---|
| Muse Glimmer | **9/12** | 11/12 | **0/12** | 2 |
| GLM 4.7 Flash | 6/12 | 6/12 | 4/12 | **0 of 12** |
| Ternary Bonsai | 5/12 | 8/12 | 0/12 | **3** |

Two results matter more than the ranking:

- **GLM never once recovered from a repair turn** carrying real failure output. This repo's
  `post-edit-check` plugin throws errors back at the model, so a model that cannot act on an
  error message is weak exactly where this box needs it.
- **A runaway** — `finish_reason: length` with no answer — wasted 4 of GLM's 12 turns, spending
  the whole 8,192-token budget for nothing.

**Bonsai takes feedback best** (5/12 → 8/12, three recoveries), so reach for it when memory is
short and you expect to iterate. Its 2-bit ternary quant shows **no collapse**; its failures
are ordinary mistakes.

**Limits of this measurement, kept deliberately:** every prompt was under 4,000 tokens, so
nothing here measures capability near a full context window. A 6 → 4 swing sits inside the
suite's declared noise band. For the long-prompt result, see the next section.

### Capability at agentic context — the ranking above does not hold there

The table above is measured at ~1.5k-token prompts. Re-run at **~17.6k**, on the three tasks
that carried all of its separation (T1, T2, T4), with the same prompts and the same
execution graders:

| Model | pass@1 4k → 17.6k | pass@≤2 4k → 17.6k | min/solved 4k → 17.6k |
|---|---|---|---|
| Muse Glimmer | 9/9 → **8/9** | 9/9 → **8/9** | 2.29 → 3.19 |
| GLM 4.7 Flash | 6/9 → **6/9** | 6/9 → **7/9** | 2.10 → 3.64 |
| Ternary Bonsai | 5/9 → **7/9** | 8/9 → **8/9** | 2.07 → **2.31** |

**A 9 / 6 / 5 spread becomes 8 / 6 / 7.** Muse's four-point lead over Bonsai becomes one, and
on pass@≤2 the two **tie**. Every remaining gap sits inside the noise band, so at the context
this repo actually runs, **the three models are not separable by this suite**. Muse kept the
default at the time only because the deciding rule was fixed in writing before the run and
required a challenger to lead by three — not because it measurably led. **The default moved to
Bonsai anyway on 2026-08-14**, on footprint and cost per solved task; see Why the default is
Bonsai.

**Ternary Bonsai is the cheapest per solved task at length (2.31) and degrades least
(1.12×). GLM degrades most (1.73×)**, because prefill is paid once per visit and decode is
paid on every token.

Two cautions carried from the run. These min/solved figures are **not** comparable to the
roster table's 3.46 / 3.83 / 4.09: those come from all four tasks, and dropping T3 removes
where GLM's runaways lived, so the trimmed suite flatters GLM and Bonsai. And 9 runs over 3
tasks cannot resolve a one-task gap — the honest claim is "indistinguishable", not "equal".

**Long-range retrieval is not the weakness.** A separate probe put six unique facts at 2.6 %
to 95.3 % depth of a ~22k corpus of this repo's own source: **36 of 36**, every model, every
answer exact. Muse read a needle **21,000 tokens back** as reliably as one 1,050 tokens back,
so its 13-of-52 full-attention layers are sufficient at this size. What degrades with length
is writing and repairing code, not finding a fact.

**T3 scored 0/9 first-shot** — a real `ai.sh`-shaped Bash defect. Every model corrected the
quoting and the ordering and every model left something real: GLM kept `for f in $(ls -rt)`,
which word-splits on the spaces the contract names; Bonsai and Muse both reached for GNU
`find -printf`, which macOS does not have. Only Muse repaired it when shown the failure.
**`post-edit-check` lints JS/TS only, so nothing in this repo catches a Bash defect a model
introduces — in the one language the launcher is written in.** Review Bash by hand.

### Muse Glimmer 30B 4-bit — `--muse`

A 30B VLM whose perception encoder is ~3.63 GB of the 18.99 GB download; served here as a
coding model only.

Its KV is the cheapest of the three by a wide margin, and not for the reason a 30B suggests:
`layer_types` runs **3 `sliding_attention` : 1 `full_attention`** at `sliding_window: 2048`,
so only **13 of 52 layers** cache KV ⇒ **~13 KB/token** plus a fixed ~0.16 GB rotating term,
about **1.0 GB at 65 k**. It therefore writes nothing to the SSD tier at these sizes. The same
13 layers are the only ones that see the whole window, so long-range recall is structurally
weaker than 52 layers suggests — **though not measurably so at 22k**: a six-needle probe at
depths from 2.6 % to 95.3 % returned 12 of 12, and the needle 21,000 tokens back was as
reliable as the one inside the sliding window. 2 KV heads, head_dim 128. Native window
**131,072** — the shortest on the roster.

**Its history, honestly.** This is the same 30B removed on 2026-08-10 for prefilling at
~200 tok/s. It came back as a *different artifact* — a flat 4-bit `mlx-community` build rather
than the `Jundot` oQ4e one — and was treated as unmeasured rather than known-bad. The
measurement reproduced the old number to the second: **64.46 s** to first token on a
12,882-token prompt (second run 68.84 s). A flat 4-bit quant does not fix prefill. It was made
the default anyway, on capability per minute, with that cost known — and it held the default
until 2026-08-14, when W21's long-context result took the capability argument away and left
the cost standing.

It has **no custom Metal kernel** in oMLX and no remaining lever on its decode rate. DFlash
speculative decode was tried and lost (see Speculative decode). 26 tok/s is a fixed property
of this box — at a short prompt. In a real agent turn at 17–22k it decodes at **~11 tok/s**,
which is the rate to budget with.

#### Its output needs a parser patch — five fixes

Muse frames every message as `<|start|>assistant to=<recipient><|message|>BODY`, and renders a
tool call as that header plus an ATEM XML body naming the tool **again**.

**One design choice in oMLX makes every parse failure expensive.** A body whose recipient is
neither `self` nor `user` is **suppressed while streaming** and parsed only at finalize. So when
the parse fails, the tokens are already gone: the client gets an empty answer with
`finish_reason=stop`, opencode reads that as "no tool call" and leaves the agent loop, and the
session dies with no error anywhere. `scripts/patch-omlx-muse-toolcall.mjs` carries five fixes,
is idempotent, is re-applied every launch, and appends **`+musetc4`** to the build id so a
server running an older module restarts itself. **The suffix is versioned on purpose** — with a
flat `+musetc` an older server and a newer source look alike and the launcher leaves the old
code running. The script also stores the unpatched adapter as
`omlx/adapter/muse_glimmer.py.orig-ai-cli` and re-derives from it every run, so the next version
never has to reverse this one's edits.

| Defect | What you see | Repair |
|---|---|---|
| `<atem:invoke name="bash<|message|>">` — the header pattern repeated in the tag | `⚙invalid`, unknown tool | Truncate the name at the first `<` |
| The same stray `<|message|>` re-classifies the open tool body | A wall of `</atem:invoke>` as visible text | Ignore `<|message|>` while the channel is `"tool"` |
| `<atem:invoke name="read.filePath">` — the tool paired with one of its **parameters** | `⚙invalid`, one wasted turn | Use the segment before the first `.`, but **only** when the whole name is unknown and that segment is a declared tool |
| The header scan disagreed with the splitter | **The whole turn vanishes** | Read the header with `_RECIPIENT_RE`, as the splitter does |
| `<invoke name='bash'>` — the namespace prefix or the quotes dropped | **The whole turn vanishes** | Make both optional in `_INVOKE_RE` / `_PARAM_RE` |

**The last two are the ones that killed sessions.** `_MuseChannelSplitter` finds the recipient
with `_RECIPIENT_RE.search`, so `to=` may sit anywhere in the header; `_extract_tool_calls`
demanded `assistant\s+to=`, so `to=` had to come first, after at least one space. On 2026-08-13 a
`/init` run read six files and then stopped, because the model opened its first message with **no
space** after `<|start|>assistant`. The template confirms why: `add_generation_prompt` renders
exactly `'<|start|>assistant'`, with **no trailing space**, so that space is the model's to emit
and its to forget. Replayed against the patched adapter, the same 56 tokens yield
`read(src/setupProxy.js)` five times out of five.

**The dotted-name repair needs the tool list, and oMLX was not delivering it.** It rewrites
`webfetch.webfetch` to `webfetch` only when it can prove the prefix is a declared tool — so with
no tool list it proves nothing and does nothing. oMLX builds the parser session from
`request.tools`; `Request` carries the field and `engine_core.add_request` forwards it, but
`VLMBatchedEngine.chat`/`.stream_chat` hold `tools` as an explicit parameter and never passed it
on. **On the VLM lane it was always `None`**, so the repair was dead code and shipped that way —
seen live as `⚙invalid [tool=webfetch.webfetch]` on an already-patched server, costing one round
trip of a three-round-trip, 2m21s answer.

`scripts/patch-omlx-vlm-tools.mjs` forwards it, marking the build `+vlmtools2`. **Both engine
entry points needed it**: streaming reaches `add_request` through `stream_generate`, non-streaming
through `engine_core.generate`. With only the first fixed, `tools-reach-parser.py` passed
streaming and failed non-streaming — which is why that probe runs both. Bonsai rides the same
lane and gained the same fix; GLM is on the batched lane and is untouched. It is an upstream
defect worth reporting: the scheduler reads `request.tools` on every lane.

**A patch whose effect is invisible needs a probe of its own.** Nothing about a blind parser
shows up in a log; it just quietly stops repairing. The only outside signal is parameter
coercion, which is what `tools-reach-parser.py` reads.

**Two defects trace straight to the model's own prompt, so expect more of them.** The template
advertises `# Valid recipients: "self", "read.*", "webfetch.*", …` — built as
`fn.name.split('.')[0] + ".*"` — which is why the model writes `read.filePath`. And it states the
payload "is not expected to be valid XML and is parsed with regular expressions", which is why
the tags arrive loose. **Widening tolerance cannot invent a call**: the tag, the name and the
arguments must all still be there, an unknown name is still reported as unknown, and these
patterns only ever run over tool-channel bodies — never over reasoning or the visible answer.

**The name is truncated rather than excluded from the regex on purpose** — `[^"<]+` would make
the tag fail to match and drop the call, which is worse than mis-naming it, since the arguments
parse fine and the header already named the tool correctly.

**A rail covers the failures nobody has seen yet.** The splitter keeps what it suppresses. When
no tool call parses out of it, the adapter logs it at WARNING, and when the turn would otherwise
carry no answer it surfaces it as visible text. This matters because **oMLX records raw model
output nowhere else**: before the rail, the only trace of a lost turn was an odd `tok/s` figure in
the server log, since `first_token_time` is set only when text is actually emitted, so the log
divides by the whole wall clock. Ugly XML in the answer beats a dead session.

**Reasoning does not count as an answer, and that distinction is load-bearing.** The rail's first
version asked whether *anything* had been emitted. A turn then died anyway: the model reasoned,
ended with "Let's webfetch.", lost the tool message, and opencode showed `Thought: 6.0s` and
nothing else. Reasoning reaches the client, so counting it called that turn healthy. A turn that
only thinks and then stops is a dead turn.

Three cautions. **These model slips are intermittent and rare.** The empty turn happened once in
135 Muse turns, and the `bash<|message|>` slip never reproduced live across one tool, sixteen
tools, streaming, or four parallel calls. **The serve-check gate does not cover any of this**: it
proves a tool call *parses*, at a short prompt, with one simple tool. That is not the same as
proving tool calls survive an agent turn. And **a wasted turn is invisible in a rate** — read
`min/solved`, not `tok/s`.

Assets at `.wayfinder/model-roster-swap/assets/w22-muse-toolcall/`: `parser-regress.py` is the
full suite (no server, no model, milliseconds), `parser-repro.py` the byte-exact original
symptom, `replay-step9.py` the live replay of the dead turn from opencode's own session store.

### GLM 4.7 Flash 6-bit — `--glm`

`glm4_moe_lite`: 47 layers, hidden 2048, **64 routed experts, 4 active + 1 shared**, with MLA
attention (`kv_lora_rank` 512 + `qk_rope_head_dim` 64) ⇒ **52.9 KB/token**, ~3.3 GB at 65 k.
Native window 202,752.

**It prefills ~3× faster than anything else here**, which is what this profile buys: ~590 tok/s
against ~190. Reach for it when the door charge dominates — a large cold file, a fresh
directory — and accept that it will not act on an error message.

It carries an MTP head (`num_nextn_predict_layers: 1`) that stays **off**: nothing here has
measured it, and `mtp_enabled` is a per-model oMLX setting, not a server flag.

**It was the default until capability was measured.** Its `enable_thinking` pin was then tried
as a cure for the runaways and reverted — see Per-model settings.

Its context is capped at 32,768 for reasons that took two tickets to establish; see Context
windows.

### Ternary Bonsai 27B 2-bit — the default

A 2-bit ternary fine-tune of Qwen3.6-27B by prism-ml, `qwen3_5`. **8.44 GB resident — less
than half of `--muse`**, and the cheapest of the three per solved task at agentic length.
It has been the default since 2026-08-14; see Why the default is Bonsai.

**Unlike the default it replaced, it fills the KV cache.** Its KV is fp16 at ~64 KB/token
against Muse's ~13, so the 8 GB hot tier fills and spills to SSD where Muse's never did. That
makes `_prune_cache` and the 25 GB disk budget matter more than they did while Muse was the
default — see `_prune_cache` is load-bearing.

It is a VLM with `language_model_only: False`, so the vision tower loads either way (~0.90 GB);
served here as a coding model only. Its 64 layers run **3 linear : 1 full attention**, so only
**16 layers cache KV** — but **oMLX does not honour the card's 4-bit KV claim**
(`turboquant_kv_bits=None`), so KV is fp16 at **~64 KB/token**, ~4.0 GB at 65 k, not the ~1 GB
the card implies. Native window 262,144. It reaches its full declared window with no warning
of any kind.

Its `mtp_num_hidden_layers: 1` is **empty**: 0 of 2180 tensors carry an MTP head. oMLX detects
this and skips attachment. Do not write an `mtp_enabled` entry for it, and do not read a flat
decode rate as MTP failing to engage.

The one remaining speed lever on the roster is Bonsai's: `omlx.custom_kernels.bonsai` is a
**decode-only** kernel (`has_native()` is `False` here), so building it under
`OMLX_WITH_CUSTOM_KERNEL=1` could lift its ~38 tok/s decode. It **cannot** touch its 194 tok/s
prefill — the prefill kernel already runs its own fastest route (`impl=blocked_seq`).

## Door charge vs per-turn prefill

The vocabulary is fixed in [CONTEXT.md](CONTEXT.md). Use it — the loose words hide the whole
argument.

**Door charge**: the cold prefill paid on the **first** turn of a visit to a directory, when no
cached prefix matches. **Per-turn prefill**: what every later turn pays — the tokens outside the
cached prefix, at the model's own rate.

They are not the same number and conflating them makes a slow-prefill model look ~3× worse than
it is. Measured on Bonsai:

| | Cost |
|---|---|
| Cold 12.8k visit (door charge) | 58.6 s |
| Later turn, small tool result | 5.5 s |
| Later turn, 2k tool result | ~23 s |

The paged cache matches the growing conversation's prefix, so turn 2 re-used 12,288 cached
tokens.

**`cached_tokens` rounds down to a block, and the block size is per model — not 2048
everywhere.** This was measured on Bonsai first and written down as a general rule; it is
not one. Measured on all three at ~22k with a byte-identical prefix:

| Model | `cached_tokens` | Block | Fresh tokens re-prefilled per turn |
|---|---|---|---|
| Muse Glimmer | 20,480 | 2,048 | 1,236–1,259 |
| Ternary Bonsai | 22,528 | 2,048 | 800–823 |
| **GLM 4.7 Flash** | 21,760 / 22,016 | **256** | **9–289** |

So budget ~2k of re-prefill per turn on Muse and Bonsai, and almost none on GLM. Quoting the
2048 rule for GLM understates its cache by a factor of eight.

**The door charge is paid once per model, not once per turn — confirmed on all three.** With
a constant prefix at the head of every request, a ~22k visit cost 130.4 s cold and 26.0 s
warm on Muse, 203.8 → 23.6 s on Bonsai, 92.2 → 20.6 s on GLM. This is what makes a
long-context measurement affordable at all.

So the door charge buys a session, and it gates the **default** choice only.

### Measuring prefill

**Isolate prefill with `max_tokens: 1`.** Never infer it by subtracting decode from the log
line: oMLX builds report `tok/s` differently (end-to-end vs decode-only), so the arithmetic
silently disagrees between versions. One token of output isolates prefill on either.

Two readings that mislead, recorded so nobody repeats them:

- **The first large prefill after a model load costs about twice the steady rate** — 14,896
  tokens in 45.13 s (330 tok/s) against ~590 tok/s for every later cold prefix on GLM. Warm-up
  is a one-time cost; do not quote the first run as the rate. (It did **not** reproduce on
  Bonsai or Muse, where the first run of each size was the faster one.)
- **A prefix repeated immediately after its cold run does not hit the cache**, while still
  reporting a large `cached_tokens`. The reported hit count is not proof of a restore.

Full measured prefill, directly at `max_tokens: 1`:

| Prompt | Muse Glimmer | Ternary Bonsai | GLM 4.7 Flash |
|---|---|---|---|
| ~10k | 54.05 / 57.34 s | 47.29 / 54.86 s | ~25 s at 14.9k |
| ~12.8k | **64.46 / 68.84 s** | **66.20 s** | — |
| ~25k | 154.90 / 155.70 s | 147.52 / 151.22 s | — |
| ~33k | — | — | 116 s |
| ~41k | — | — | 266 s (throttled) |
| ~65k | 414.16 s | 443.82 s | unreachable |
| Cold model load | 4.64 s | 2.89 s | 5.5–8.9 s |
| Warm 25k restore | 3.52–3.79 s | 3.35–3.93 s | 1.0–2.0 s at 14.9k |

**Prefill scales well and starts badly.** 6.5× the tokens (10 k → 65 k) costs only 1.2× the
per-token rate. The constant factor is the whole problem, and it is what a dense forward pass
costs on this box.

**The two-tier cache works, and honestly.** A 25k prefix comes back in ~3.5 s against ~150 s
cold.

## Context windows

`opencode.json` declares **65,536 / 8,192 output** for Muse and Bonsai, and **32,768 / 8,192**
for GLM. Understanding why they differ takes three steps, each of which corrected the one
before it.

**1. It is not KV size.** All three models have cheap KV — 1.0 GB (Muse), 4.0 GB (Bonsai),
3.3 GB (GLM) at 65 k. KV was never the binding constraint on any of them.

**2. It is not memory either.** The real wall is the **prefill activation transient** against
Apple's Metal working-set cap — **51.84 GiB** on this box. (The abort limit is
`min(static, metal) − hot_cache_reservation`; the static limit is 62 GiB, so Metal binds. Note
`--memory-guard-gb` does **not** set it.) But peak RSS on every passing rung read **23–28 GB**
against that 51.84 GiB cap, so memory had headroom the whole time.

**3. It is time.** Prefill grows as `a·n + b·n²`. You wait at most **120 s** for a cold open.
Fitting the measured rungs below the throttle solves to **~32,311 tokens** at 120 s for GLM —
so 32,768 lands within **1.5 %** of the patience boundary by accident. Muse reaches only
~22,800 tokens in the same 120 s, and Bonsai — the default — about **~21,000**, interpolated
between its measured 66.20 s at 12.8k and 147.52 s at 25k rather than fitted. **The default
therefore has the tightest patience boundary of the three.**

This reason is **stable**: unlike the memory one, it does not move if a future oMLX fixes the
guard, and it applies to every profile. **No profile on this box opens a 45,000-token file in
two minutes**, so switching profile is not a workaround.

Muse and Bonsai keep a flat 65,536 anyway, because a session grows one cached turn at a time
and only a single pathological turn pays the full-window cost.

**The lever, if you ever need it:** `sudo sysctl iogpu.wired_limit_mb=57344` raises the Metal
cap. It was approved mid-investigation and then declined, because nothing on this roster
reaches the cap and it switches on `mx.set_wired_limit`, whose failure mode (oMLX #2184) needs
a reboot.

### GLM's MLA KV over-count, and the patch that fixes it

Unpatched, oMLX sizes GLM's MLA cache with the plain **MHA** formula. It logs:

```
Model info set: 47 layers (47 KVCache), 20 KV heads, 20 Q heads, 102 head_dim.
```

`102` is `hidden_size 2048 / 20 heads`. That charges `47 × 20 × 102 × 2 × 2 B` ≈ **362 KB/token
against a real 52.9** — a **7.08×** over-count, which put 65,536 out of reach and throttled the
prefill chunk from ~25k tokens up.

`scripts/patch-omlx-mla-kv.mjs` corrects it (KV at 65 k drops 23.41 GB → 3.30 GB). It is
idempotent, and it **cannot reach the other two models**: the estimator returns early unless the
config carries both `kv_lora_rank` and `qk_rope_head_dim`, which only GLM does.

Two traps worth carrying:

- **The obvious root cause was one level off.** The `.caches` loop is *unreachable*, because
  `glm4_moe_lite` defines no `make_cache`, so the estimator bails at `cache_list is None`
  first. A patch to the loop alone changes nothing.
- **Correcting the estimate did not raise the ceiling.** With KV honest, the guard *admits*
  45,072 tokens — and the prefill then force-stops against the physical Metal cap and unloads
  the model, costing ~5 minutes. Fixing the over-count removed a safety net; the
  `max_context_window` rail puts it back (45,072 → clean HTTP 400 in 1.67 s).

oMLX is an **editable** install, so the patched source *is* what runs — but only from the next
server start, because a live process already imported the old module. `ai.sh` appends `+mlakv`
to the recorded build id, so the state-file check restarts a stale server on its own.

**Fail-safe.** If the patch anchor is gone (an oMLX upgrade moved the code), `ai.sh` caps GLM at
**24,576** for that session only, through the `OPENCODE_CONFIG_CONTENT` overlay, and warns. It
keys on the profile **name**, not on a `"default"` sentinel — a sentinel that moves with the
default silently points the guard at the wrong model. The 2026-08-14 move of the default from
Muse to Bonsai is the case that design was written against, and the guard stayed on GLM through
it without an edit.

### oMLX under-prices the prefill peak it admits

`_admission_estimate` charges the transient of a **floor-size** chunk (256 tokens) while prefill
*starts* at `prefill_step_size` (2048) and shrinks only once the throttle engages. On a cold
server, where no floor-size sample exists, admission uses the throttled steady state — a *lower*
bound on the peak — as if it were an upper bound. It quoted `KV+SDPA 1.55 GB` against >14 GB
real.

**Reported, not patched**, because the repo already carries one oMLX source patch and the
`max_context_window` rail already turns the five-minute abort into an instant HTTP 400. The
written report is at
`.wayfinder/model-roster-swap/assets/w17-prefill-headroom/upstream-report.md`.

## The weight-sharing contract

**One copy of every weight file on disk.** This is the most surprising thing about the setup and
the easiest to break by accident.

- **LM Studio owns the store**, at `~/.cache/huggingface/hub/<org>/<repo>` — flat directories,
  **not** Hugging Face's `models--org--repo/snapshots/<sha>/` layout.
- **You download models by hand in LM Studio.** `ai.sh` has no download path at all.
- **oMLX reaches the same bytes by symlink**, from `~/.omlx/models/<org>/<repo>`.

`_ensure_model` is a verifier. It fails loudly, by repo id, when:

- the weights are absent (no `*.safetensors` under the store path);
- LM Studio is **still fetching** them (`downloading_*` or `*.part` present) — a half-fetched
  model must fail exactly like an absent one, because the shards that landed would otherwise
  load as a truncated model, which oMLX reports as a *model* error rather than a missing
  download;
- a **real directory** sits where the symlink belongs — that is a second copy of the weights,
  the one thing this design exists to prevent. It is reported, never overwritten.

`_prune_stale_model_links` removes links whose target is gone. oMLX skips a dangling link in
silence, so this is tidiness rather than correctness — it keeps `--model-dir` an honest list of
what this box can serve.

**The symlink is not what grants visibility.** oMLX also scans the HF cache on its own
(`huggingface.hf_cache_enabled`). The link makes `--model-dir` *authoritative*, so the linked
copy wins the duplicate tie-break, and it gives `_ensure_model` a path to verify.

**Do not repoint `OMLX_MODEL_DIR` at the store instead.** `bge-m3` lives under `--model-dir` and
would be stranded.

**Sharing is one-directional for Muse Glimmer.** LM Studio's MLX runtime carries **mlx_vlm
0.6.5**, which has no `muse_glimmer` module; upstream needs 0.6.12, and oMLX serves the model
only by **vendoring** its own implementation
(`omlx/patches/mlx_vlm_muse_glimmer_compat`). So one copy on disk, but only oMLX reads it.
Updating or reinstalling the LM Studio **app** changes nothing here — a fresh 0.4.21 install
still ships `mlx-llm 1.11.0` carrying mlx_vlm 0.6.5. Only a **backend** release moves it.

**Indexing does not predict loading.** LM Studio indexed the Muse Glimmer copy perfectly and
still could not run it. Every claim that a model works in LM Studio needs a real load test.

## opencode configuration — `opencode.json`

Symlinked to `~/.config/opencode/opencode.json`. Two providers matter.

### Provider `mlx` — the local oMLX endpoint

Port 10081, OpenAI-compatible, declaring all three roster models with their context and output
limits and a 600 s timeout. Every row sets `"temperature": false`, so opencode omits the option
and oMLX falls back to each model's own `generation_config.json`.

**Do not delete these entries.** `mlx` is a custom `@ai-sdk/openai-compatible` provider with no
models.dev entry, so `-m mlx/<id>` only resolves while they exist — and that flag is how `ai.sh`
pins the local model.

**oMLX does not honour `do_sample`.** All three models sampled, including Muse, whose
`generation_config.json` sets it false, and Bonsai, which ships no such file. Never infer
determinism from a config — probe it.

### Provider `lmstudio` — the cross-runtime A/B

Declares the two models LM Studio can actually run, so the same weights can be compared across
both runtimes. Nothing in this repo drives it; it is used by hand.

Three facts it took two tickets to establish:

- **`whitelist` is required.** `lmstudio` is a **built-in models.dev provider**, so a `models`
  block *extends* its roster rather than replacing it — without the whitelist the picker lists
  three phantom models this box does not hold.
- **GLM needs `options.stop`.** LM Studio honours only the single `eos_token` in
  `tokenizer_config.json` and ignores the other two ids `config.json` declares (`<|user|>`
  154827, `<|observation|>` 154829). GLM ends its turns with `<|user|>`, so nothing stops it: it
  answers correctly and then fabricates a dialogue to the cap — 8191 tokens in 291.89 s. One
  added stop list turns that into 509 tokens in 14.02 s. **The fault is the runtime, not the
  model** — oMLX serves these same weights correctly.
- **A model's `options` object is spread verbatim into the request body.** That is a general
  lever: any body parameter the endpoint understands can be declared per model.

**`limit.context` never reaches LM Studio.** It is a client budget only; LM Studio fixes context
at **load** time. Load with an explicit `lms load zai-org/glm-4.7-flash --context-length 32768`,
or every agentic turn fails in two seconds.

### The top-level `model` is not a local model

`"model"` is what a **bare `opencode`** gets in any directory. `ai.sh` always passes
`-m mlx/<id>`, and a CLI flag beats the config default, so the roster is unaffected by whatever
this key names.

It currently names `zai/glm-5.2` (an uncommitted working-tree change; `HEAD` has
`vercel/alibaba/qwen3.8-max`). Note that `~/.local/share/opencode/auth.json` holds credentials
for `anthropic`, `vercel` and `openrouter` only — so that default needs its own
`opencode auth login` before a bare `opencode` session will run.

`disabled_providers` is `["opencode", "gitlab"]`. `gitlab` is hidden because a `GITLAB_TOKEN` in
the environment makes opencode auto-register 23 `duo-chat-*` models that crowd the picker.

The top-level `permission.task: "ask"` makes opencode prompt before the primary model delegates
to **any** subagent. It outlived the `@advisor` subagent it was written for: it is a general gate
on the `task` tool, so it still stops the local model spawning work you did not ask for. Keep it.

## Per-model oMLX settings — `~/.omlx/model_settings.json`

Some oMLX behaviour is reachable only through per-model settings persisted in
`$OMLX_BASE_DIR/model_settings.json`, **not** through `omlx serve` flags. `ai.sh` re-applies
`scripts/patch-omlx-mtp.mjs` on every launch. oMLX reads the file at **model load**, so a change
needs a server restart (the model-switch restart covers the usual case).

**Settings must be keyed by the model's *directory leaf*, not the two-level id.** oMLX resolves
a request by stripping everything before the first `/` and re-matching, and keys settings
against the result. An entry under the two-level id alone is **silently never consulted**. The
patch writes **both** spellings for every model.

**The roster pins no behaviour.** No `enable_thinking`, no `mtp_enabled`, no reasoning-strength
cap. All three models split `reasoning_content` from `content` correctly at their own defaults.

**It does pin one safety rail per model:** `max_context_window` = the declared opencode context
**plus one 4,096-token block**.

| Model | `limit.context` (budget) | `max_context_window` (rail) |
|---|---|---|
| GLM 4.7 Flash | 32,768 | 36,864 |
| Ternary Bonsai | 65,536 | 69,632 |
| Muse Glimmer | 65,536 | 69,632 |

The two numbers do different jobs and **must not be equal**. `limit.context` is the client's
budget; `max_context_window` is a rail against clients that never read `opencode.json` at all —
the memory summarizer, smart-coding, a stray script. Without it oMLX resolves the cap from the
model's native window (202,752 / 262,144 / 131,072), so such a client can send a prompt far past
what this box can prefill and pay minutes before it fails. Mirroring them exactly was tried and
is wrong: opencode estimates tokens with its own tokenizer, so a prompt built for 32,768 arrived
as 32,784 and was hard-rejected. One block of headroom absorbs that drift.

### Two traps in this file

- **The patch never DELETES a key.** Removing an entry from `DESIRED` leaves the old value live
  in `model_settings.json` forever. Reverting a pin means editing that file by hand. The live
  file still carries inert entries for departed models (`Qwen3.6-35B-A3B-oQ6-mtp`,
  `gemma-4-12B-it-qat-OptiQ-4bit`) for exactly this reason — harmless, since oMLX only reads the
  id it resolved a request to, but check the file, not just the script.
- **The idempotency check uses deep value equality**, not `!==`. An object-valued setting (e.g.
  `chat_template_kwargs`) compares by reference under `!==`, always differs, and rewrites the
  file on every launch.

### GLM's thinking pin was tried and reverted — do not re-open it

The one pin this roster had a measured reason to try. Pinning `enable_thinking: false` on GLM
worked perfectly at the mechanical level: runaways **4/12 → 0/12**, reasoning 151,688 chars →
**0**, wall **23.0 → 1.9 minutes** on a twelfth of the tokens.

And solved fell **6/12 → 4/12**. GLM's reasoning is what produces its correct answers — the
control's two passes on the hardest task cost 9,431 and 26,413 reasoning chars. Pinned, GLM
instead imported packages that do not exist (`lodash-es`, `deepmerge`, zero times in the
control) and emitted Bash that fails `bash -n`.

**The cure converts wasted turns into wrong answers, not right ones.** It is off, now by
measurement rather than by default. Do not re-add it without new evidence.

A related finding: **a runaway reports `reasoning_content` empty**, because oMLX splits the two
only at the closing tag. So a turn that hits the output cap mid-reason looks like a turn that
never reasoned.

### Serve-check gate

Every serve check must assert **`finish_reason: stop` and non-empty `content`, with `max_tokens`
at 4096 or above** — and measure at **8192**, which is what `opencode.json` actually grants.

The floor is not arbitrary. At a short cap a model returns its whole reasoning inline in
`content` with **no `reasoning_content` key**, so a bare non-empty test passes a dead answer.
1024 passed on a trivial prompt and then failed three times on a real coding prompt, because
Bonsai spends ~1300 reasoning tokens before answering. Measuring at 4096 when production grants
8192 under-provisions by half and manufactures runaways that would never happen in use.

## Speculative decode — off, by measurement

**MTP stays off.** GLM carries an MTP head but nothing here has measured it; Bonsai's declared
head is empty (0 of 2180 tensors); Muse has none.

**DFlash was tried on Muse Glimmer and lost on every axis.** Decode **−15 %** (26.9 → 22.8
tok/s), cold prefill **+21 %** (194 → 161 tok/s), peak RSS +3.9 GB, and two concurrent requests
**serialize** (2.4× a single, against the baseline's 1.33×) because DFlashEngine bypasses the
scheduler. Engagement was proved from the log, not inferred from the rate.

**The finding that outranks the decode number:** DFlash's prefix cache made **9 lookups and 0
insertions**. An identical repeated 12,189-token prompt re-prefilled from scratch — 77–87 s
against the baseline's 10.6 s — confirmed after a real generation, not an artefact of
`max_tokens: 1`. That **inverts the door charge**: on that path every turn re-pays the full
prefill. oMLX does wire the writer, so the gate that declines to publish sits deeper, in
`dflash-mlx`'s own runtime. Harmless while DFlash is off everywhere.

oMLX rejects `mtp_enabled` and `dflash_enabled` together at construction, so the two were never
combinable.

## Validating changes

There is no build step and no test framework — this repo is a Bash launcher (`ai.sh`), a few
opencode plugins (`plugins/*.js`, ESM), agent definitions (`agents/*.md`), and idempotent patch
scripts (`scripts/*.mjs`). There is no `package.json`; don't reach for `npm test`. Validate
edits with:

- `bash -n ai.sh` — syntax-check the launcher.
- `node --check plugins/<file>.js` / `node --check scripts/<file>.mjs`.
- `python3 -m json.tool opencode.json >/dev/null` — validate the config JSON.
- **Prove the parser can see the tool list**:
  `~/.omlx/venv/bin/python .wayfinder/model-roster-swap/assets/w22-muse-toolcall/tools-reach-parser.py`
  (and `--stream`). Needs a running server. Reads a string-typed parameter holding digits: it
  stays `"5"` only when the schema arrived. **Run both paths** — they reach `add_request` through
  different engine entry points, and one was fixed while the other stayed blind.
- **Unit-test the Muse parser patch**:
  `~/.omlx/venv/bin/python .wayfinder/model-roster-swap/assets/w22-muse-toolcall/parser-regress.py`
  — every defect the patch repairs plus the well-formed cases it must not touch, against the
  installed adapter. No server, no model, milliseconds. Run it after any edit to
  `patch-omlx-muse-toolcall.mjs`, and after an oMLX upgrade. Use the oMLX venv interpreter; the
  system `python3` cannot import the adapter.
- **Unit-test the settings patch in isolation**: `node scripts/patch-omlx-mtp.mjs /tmp/ms.json`
  against a throwaway path, then assert the merge — fresh-create, idempotent re-run (no
  rewrite), a pre-existing model preserved, recovery from a corrupt file. No oMLX needed.
- `opencode agent list` — after editing `opencode.json`, confirm the agents opencode resolves and
  their `model`/permissions. **This repo ships no custom agent**; `ai.sh` actively deletes any
  left in `~/.config/opencode/agents/` by an earlier install.
- **Unit-test a plugin hook in isolation** (no oMLX, no opencode): `import` the plugin and invoke
  the returned hook with a synthetic `(input, output)` — e.g. fire `post-edit-check`'s
  `tool.execute.after` with a fake `edit` on a throwaway file and assert what it throws.
- **Restart to load changes**: opencode loads plugins and agents only at startup.

`post-edit-check` runs ESLint/tsc/Prettier on JS/TS edits in the *target* projects opencode
opens. It cleanly no-ops on this repo — and note it gives Bash **no** cover at all.

## Architecture

### `ai.sh` — single Bash function `ai()`

1. **Runtime resolution** — `_resolve_runtime` picks the oMLX binary, the KV-cache directory and
   the cache budget. **One build serves every profile now**, so these no longer vary by model;
   the function stays because the environment may override each of them, and because it computes
   the build id (below).
2. **Model verification** — `_prune_stale_model_links` then `_ensure_model`. Never downloads.
3. **Patches, re-applied idempotently every launch** — `patch-omlx-mtp.mjs` (per-model
   settings), `patch-omlx-mla-kv.mjs` (GLM's MLA KV estimate), `patch-omlx-muse-toolcall.mjs`
   (Muse's output parser), `patch-omlx-vlm-tools.mjs` (the tool list the VLM lane never
   delivered to that parser), the three `opencode-mem` patches, and the two `smart-coding`
   patches. Every one survives a package re-download or an admin-panel toggle by being
   re-asserted rather than assumed.
4. **Server lifecycle** — `_start_server` runs `omlx serve --model-dir … --paged-ssd-cache-dir …`
   with tuned cache/memory flags, under **`nohup` + `disown`**. A bare `&` left the server a
   child of the launching shell, so closing the terminal you typed `ai` in killed it — observed
   twice on 2026-08-13 as a graceful shutdown mid-session, which in the log reads exactly like a
   crash and is not one. macOS has no `setsid`, so this is as detached as it gets; the server
   ends up with PPID 1. Stop it with `ai -k`. oMLX discovers models from `--model-dir` subdirectories, so no
   `--model` is passed; opencode picks the model per request. `_wait_for_server` polls
   `/v1/models` with a spinner and opens a tmux log pane when in tmux. `_kill_server` kills by
   PID file then port scan, and only ever targets python/mlx/omlx processes.
5. **Frontend launch** — `opencode -m mlx/<model-id>` in the caller's original `$PWD`.

### Restarts, and the state file

`$AI_STATE_DIR/omlx-model` holds **two lines**: the served model id, and the **build** serving
it — `<binary path>@<git HEAD of the source checkout>`, with `+mlakv` appended when the MLA
patch applied. A difference in **either** line forces a restart.

The build line earns its place: the oMLX install is **editable**, so the source checkout's
commit *is* the code being served, and an in-place upgrade leaves the binary path identical.
Without it, a stale server keeps answering on old code — invisible from the outside, and
diverging from the model settings and architecture support the new build brought in. A state
file written before this format reads as a mismatch and restarts once.

### The two-model thrash, and why `ai.sh` can only warn

oMLX is multi-model and lazy-loads whatever id a request asks for. So a **lingering opencode
from a previous run** keeps requesting *its* model, and oMLX loads it alongside the new one. Two
large LLMs cannot coexist under the memory guard, so it thrashes (evict/reload) and stalls or
`507`s requests mid-turn — the agent appears to "choke".

`_warn_model_conflict` reads each running opencode's `-m mlx/<id>` argument and warns when one
differs, pointing you at that session and `ai -k`. It cannot fix this automatically, because it
cannot control the other client.

### Memory — `opencode-mem` plugin (`opencode-mem.jsonc`)

Persistent cross-session memory. Activated by `"plugin": ["opencode-mem"]` in `opencode.json`,
configured by `opencode-mem.jsonc` (symlinked to `~/.config/opencode/`). Fully local:

- **Storage**: SQLite at `~/.opencode-mem/data` (macOS uses Homebrew SQLite via
  `customSqlitePath`). Web UI at `http://127.0.0.1:4747`.
- **Embeddings**: `bge-m3` (1024-dim, MLX/Metal) served by oMLX at `/v1/embeddings`. Setting
  `embeddingApiUrl` + `embeddingApiKey` switches the plugin off its in-process Xenova path.
- **Auto-recall**: `chatMessage` injects top memories at session start; `compaction` restores
  them after context compaction.
- **Auto-retain**: `autoCaptureEnabled` summarizes salient turns after idle, on the local oMLX
  server, so capture stays on-box. It fires on `session.idle` plus a **10 s debounce**, so it
  never overlaps the turn that produced it — it overlaps the **next** one.

### The summarizer runs on the session's own model, and the timings are the whole story

`ai.sh` sets `OPENCODE_MEM_MODEL` to the session model, so the summarizer **is** whatever
profile you launched. It was measured on Muse Glimmer at 26 tok/s, which was the default then
and is `--muse` now. A capture there costs **44–99 s** — and the plugin aborts each iteration
at `autoCaptureIterationTimeout`, which ships at **30 s**. On the stock settings auto-capture
therefore **never completed**: 0 of 8 measured captures finished in time. It was broken, not
merely slow.

**The settings did not move with the default on 2026-08-14, and should not.** A `--muse`
session still meets the case they were sized for, and **no capture has been measured on
Bonsai** — its 38 tok/s short-prompt decode suggests a shorter wall, but suggests is all it
does. A timeout with too much headroom costs nothing; one that is too tight drops the memory
in silence.

**The abort is decode-bound, not prefill-bound.** This is the one counter-intuitive fact here,
and it kills the obvious cure: lowering `OPENCODE_MEM_MAX_CONTEXT_CHARS` cuts the prefill but
makes Muse **reason more**, so the wall goes *up* — 44 s at 24,000 chars, **76 s at 2,000**.
Never treat the input cap as a latency lever; it is a memory guard.

`opencode-mem.jsonc` therefore pins three settings as one package:

| Setting | Value | Why |
|---|---|---|
| `autoCaptureIterationTimeout` | `180000` | Fits the measured worst case — a capture overlapping a coding turn stretches to 99 s |
| `autoCaptureMaxIterations` | `2` | At 180 s, 8 iterations is a 24-min tail. Muse called the tool on 8 of 8 solo runs, so retries are rare |
| `memoryExtraParams` | `{"max_tokens": 2048}` | The provider sends **no** `max_tokens`, so oMLX applied its own **32,768** default — a 21-min runaway at 26 tok/s |

`max_tokens` is not in the provider's `PROTECTED_KEYS`, so `memoryExtraParams` is spread
verbatim into the request body — a supported config lever, not a patch. 2048 and not lower:
real captures emit 689–1203 completion tokens, and a cap that truncates yields
`finish_reason: length` with **no tool call at all**, which is a silently failed capture.

**Do not pin the summarizer to a second model.** Both alternatives were measured and both lose.
Bonsai costs the next coding turn ~27 % of its decode rate (72–74 % retained, three runs) —
*worse* than sharing one model — because two models run two forward passes instead of sharing
one batched pass. GLM is worse still: 68 % retained, and Muse + GLM reaches a **44 GB** real
footprint against the guard's 40.8 GB soft target, which sends oMLX into exactly the documented
ping-pong (`Evicting 'Muse-Glimmer-30B-4bit' to fit 'GLM-4.7-Flash-MLX-6bit' … 43.41GB >
40.80GB`, then evicting GLM back). Same-model capture costs only ~20 % (77–81 % retained).

All of that was measured with **Muse** as the session model. The first finding — two models
cost more than one, because they cannot share a batched pass — is about the arrangement, not
about which models fill it, so it carries to the Bonsai default unchanged. **The 44 GB figure
does not carry**: Bonsai leaves ~10 GB more headroom, so a Bonsai + GLM pair may well stay
under the soft target where Muse + GLM could not. Nobody has measured that, and it is no reason
to pin a second model — the batching cost stands on its own.

**Measure memory with `phys_footprint`, never `ps` RSS.** MLX allocates through
`IOAccelerator`, which RSS does not count. With two models resident, RSS read **18.64 GB**
against a real **31 GB** — a **1.66×** under-read. Use `footprint -p <pid>` or `vmmap -summary`.

Three patches make that safe, all re-applied on every launch:

- **Input cap** (`patch-opencode-mem-cap.mjs`). The summarizer is a raw OpenAI client to oMLX,
  so it **bypasses `opencode.json`'s context limit** and would feed oMLX the full, uncapped turn
  transcript — ~120k-token prefills observed, saturating the memory guard, throttling coding
  turns (a 3.8k turn took 340 s) and 507-ing concurrent `bge-m3` loads. The patch caps the input
  to `OPENCODE_MEM_MAX_CONTEXT_CHARS` (default 24000 ≈ 6k tokens), keeping the request-framing
  head and the outcome tail and eliding the middle. It is a **memory** guard: it bounds the
  prefill the summarizer can demand. It is **not** a latency lever — see above, where shrinking
  it makes a capture slower.
- **Model override** (`patch-opencode-mem-model.mjs`). Makes `memoryModel` honour
  `OPENCODE_MEM_MODEL`, which `ai.sh` sets to the **session's own model**. Without it the
  summarizer asks oMLX for a *different* model mid-session, oMLX cannot hold two large models
  under the guard, and it ping-pongs into a `507` thrash loop. The `memoryModel` value in the
  JSONC is only a fallback for a bare `opencode` that `ai.sh` did not launch, so it must always
  name a model oMLX can serve.
- **Directory exclude** (`patch-opencode-mem-exclude.mjs`). `opencode-mem` has no directory- or
  agent-scoped opt-out, so one is patched in: capture, recall and post-compaction restore are all
  skipped when the session directory sits under any prefix in `OPENCODE_MEM_EXCLUDE_DIRS`. Set
  sensitive client-repo roots there via `ai.env`.

**Measured, not open.** W20 measured a capture overlapping a coding turn — the capability suite
had run with the summarizer deliberately unreachable, so nothing on the map had. The numbers and
the settings they justify are above; the method is at
`.wayfinder/model-roster-swap/assets/w20-summarizer/`.

### Post-edit checks — `post-edit-check` plugin (`plugins/post-edit-check.js`)

Deterministic lint/typecheck enforcement, so the agent never leaves broken code behind.
Prompt-level rules ("always run the linter") are advisory and get skipped — especially by a
local model — so this rides opencode's **`tool.execute.after`** hook, the one lever that can
**throw an error back into the agent loop** and force a fix before the turn finishes.

After every `edit`/`write` to a JS/TS file, scoped to that file's project (nearest
`package.json`):

1. **Auto-fix (silent)**: `prettier --write`, then `eslint --fix`.
2. **Re-check**: `eslint --format json` (**file-scoped** — only the edited file's own errors
   block) and `tsc --noEmit` (project-wide; blocks only on type errors in files **the agent has
   edited this session**, so a break it caused earlier still blocks while untouched pre-existing
   errors are surfaced as non-blocking notes).
3. **Block**: remaining errors are `throw`n as a concise `file:line  rule/code  message` list.
4. **Capped retries**: after `OPENCODE_LINT_MAX_RETRIES` consecutive throws for the same
   file+error set it warns instead of blocking, so a local model cannot doom-loop on something it
   cannot fix. (`opencode.json` sets `"doom_loop": "allow"`, so this in-plugin cap is the real
   safeguard.)

Auto-detects tooling and **no-ops cleanly** when ESLint config / `tsconfig.json` / Prettier are
absent. Binaries resolve from the project's `node_modules/.bin` first, else `npx --no-install`
(never auto-installs). tsc uses `--incremental` with a cached `tsBuildInfoFile`, and runs after
every edit — no time-based skip — so a fresh type error can never slip through.

**tsc is not run as `tsc -p tsconfig.json`.** With TypeScript **project references**
(`references: [...]`, common in monorepos), that invocation aborts with `TS6306`/`TS6053` about
the *referenced* projects **before type-checking any source**, so the edited file's real errors
never surface. The plugin generates a wrapper config in
`node_modules/.cache/opencode-tsc-check.json` that `extends` the real tsconfig (absolute path,
so `include`/`exclude` resolve correctly) but clears `references` and `composite`, forcing a
plain whole-program check. Harmless for non-reference projects.

**Global, not per-project.** opencode auto-loads any file in `~/.config/opencode/plugins/` **at
startup** (note the directory is **plural** — the singular `"plugin"` key in `opencode.json` is
the npm-package array, a different mechanism), so `ai.sh` symlinks it there on every launch.
**Restart opencode to pick up any change to it.**

### RAG — smart-coding-mcp

Installed as a **private repo-owned copy** so we never mutate a shared global:
`npm install --prefix ~/.smart-coding-omlx smart-coding-mcp`. `opencode.json` launches it from
there, and two patches are re-applied every launch (so an `npm update` cannot silently revert
them):

- `patch-smart-coding-omlx.mjs` reroutes its in-process Xenova embedder to oMLX's `bge-m3`
  (1024-dim, Metal). Switching the embedding model invalidates a workspace's
  `.smart-coding-cache` (dimensions changed) — already-indexed projects need a one-time
  `rm -rf .smart-coding-cache`.
- `patch-smart-coding-excludes.mjs` adds the `SMART_CODING_EXCLUDE_PATTERNS` /
  `SMART_CODING_EXCLUDE_DEFAULTS` overrides upstream lacks. Its built-in virtualenv set needs no
  configuration.

**Why the exclude patch exists.** smart-coding-mcp derives its final exclude list from
`ProjectDetector` **alone**: `lib/config.js` discards its own 200-entry default list, and in
`--workspace` mode the package's `config.json` is never read (it loads `config.json` from the
*workspace* root), so editing the package config fixes nothing. The detector only emits a
language's ignore patterns when it *detects* that language, yet `py` is unconditionally in
`fileExtensions`. Net effect: a JavaScript repo containing a stray Python virtualenv gets 501
JS-only patterns, none matching `venv`/`site-packages`, and indexes the entire virtualenv as
first-party source. Measured on one client repo: **4,348 of 5,115 files and 133,011 of 140,703
chunks (94.5%) came from `.venv`**, producing a 750 MB `embeddings.db` and pinning oMLX above
100% CPU for hours — with **no LLM loaded**, since the embedder issues one HTTP request per
chunk.

**Patterns are not glob-matched.** `discoverFiles` reduces each pattern to a bare directory name
via `pattern.match(/\*\*\/([^/*]+)\/?\*?\*?$/)` and exact-matches that basename at any depth. So
a pattern only works as literally `**/<name>/**` with no wildcard inside `<name>`:
`**/*.egg-info/**` extracts nothing and is silently inert, and file-level globs like
`**/*.min.js` can never work.

**Changing excludes does not shrink an existing index.** Stored chunks persist in
`.smart-coding-cache/embeddings.db`; delete that directory (with opencode closed, so nothing
holds the SQLite WAL) to reclaim the space and re-index clean.

### MCP kill-switch — present, unclaimed

`ai.sh` can disable **every** MCP server for a session without editing `opencode.json`: it
builds an inline config marking `enabled:false` for each server keyed under `mcp` and passes it
via **`OPENCODE_CONFIG_CONTENT`**, which opencode deep-merges **last** (later wins). The
override is session-scoped and automatically covers any MCP added later.

The retired `-l` profile owned this behaviour. **No profile claims it today** — the branch reads
`if (( mcp_free ))` with `mcp_free=0`, one assignment from live. It stays because it costs
nothing while idle, and because the GLM context fail-safe reuses the same overlay mechanism.

### No cloud path — the `@advisor` subagent is removed

`ai` runs entirely on this box. There is no hybrid mode, no cloud subagent, and no flag that
opens one: `--hybrid` and `--no-hybrid` both exit 1, because silently accepting `--no-hybrid`
would read like a guarantee from a launcher that no longer has anything to disable.

`agents/advisor.md` and `plugins/advisor-egress-log.js` are gone, and `ai.sh` **deletes their
symlinks from `~/.config/opencode/` on every launch**, alongside the AFK scraps. That deletion is
the load-bearing part: opencode auto-loads whatever sits in `agents/` and `plugins/` at startup,
so removing the repo copy alone would leave an older install still resolving `@advisor` against
the `anthropic` provider.

`logs/advisor-egress.jsonl` is **kept**. It is the audit trail of what actually left this machine
while the advisor existed (one call, 2026-06-16), and a record of egress should outlive the
feature that caused it.

## Configuration

Set these in `ai.env` (gitignored) or export them before running. `ai.env.example` holds
commented placeholders.

| Variable | Default | Description |
|----------|---------|-------------|
| `AI_DIR` | auto-detected | Base directory of the tool |
| `AI_LOG_DIR` | `$AI_DIR/logs` | Server log directory |
| `AI_STATE_DIR` | `~/.local/state` | State and PID files |
| `AI_PORT` | `10081` | oMLX server port |
| `OMLX_BIN` | `$OMLX_VENV/bin/omlx`, else `omlx` on PATH | oMLX server binary. The venv build is preferred because a PATH build is whatever was installed last |
| `OMLX_VENV` | `~/.omlx/venv` | Virtualenv holding that binary |
| `OMLX_SRC_DIR` | `~/.omlx/src` | oMLX source checkout. The install is **editable**, so this checkout's git HEAD is the code being served; `ai.sh` records it in the state file and a change there restarts a running server |
| `OMLX_MODEL_DIR` | `~/.omlx/models` | Dir oMLX discovers models from. Holds `bge-m3` plus one symlink per roster model. **Do not** repoint it at the weight store — `bge-m3` would be stranded |
| `HF_HUB_CACHE` | `$HF_HOME/hub`, else `~/.cache/huggingface/hub` | LM Studio's weight store — the single copy of every model's weights. `ai.sh` only ever reads and links it |
| `OMLX_BASE_DIR` | `~/.omlx` | oMLX base path; `$OMLX_BASE_DIR/model_settings.json` is where `patch-omlx-mtp.mjs` writes the per-model rails |
| `OMLX_CACHE_DIR` | `~/.omlx/cache` | Paged SSD KV-cache directory |
| `OMLX_HOT_CACHE` | `8GB` | In-RAM hot KV tier. Model + tier must fit under the memory guard's soft threshold or oMLX evicts models mid-request |
| `OMLX_SSD_CACHE_MAX` | `25GB` | Disk cap for the paged SSD cache (unset, oMLX claims nearly all free disk) |
| `OMLX_CACHE_PRUNE_GB` | numeric part of `OMLX_SSD_CACHE_MAX` | Prune the on-disk KV cache to this many GB at each server (re)start, oldest-first. Derived from the same number the server is given, so the two can never disagree. Set `0` to disable |
| `OMLX_MEMORY_GUARD_GB` | `48` | Memory ceiling oMLX will not exceed. **It does not set the prefill abort limit** — see Context windows |
| `OMLX_MAX_CONCURRENT` | `2` | Max concurrent requests (continuous batching): 1 coding turn + 1 summarizer. Don't set 1, or memory captures serialize with coding turns |
| `OPENCODE_MEM_MODEL` | set by `ai.sh` to the session model | Summarizer model, read by the patched plugin |
| `OPENCODE_MEM_MAX_CONTEXT_CHARS` | `24000` | Char budget the summarizer input is capped to (≈6k tokens) |
| `OPENCODE_MEM_EXCLUDE_DIRS` | unset | Colon-separated dir prefixes where opencode-mem never captures or recalls |
| `SMART_CODING_OMLX_DIR` | `~/.smart-coding-omlx` | Prefix holding the private smart-coding-mcp copy |
| `SMART_CODING_EXCLUDE_PATTERNS` | unset | Colon-separated extra directory globs kept out of the RAG index. Each entry must be exactly `**/<dirname>/**` |
| `SMART_CODING_EXCLUDE_DEFAULTS` | unset (`true`) | Set `false` to drop the built-in virtualenv / tool-cache excludes |
| `OPENCODE_LINT_ENABLED` | `true` | Master on/off for post-edit-check |
| `OPENCODE_LINT_CHECKS` | `eslint,tsc,prettier` | Which post-edit checks to run |
| `OPENCODE_LINT_MAX_RETRIES` | `3` | Consecutive blocking throws per file before falling back to warn-only |
| `OPENCODE_LINT_EXTENSIONS` | `.ts,.tsx,.js,.jsx,.mjs,.cjs` | Extensions the hook acts on |

## Dependencies

- **`omlx`** — the local inference server, currently `0.5.8.dev3` at tag `v0.5.8.dev3`
  (`350dc08b`), with `mlx 0.32.0`, `mlx-lm ab1806e8`, `mlx-vlm 0.6.3` and `transformers 5.12.1`.
  The Homebrew formula fails (its sandboxed build cannot see `cargo` to compile `rpds-py`);
  build from source into a venv with `uv`:
  ```bash
  git clone https://github.com/jundot/omlx ~/.omlx/src
  uv venv ~/.omlx/venv --python 3.12
  VIRTUAL_ENV=~/.omlx/venv uv pip install -e ~/.omlx/src
  ```
  **No compiler is needed** — the custom Metal kernels are opt-in behind
  `OMLX_WITH_CUSTOM_KERNEL`. **Upgrade in place, one build**: no second checkout, no second
  venv. Rolling back needs explicit pins for `mlx` and `transformers`, because the pyproject
  uses floors.
- **`uv`** — builds and runs the oMLX venv.
- **`opencode`** — the frontend, sst/opencode (`brew install sst/tap/opencode`).
- **`node`** — required by `opencode-mem` (auto-installed by opencode from the `"plugin"` array)
  and by every `scripts/*.mjs` patch.
- **`smart-coding-mcp`** — RAG, as a private copy (see RAG above).
- **LM Studio** — owns the weight store and provides the cross-runtime A/B. Optional for `ai`
  itself, but it is where you download models.
- **Models** live in LM Studio's store and are symlinked under `~/.omlx/models/<org>/<repo>`.
  `bge-m3` is the exception: `mlx-community/bge-m3-mlx-fp16` downloaded straight into
  `~/.omlx/models/bge-m3`.

## Server tuning

oMLX launches with explicit flags (see the `OMLX_*` variables above):

- **`--paged-ssd-cache-dir ~/.omlx/cache`** — the headline feature. Block-based KV cache
  (vLLM-style, prefix sharing + copy-on-write) with a cold SSD tier; recurring prefixes are
  restored from disk on a hit, **even across a server restart**, instead of recomputed.
- **`--paged-ssd-cache-max-size 25GB`** — disk cap. Without it oMLX sizes the cache off free disk
  and grows until the disk is nearly full.
- **`--hot-cache-max-size 8GB`** — the in-RAM hot tier (oMLX's default is 0/disabled; it must be
  set explicitly). A bigger tier means more in-memory hits before spilling to SSD, but model +
  tier must stay under the guard's soft threshold.
- **`--memory-guard-gb 48`** — the ceiling oMLX will not exceed, leaving ~16 GB for macOS on a
  64 GB machine. Eviction starts at the 85% soft threshold (40.8 GB), not at the ceiling.
- **`--max-concurrent-requests 2`** — continuous batching. One slot for the coding turn, one so
  the summarizer can overlap it instead of serializing. Kept at 2 because each concurrent prefill
  adds transient working memory against the soft threshold; embeddings run on the separate
  `bge-m3` engine and don't compete for these slots.

### `_prune_cache` is load-bearing, not a safety net

**oMLX's own LRU governs only its *live* index.** Blocks orphaned by a prior run or a
model/quant switch fall out of that index and are never revisited, so the on-disk footprint
drifts far past the cap — observed at **122 GB against a 40 GB cap** (~19 days), filling the disk
to 99%.

`_prune_cache` deletes blocks oldest-first (mtime = LRU, matching oMLX's intent) at every server
(re)start. It runs only with the server down, so nothing holds the blocks live; blocks are
content-addressed, so a lookup for a pruned one is just a miss → recompute, which is the safe
failure mode.

**A model switch orphans the whole cache.** One switch logged
`skipped_incompatible=399 blocks (5.15 GB)` — the previous model's entire cache, unusable. And
one measurement session on a slow-prefill model took the cache from 5.15 GB to **24 GB**. So
25 GB is a working budget, not generous headroom; expect to start from a full cache. Muse
Glimmer contributes almost nothing to it (its 13 KB/token KV never fills the 8 GB hot tier), so
the budget is sized by Bonsai and GLM alone — **and since 2026-08-14 one of those two is the
default**, so the cache now fills in ordinary use rather than only during measurement runs.

**Deleted space may not appear as free.** macOS holds it in APFS Time Machine local snapshots
until it needs it — the space is *purgeable* rather than free, and `df` will not move. Deleting
those snapshots destroys backup history and is your call, not the launcher's.

## Key details

- **Port 10081** — OpenAI `/v1`, Anthropic `/v1/messages`, embeddings `/v1/embeddings`, rerank
  `/v1/rerank`; oMLX admin/chat UI at `/admin`.
- **Logs**: `$AI_LOG_DIR/omlx-server-<timestamp>.log` (`*.log` older than 14 days pruned at
  server start); oMLX also writes `~/.omlx/logs/server.log`.
- **State file**: `$AI_STATE_DIR/omlx-model` (two lines — model id, then `<binary>@<git HEAD>`);
  **PID file**: `$AI_STATE_DIR/omlx-server.pid`.
- **Startup timeout**: 120 s. oMLX binds in ~1–3 s; the first chat request lazily loads the model
  (2.9–8.9 s depending on profile).
- **In tmux**: auto-opens a split pane tailing the server log.
- **Config symlinks**: `opencode.json` and `opencode-mem.jsonc` → `~/.config/opencode/`;
  `plugins/post-edit-check.js` → `~/.config/opencode/plugins/` (plural).
- **`get_speculation_stats()` is not reachable** from the CLI — it is served only from
  `/admin/api/activity`, which 401s without a session cookie.
- **The route that produced this file** is charted at `.wayfinder/model-roster-swap/`: the map,
  one ticket per decision, and the measurement assets under `assets/`. Read a ticket before
  re-opening the question it closed.
