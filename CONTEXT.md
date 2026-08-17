# ai-cli

A launcher that serves local MLX models from one oMLX process and connects opencode to
them. This glossary fixes the words used to compare those models, because the loose
ones hide real differences.

## Language

### Roster

**Profile**:
One named model that `ai` serves, selected by its own flag. The bare `ai` command
selects the default profile. A profile normally names a fixed model; a **slot** is the
exception.
_Avoid_: mode, variant, flag

**Slot**:
A flag that carries the **newest model of a family** rather than a fixed model, so a
later release replaces the current occupant under the same flag instead of earning a
flag of its own. `--qwen` is the one slot on this roster. The **default never lives in
a slot**: a default that followed a slot's next occupant would move with no measurement
at all. A slot occupant that wins the default takes it *as that model*, and its
replacement re-enters as a challenger.
_Avoid_: profile, flag, alias (each hides that the model behind it changes)

**Serve check**:
The functional gate a model passes before it earns a profile: `finish_reason: stop`,
non-empty `content`, reasoning split out, and a tool call that parses — measured at
4096 output tokens or more. It proves the model *works*. It says nothing about how
well the model writes code.
_Avoid_: smoke test, benchmark, quality test

**Capability**:
How well a model performs the actual work, measured against real coding tasks. No
serve check measures it. It has been measured at two lengths on this roster — under
4,000 tokens and at ~17.6k — and the ranking at one does not survive the other. Nothing
measures it near a full context window. **Name the length whenever you quote it.**
_Avoid_: quality, intelligence, performance (which reads as speed)

**pass@1 / pass@2**:
Whether a model satisfied a task on its first attempt, or after exactly **one** repair
turn carrying the **real** failure output — the failing assertion or shell error, not a
hint written by hand. The gap between the two rates is what a single-shot test cannot
see: a model can lead on pass@1 and still be the worst in an agent loop, because it
cannot act on an error message. GLM does exactly that.
_Avoid_: score, success rate (each hides whether feedback was allowed)

**Minutes per solved task**:
A model's own wall-clock divided by the tasks it actually solved. It is the metric that
picks the **default profile**, because a rate in tok/s prices only the turns that work: a
wasted turn is fast, so raw speed flatters the model that fails. At short prompts: Muse
3.46, GLM 3.83, Bonsai 4.09 — which reverses the tok/s ranking. At ~17.6k, on the three
separating tasks: Bonsai 2.31, Muse 3.19, GLM 3.64 — which reverses the short-prompt one.
Qwen3.8 arrived later and is **not on either scale**: its 1.81 at short prompts and 3.14
at ~17.6k come from their own run, against a re-run Bonsai reading 4.47 and 3.50 there.
**Always say which length and which run a figure comes from**; the orders disagree, and
figures from different days are not comparable. Read it only beside the solved count,
since a model that solves one task quickly scores well on this alone.
_Avoid_: throughput, speed, tok/s (each hides the wasted turns)

**Protocol failure**:
A run unusable in an agent loop rather than merely wrong: an unparsable tool call, no
code block where one was demanded, empty content, a runaway, or generated code that
touches the filesystem or network. Counted as a failure and reported **separately**,
because "unusable" and "incorrect" are different defects and averaging them hides both.
_Avoid_: error, failure

**Runaway**:
A turn that reaches its `max_tokens` cap without producing an answer
(`finish_reason: length`), spending the whole output budget for nothing. Measure at the
budget production actually grants — `opencode.json` declares `output: 8192` — because a
smaller cap manufactures runaways that would never happen in use.
_Avoid_: truncation, timeout

### Prefill and cache

**Door charge**:
The cold prefill paid on the first turn of a visit to a directory, when no cached
prefix matches. Paid once per visit, not once per turn.
_Avoid_: TTFT, time to first token, prefill (each hides whether it is per visit or per
turn)

**Per-turn prefill**:
What every turn after the first pays: the tokens outside the cached prefix, at the
model's own prefill rate. Larger than the appended text alone, because the cache
matches only whole blocks.
_Avoid_: TTFT, incremental prefill

