# ai-cli

A launcher that serves local MLX models from one oMLX process and connects opencode to
them. This glossary fixes the words used to compare those models, because the loose
ones hide real differences.

## Language

### Roster

**Profile**:
One named model that `ai` serves, selected by its own flag. The bare `ai` command
selects the default profile.
_Avoid_: mode, variant, flag

**Serve check**:
The functional gate a model passes before it earns a profile: `finish_reason: stop`,
non-empty `content`, reasoning split out, and a tool call that parses — measured at
4096 output tokens or more. It proves the model *works*. It says nothing about how
well the model writes code.
_Avoid_: smoke test, benchmark, quality test

**Capability**:
How well a model performs the actual work, measured against real coding tasks. No
serve check measures it. W14 established it for this roster on **short prompts only**
(all under 4,000 tokens); nothing measures it near a full context window.
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
**Always say which length a figure comes from**; the two orders disagree, and the second
is what set the current default. Read it only beside the solved count, since a model that
solves one task quickly scores well on this alone.
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

**Natural prefill rate**:
The rate a model prefills at when the throttle is not engaged. It falls as the prompt
grows, because prefill cost is `a*n + b*n²` and attention is the square term. A rung
that costs much more than that curve predicts is throttled; a rung on the curve is not.
Name it whenever a rate is quoted, because "prefill is slower at 40k" hides which of the
two causes is acting.
_Avoid_: prefill rate, tok/s

**Patience ceiling**:
The largest prompt whose **door charge** fits the time a person will actually wait. It
is a property of the model and the box, not of memory. On this box GLM reaches ~32,300
tokens in 120 s and Muse Glimmer ~22,800. It caps usable context below every memory
limit here, so a declared context above it buys a window nobody opens.
_Avoid_: context limit, max context (each reads as the declared number)

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
