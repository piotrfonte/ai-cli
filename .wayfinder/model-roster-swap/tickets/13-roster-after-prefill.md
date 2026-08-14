---
id: W13
title: Decide the roster now that Bonsai prefills at ~200 tok/s
map: model-roster-swap
labels: [wayfinder:grilling]
status: closed
assignee: claude
blocked_by: [W7]
---

## Question

The destination names three models. One of them, Bonsai, now measures at the exact
latency that removed a model from this roster two days ago. Does it stay?

W6 found `prism-ml/Ternary-Bonsai-27B-mlx-2bit` passes every functional check —
serves, splits reasoning, calls tools, loads its ternary quant, reaches 65,536
context, provokes no memory fault at all — and prefills at **194 tok/s**, giving
**66.2 s to first token on a 12,818-token agentic turn**. `--muse` was deleted on
2026-08-10 for ~64 s on the same size of prompt.

So this is not a question about whether the model works. It is a question about what
the roster is *for*.

### Why this waits on W7

Muse Glimmer is the other dense model, carrying the same suspected fault, and the map
already flags it as "unmeasured, not known-bad". If both fail on prefill, the
three-model table in the destination collapses and that is **one** scoping
conversation, not two run separately. If Muse passes, the question narrows to Bonsai
alone and gets a much easier answer.

Do not pre-empt it. Read W7's number first.

### From W7 — the other one failed too, so this is the collapse case

**Muse Glimmer prefills a 12,882-token prompt in 64.5 s (187–200 tok/s).** It passes
every functional check at its defaults and reaches 65,536 context with no warning, in
6 m 54 s. So both dense models now sit on the ~64 s that removed `--muse` on
2026-08-10, and the three-model table in the destination is down to **one model that
prefills quickly**:

| | Prefill @12.8k | Decode | Resident | KV @65k |
|---|---|---|---|---|
| GLM 4.7 Flash | ~590 tok/s | ~68 tok/s | 22.89 GB | 3.5 GB (charged 7×) |
| Bonsai 27B | 194 tok/s — **66.2 s** | ~38 tok/s | **8.44 GB** | 4.0 GB |
| Muse Glimmer 30B | 187–200 tok/s — **64.5 s** | ~26 tok/s | 18.59 GB | **~1.0 GB** |

**Muse Glimmer is dominated.** Bonsai matches its prefill, decodes 1.4× faster, and
costs 2.2× less memory. Any argument that keeps Muse keeps Bonsai first — so option 4
below ("replace it with a different small model") cannot be answered by promoting one
of these two over the other.

This also absorbs the map's old fog patch **"what replaces a model that fails its serve
check"**. It is no longer hypothetical: two have failed, no fallback is chosen, and
picking one is either this ticket's job or a fresh effort.

**What Muse Glimmer alone would bring**, if the roster wanted it: the cheapest KV of
the three (13 of 52 layers cache KV ⇒ ~1.0 GB at 65 k), and it writes **nothing** to
the SSD KV tier. Against that, only 13 of 52 layers see the whole window, so
long-range recall is the weakest of the three, and its native window is 131,072 rather
than ~262 k. Neither fact touches the 64.5 s.

### What the decision has to weigh

- **Bonsai is by far the cheapest model on the roster** — 8.44 GB resident against
  GLM's 22.89 GB. That is its real argument: it is the only profile that leaves the
  box usable for anything else, and the one that would survive a smaller machine.
- **Prefill is what agentic coding spends its time on.** A coding turn carries file
  context; 12.8k tokens is a modest turn, not a large one.
- **Warm restore is excellent** — a repeated 25k prefix comes back in ~3.5 s. A
  session that keeps hitting the same prefix pays the 66 s once. How much that
  redeems the profile depends on how the user actually works.
- **Decode has headroom that has not been claimed.** Building
  `OMLX_WITH_CUSTOM_KERNEL=1` would lift the ~38 tok/s decode via the Bonsai qmv
  kernels. It does **not** touch prefill (W6 §5), so it cannot rescue the number
  under discussion — but it changes the model's standing if it stays.

### The options worth naming

1. **Keep it as-is**, accepting 66 s TTFT, on the grounds that a 8.44 GB profile earns
   its place on memory alone and warm restore softens the cost in practice.