**Prefix-extension hit**:
The paged cache matching the start of a growing conversation, so a turn prefills only
its new tokens. Matches in whole blocks, so the tail of an already-seen prefix is
re-prefilled.
_Avoid_: cache hit

**Warm restore**:
The paged cache serving a prompt whose prefix it has seen before, in a later request
or a later server run. Distinct from a prefix-extension hit, which happens inside one
growing conversation.
_Avoid_: cache hit

**Cache block**:
The unit the paged cache stores, evicts and matches on — one file on disk, 2,048
tokens for every model here except GLM, which uses 256. It is **larger than the KV the
same tokens need**, because a model whose layers are not all attention writes a fixed
state per block as well. Say which of the two you mean whenever you price the cache.
_Avoid_: KV, block (each hides the fixed term)

**Cache budget**:
The bytes the paged cache is allowed on disk, across every model. One number serves
the whole roster, so profiles compete for it. It is not the size of any one model's
cache, and it is not free disk.
_Avoid_: cache size, cache cap

**Natural prefill rate**:
The rate a model prefills at when the throttle is not engaged. It falls as the prompt
grows, because prefill cost is `a*n + b*n²` and attention is the square term. A rung
that costs much more than that curve predicts is throttled; a rung on the curve is not.
Name it whenever a rate is quoted, because "prefill is slower at 40k" hides which of the
two causes is acting.
_Avoid_: prefill rate, tok/s

**Patience ceiling**:
The largest prompt whose **door charge** fits the time a person will actually wait. It
is a property of the model and the box, not of memory. On this box, in 120 s: GLM
reaches ~32,300 tokens, Muse Glimmer ~22,800, Qwen3.8 21,127 and Ternary Bonsai ~21,000.
It caps the size of a **cold** open, and it does **not** set the declared context — a
session that grows to a large window pays its door charge once, so every model here
except GLM declares far above its own ceiling on purpose.
_Avoid_: context limit, max context (each reads as the declared number)

### Context limits

Three different numbers, and each one bounds a different party. Say which you mean.

**Declared context**:
The token budget `opencode.json` gives a profile. opencode reads it, tracks the session
against it, and compacts as the session approaches it. It binds **the client only**:
nothing stops a caller that never reads that file. On this roster it sits **above** the
patience ceiling for every model except GLM, and that is deliberate — a session grows one
cached turn at a time, so only a cold prompt that arrives whole at that size pays the
full-window door charge.
_Avoid_: context limit, max context, context window

**Context rail**:
The per-model cap pinned in oMLX's own settings. It binds **the server**, and it exists
for the callers the declared context cannot reach — the memory summarizer, smart-coding, a
stray script. It rejects an oversized prompt before prefill starts, so the caller pays an
immediate error instead of minutes. It is always the declared context **plus one
4,096-token block**: mirroring the two exactly was tried and rejected a legitimate prompt,
because opencode counts tokens with its own tokenizer and a prompt built for 32,768
arrived as 32,784.
_Avoid_: context limit, max context, declared context

**Native window**:
The window a model's own config declares — 262,144 for Ternary Bonsai and Qwen3.8, 202,752
for GLM, 131,072 for Muse Glimmer. It is what oMLX falls back to when **no context rail is
pinned**, and it is far past what this box prefills in any usable time. It bounds nothing
in practice. The patience ceiling does.
_Avoid_: context window, max context, model context

### Memory guard

**Charged KV**:
The KV cache size oMLX *estimates* for a model. It is what prefill admission prices a
prompt against. It can differ from the real KV by a large factor, and when it does, the
model is refused memory it never needed.
_Avoid_: KV size, KV cache (each hides whether it means the estimate or the fact)

**Real KV**:
The KV cache size the model's architecture actually needs, derived from its config.
_Avoid_: KV size, KV cache

**Prefill admission**:
The check that accepts or rejects a prompt *before* prefill starts, comparing memory in
use plus charged KV against the ceiling. It rejects with an HTTP error and costs the
turn.
_Avoid_: memory guard (which also covers eviction and the throttle)

**Prefill throttle**:
The separate mechanism that shrinks the prefill chunk as memory approaches the target.
It makes a prompt slower. It never rejects one.
_Avoid_: memory guard
