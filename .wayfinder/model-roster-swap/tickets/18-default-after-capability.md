---
id: W18
title: Decide the default profile now that capability is measured
map: model-roster-swap
labels: [wayfinder:grilling]
status: closed
assignee: claude
blocked_by: [W14]
---

## Question

**Should bare `ai` still serve GLM 4.7 Flash?**

GLM is the default for one measured reason: it prefills ~3× faster than anything else on
the roster, so the door charge on a 12.8k-token visit is ~21.8 s against Bonsai's 58.6 s
and Muse's 64.5 s. That choice was made when **no measurement tested capability**.

[W14](14-capability-comparison.md) has now tested it, and GLM comes last:

| Model | pass@1 | pass@≤2 | Recoveries | Runaways | Door charge | Decode |
|---|---|---|---|---|---|---|
| GLM 4.7 Flash 6-bit | 6/12 | 6/12 | **0** | **4/12** | **21.8 s** | **68 tok/s** |
| Ternary Bonsai 27B 2-bit | 5/12 | 8/12 | 3 | 2/12 | 58.6 s | 38 tok/s |
| Muse Glimmer 30B 4-bit | **9/12** | **11/12** | 2 | **0/12** | 64.5 s | 26 tok/s |

So the default is the fastest model and the weakest coder, and the ranking on speed is
the exact reverse of the ranking on capability.

### What makes this a real decision and not a swap

- **The door charge is paid once per directory visit, not per turn** — W13 measured that.
  So Muse's 64.5 s against GLM's 21.8 s costs ~43 s *once*, then later turns prefill only
  their fresh tokens. Against that, a wasted turn costs a full 8,192-token decode, and
  GLM wasted one turn in three.
- **Decode is per turn and does not amortise.** Muse at 26 tok/s is 2.6× slower than GLM
  on every single answer, for the whole session. That is the real cost of switching, and
  it is not a one-off.
- **GLM's failure modes are the expensive kind.** A runaway burns the entire output
  budget and returns nothing; a model that cannot act on `post-edit-check`'s error
  message forces the user to intervene. Both cost more than their wall-clock suggests.
- **Muse is oMLX-only.** [W10](10-remove-muse-gguf.md) found LM Studio cannot load it and
  deleted its GGUF, so making it the default means the default has no cross-runtime
  fallback. GLM and Bonsai keep one, pending
  [W16](16-lmstudio-load-check.md).
- **GLM's context is capped at 32,768** against 65,536 for the other two
  ([W12](12-glm-context-cap.md)), so the default also has the shortest usable window —
  though Muse's *native* window is the shortest of the three at 131,072, and only 13 of
  its 52 layers see all of it.

### What the answer must not rest on

W14 measured **four tasks, 12 runs per model, every prompt under 4,000 tokens**. It says
nothing about long-context work, and a gap of one or two runs is noise. A decision to
move the default should say plainly which part of the evidence it leans on, and 9 against
6 is the only gap here that carries weight.

If the answer is "measure more before moving", say what measurement would settle it —
otherwise the default stays where it is by default rather than by decision.

### Options on the table

- **A — keep GLM.** Prefill speed is what makes an agentic session feel usable, and one
  wasted turn in three is tolerable when turns are cheap.
- **B — make Muse the default.** Best coder, zero runaways, cheapest in tokens; accept
  the 43 s door charge and 2.6× slower decode. **W15 has now priced this option finally:**
  the DFlash drafter — the one lever that could have lifted 26 tok/s — engages and makes the
  model *worse* (decode −15 %, prefill +21 %, prefix reuse destroyed, concurrency
  serialized), so 26 tok/s is what this option costs, permanently. See
  [Try the DFlash drafter on Muse Glimmer](15-dflash-drafter-muse.md).
- **C — make Bonsai the default.** Middle on capability, recovers best of the three from
  feedback, and by far the smallest resident footprint at 8.44 GB.