2. **Keep it with a lowered context cap**, so the profile advertises what it can serve
   quickly rather than what it can serve at all. 65,536 is reachable but costs 7m 24s
   cold.
3. **Drop it** and let the roster be two models, redrawing the destination. After W7
   this reads differently: dropping both dense models leaves **one**, and the
   destination's table has to be redrawn either way.
4. **Replace it** with a different small model. The map has no candidate and choosing
   one is arguably a fresh effort, not a step on this route.
5. **Accept that only GLM prefills quickly** and keep the other two as deliberate
   trade profiles — Bonsai for memory, Muse for nothing measured so far — with caps
   and documentation that say so plainly.

### What this ticket must produce

A decision recorded plainly enough that W8, W9 and W11 can be written against it — the
profile list, the flag names, and the context cap for whatever survives. W8 and W9 are
blocked on this for exactly that reason.

### Related

- [Serve-check Ternary Bonsai 27B 2-bit and measure it](06-serve-check-bonsai.md) — the
  measurement this ticket reacts to.
- [Serve-check Muse Glimmer 30B 4-bit and measure it](07-serve-check-muse.md) — closed;
  the second measurement this ticket reacts to.
- [Decide GLM's context cap against oMLX's 7x MLA over-count](12-glm-context-cap.md) —
  the other open cap question. W6 showed the two are independent: GLM's cap is forced
  by an accounting bug, Bonsai's would be a latency choice.

## Resolution

**All three models stay. The destination's table is unchanged.** The user decided this
after two rounds of argument against Muse Glimmer, and the argument was answered — see
§3, which is the important part of this resolution.

| Profile | Model | Context |
|---|---|---|
| bare `ai` | `lmstudio-community/GLM-4.7-Flash-MLX-6bit` | set by [W12](12-glm-context-cap.md) |
| `--bonsai` | `prism-ml/Ternary-Bonsai-27B-mlx-2bit` | **65,536 / 8,192 out** |
| `--muse` | `mlx-community/Muse-Glimmer-30B-4bit` | **65,536 / 8,192 out** |

`-l`, `--lite`, `-g`, `--gemma` and `--macaw` remain hard errors naming the
replacement, per constraint 6. GLM stays on the **current 6-bit build** — no re-quant.

W8, W9 and W11 can now be written. **Keeping all three costs no new disk**: every
weight is already in the store (GLM 23 GB, Muse 18 GB, Bonsai 7.9 GB), so nothing is
downloaded and the 15 GiB free does not shrink.

### 1. The 66 s is a door charge, not a per-turn tax

The ticket's premise was wrong, and measuring it changed the decision. W6 measured a
*cold* 12.8k prefill; an agentic turn 2 is a **strict extension** of turn 1, so the
paged cache may match the prefix. It does.

| Turn | Prompt | Cached | Fresh | Time |
|---|---|---|---|---|
| 1 — cold, at the door | 12,840 | 0 | 12,840 | **58.63 s** |
| 2 — small tool result | 13,687 | 12,288 | 1,399 | **7.40 s** |
| 3 — 2k tool result | 17,115 | 12,288 | 4,827 | 24.24 s |
| 4 — 2k tool result | 20,543 | 16,384 | 4,159 | 22.51 s |
| 5 — small tool result | 21,390 | 20,480 | 910 | **5.45 s** |
| repeat of turn 1 | 12,840 | 12,288 | — | **3.18 s** |

Method and scripts: [assets/w13-prefix-extension](../assets/w13-prefix-extension/).
`max_tokens: 1` on every request, so wall time is prefill alone.

So the honest cost of a **folder visit** is ~59 s once, then ~5–25 s a turn. Against
GLM at 590 tok/s the same visit costs 21.8 s and ~4 s a turn. **Bonsai is ~2.7× the
wait at every step, not only the first** — which is worse than "one slow start" and
better than "66 s per turn". Both readings were in play before this was measured.

**`cached_tokens` rounds down to a 2048-token block.** Up to ~2k tokens of already-seen
prefix are re-prefilled every turn, which is why a ~500-token append charges 1,399
fresh. Budget for it. Nothing spilled to the SSD tier at these sizes.

The terms are now fixed in [CONTEXT.md](../../../CONTEXT.md): *door charge*, *per-turn
prefill*, *prefix-extension hit*, *warm restore*.