- **D — keep GLM but fix its runaways first.** The 4/12 `finish_reason: length` rate may
  be a settings problem, not a capability one — no reasoning pin has ever been tried on
  it (see the map's fog on per-model thinking pins). Measure with a pin, then re-decide.

### Related

- [Measure coding capability across the three profiles](14-capability-comparison.md) —
  the measurement, its method and its limits.
- [Decide the roster now that Bonsai prefills at ~200 tok/s](13-roster-after-prefill.md) —
  established that TTFT gates the **default** specifically, and that the door charge is
  per visit.
- [Buy prefill headroom for GLM](17-glm-prefill-headroom.md) — if GLM's ceiling moves,
  the trade changes.
- [Try the DFlash drafter on Muse Glimmer](15-dflash-drafter-muse.md) — closed the only
  lever on Muse's decode speed. It made things worse, so option B carries 26 tok/s as a
  fixed cost.

## Resolution

**Option B. Muse Glimmer serves bare `ai`, effective now. GLM moves to `--glm`.** The
change is made, validated and in the working tree.

### The number that decided it — minutes per solved task

The ticket framed the trade as speed against capability, and every prior number on this
map priced speed *per token*. That metric flatters a model that fails, because a wasted
turn is fast. Dividing each model's own recorded wall-clock by the tasks it actually
solved inverts the answer — computed this session from W14's stored `results-*.json`, not
re-measured:

| Model | Wall | Solved (pass@≤2) | **Min/solved** | Wall that produced nothing |
|---|---|---|---|---|
| Muse Glimmer 30B 4-bit | 38.1 min | 11 | **3.46** | 5.3 min (14%) |
| GLM 4.7 Flash 6-bit | 23.0 min | 6 | 3.83 | **18.2 min (79%)** |
| Ternary Bonsai 27B 2-bit | 32.7 min | 8 | 4.09 | 20.7 min (63%) |

**Muse decodes 2.6× slower per token and is still the cheapest per solved task.** GLM's
speed advantage does not survive its own failure rate: four runs in five bought nothing.
That is the whole decision — the rest is confirmation.

Three facts settle the runner-up and remove the ticket's stated costs:

- **Muse is *lighter* than GLM**, 18.59 GB against 22.67 GB. The swap frees ~4 GB.
- **Muse declares 65,536 against GLM's 32,768.** The default gains twice the window, and
  the "shortest usable window" objection in this ticket now describes the opt-in profile.
- **Bonsai loses on the agreed metric** (4.09) despite recovering best. Its 8.44 GB stays
  the reason to reach for it.

### The trade taken, stated plainly

Decode does not amortise. Every answer from bare `ai` is now 2.6× slower per token, for
the whole session, and the door charge on a first visit rises from ~21.8 s to 64.5 s. The
user took that knowingly, on the grounds that a wasted turn costs more than a slow one.
**Felt latency is the price; correctness is what it buys.**

### The bar GLM must clear to win the default back — registered before the run

The user chose to **switch now and let the pin compete**, rather than hold GLM while it is
measured. So the default follows the evidence in hand, and never sits still by inertia.
GLM's template accepts `enable_thinking`:

```jinja
<|assistant|>{{- '</think>' if (enable_thinking is defined and not enable_thinking) else '<think>' -}}
```

`patch-omlx-mtp.mjs` still carries the merge machinery with an empty `DESIRED` map, so the
pin costs one entry and one restart. **Four of GLM's six failures are runaways**, and it
spends 151,688 reasoning characters to produce 76,810 completion tokens, so the defect is
settings-shaped rather than obviously a capability one. Two-part bar, fixed in advance:

1. **Capability floor — GLM must solve at least 9 of 12** (pass@≤2). That is Muse's 11
   less the 2-run noise band W14 declares.
2. **Then the metric decides.** Lowest minutes per solved task takes the default. GLM
   needs roughly ≤31 min for 9 solved to beat 3.46.

The floor exists because minutes-per-solved alone rewards a model that fails fast.
**Recovery is reported, not gated** — the solved count already counts a failed repair as a
failure, so a separate gate double-counts it. A persistent 0/12 stays a recorded warning
for the `post-edit-check` loop. The run re-measures **GLM only** (~25 min against ~95 for
all three); the floor absorbs the cross-session noise, which is real, because W14 proved
oMLX ignores `do_sample` and every model samples. This is
[Measure GLM with thinking pinned off](19-glm-thinking-pin.md).

### A latent trap, found and fixed

`ai.sh` tracked the selected profile as the string `"default"`, and the GLM fail-safe for
the MLA KV patch keyed on exactly that:

```bash
if (( ! mla_patch_ok )) && [[ "$profile" == "default" ]]; then
```

A sentinel that moves with the default would have pointed that guard at **Muse** —
capping the new default at 24,576 on a patch failure while leaving GLM uncapped and
advertising 65,536 into a model oMLX rejects past ~20k. The profile is now `""` when
unset and named `glm` / `bonsai` / `muse` otherwise, so the guard names its own model.
**A swap of one line would have shipped this silently.**

### What changed

- `ai.sh` — dispatch (`*)` now resolves to `_model_muse`), new `--glm` flag with the same
  mutual-exclusion check, `--muse` kept as an explicit alias for the default, help text
  and retired-flag roster reordered, profile comments rewritten with W14's numbers, and
  the sentinel fix above.
- `opencode-mem.jsonc` — `memoryModel` fallback repointed GLM → Muse. Its own comment
  requires that value to name the default profile, and `ai.sh` overrides it per launch
  anyway via `OPENCODE_MEM_MODEL`.
- `opencode.json` — **no change needed.** Muse already declares 65,536 / 8,192.

Validated: `bash -n ai.sh`, `python3 -m json.tool opencode.json`, help renders, bare `ai`
→ Muse, `--glm` → GLM, `--bonsai` → Bonsai, `--muse` → Muse, `--glm --bonsai` errors,
`--muse --muse` does not, and `-l` still fails as retired.

### Decisions this ticket also took

- **`--muse` survives** as an explicit alias. It names a model that stays, so it is not
  the silent remap constraint 6 forbids.
- **No `AI_PROFILE` variable.** The default stays one fixed model. A per-box override
  would have let this decision go unmade.
- **The LM Studio fallback carries no weight** — the user drives opencode almost always.
  An `ai.sh`-owned `lms load` helper is now out of scope; W9's provider block stays.
- **The summarizer question is raised, not answered.** `OPENCODE_MEM_MODEL` now pins
  opencode-mem's summarizer to a 26 tok/s VLM. Pinning it to Bonsai instead is newly
  possible on memory (18.59 + 8.44 + 8 GB hot tier ≈ 35 GB against a 40.8 GB soft
  threshold) but that figure is calculated, not measured, and a second resident model is
  the exact thrash `OPENCODE_MEM_MODEL` exists to prevent. Carried as
  [Decide the summarizer model now the default decodes at 26 tok/s](20-summarizer-model.md).

### Limits

The deciding metric rests on **12 runs per model on prompts averaging 1,502 tokens and
peaking at 4,740**. It measures decode, not prefill. In a real 12–25k agentic context
GLM's prefill lead is larger than this table shows, and the door-charge gap is a fixed
~43 s per visit that no amount of solving amortises away. Nothing here measures
long-context capability, which is where Muse is structurally weakest — 131,072 native,
only 13 of 52 layers seeing all of it.