### 2. TTFT gates the default, not every profile

GLM is the default because it prefills ~2.7× faster than anything else here. An opt-in
flag may be slow when it buys something the default cannot — Bonsai's **8.44 GB
resident** against GLM's 22.89 GB is that something. The documentation must lead with
the per-turn number, not with warm restore; warm restore is real (3.18 s) but it is not
the argument, because the user's pattern is sparse hops between directories where most
visits start cold.

### 3. The case against Muse Glimmer was wrong, and this is the correction

W7 and this ticket both said Muse is "dominated on every axis". **Every axis measured
is speed or memory. None is capability.** The serve checks in W5, W6 and W7 prove the
models *work* — `finish_reason: stop`, reasoning split, a tool call that parses. They
do not test which model writes better code, and the map had quietly let "dominated"
stand in for that.

The user challenged this directly, and it does not survive:

- **Bonsai is a 2-bit ternary fine-tune of `Qwen/Qwen3.6-27B`** by prism-ml. Its card
  claims 95% of FP16 retained and 80.49 average over 15 thinking-mode benchmarks
  against 72.73 for a conventional IQ2_XXS build. **Vendor-published, unverified here,
  and benchmarked against its own FP16 — not against Muse Glimmer.**
- **No head-to-head exists.** Different lineage, no shared benchmark, and nothing in
  this repo has tested either beyond a linked-list reversal.

So keeping both is the position that needs the least unproven belief. Dropping Muse
needed a capability claim nobody has. Capability now has its own ticket —
[Measure coding capability across the three profiles](14-capability-comparison.md) —
and until it closes, the roster is chosen on speed and memory alone. **W11 must say so
plainly in the documentation.**

### 4. The scope line on swapping models

Two different acts, and only one is on this map:

- **A new model** — fresh architecture, fresh serve check, unknown. **Out of scope.**
  Muse and Bonsai each cost a full session.
- **A different quant of a model already on the roster** — same architecture, serve
  check largely re-usable. **In scope**, because it can attack an open blocker.

### 5. `unsloth/GLM-4.7-Flash-NVFP4` cannot load on this stack

Raised during the session, and worth recording so nobody re-checks it.

The checkpoint is `quant_method: compressed-tensors`, `format: mixed-precision` — FP8
channel-wise weights in one group, FP4 `tensor_group` at group 16 in the other, with
**quantized activations** on both. It targets vLLM on Blackwell.

`mlx_lm/utils.py:394` handles `compressed-tensors` by **hardcoding**
`{group_size: 32, bits: 4, mode: "affine"}`, without reading the checkpoint's recipe.
oMLX knows this is wrong — `omlx/utils/model_loading.py:143` exists to correct it, and
its docstring says the mlx-lm assumption "is wrong for float-quantized (FP8) and
nvfp4-pack-quantized checkpoints" — but it **returns early unless
`model_type == "laguna"`**, and this model is `glm4_moe_lite`. It also maps only
`nvfp4-pack-quantized` and `pack-quantized`, not `mixed-precision`, and relies on a
vendored Laguna `sanitize` to reshape tensors. GLM has no equivalent. The model would
be declared int4-affine-g32 when it is not.

**MLX's nvfp4 mode itself is fine on Metal** — `mx.quantize` + `mx.quantized_matmul` at
group 16 pass on the GPU here. The format is not the barrier; the loader path for this
checkpoint's flavour is. Supporting it means writing a GLM sanitize into oMLX.

**A native MLX 4-bit GLM does exist** and loads with no patching:
`lmstudio-community/GLM-4.7-Flash-MLX-4bit`, **15.70 GB** against the 6-bit's 22.67 GB.
The freed ~7 GB attacks W12 directly, because that guard rejects on estimated KV plus
resident weight against the Metal cap. Recorded as a fourth option on
[W12](12-glm-context-cap.md); not taken here, because the user chose the 6-bit build.

### 6. What this unblocks and creates

- **Unblocks** [W8](08-rewrite-ai-sh.md) and [W9](09-rewrite-opencode-json.md).
- **Creates** [W14 — capability comparison](14-capability-comparison.md) and
  [W15 — DFlash drafter for Muse Glimmer](15-dflash-drafter-muse.md).
- **Feeds** [W12](12-glm-context-cap.md) a fourth option.
