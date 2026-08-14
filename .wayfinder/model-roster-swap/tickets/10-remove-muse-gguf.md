---
id: W10
title: Remove the Muse Glimmer GGUF
map: model-roster-swap
labels: [wayfinder:task]
status: closed
assignee: claude
blocked_by: [W7]
---

## Question

Delete `~/.lmstudio/models/lmstudio-community/Muse-Glimmer-30B-GGUF` (17 GB).

### Why it goes

It is GGUF, so oMLX can never use it — only LM Studio can. Once the MLX 4-bit copy
is in place, that one copy serves both tools, which is the whole point of the sharing
requirement. Keeping the GGUF means paying 17 GB for a duplicate of a model you
already have, against a disk that is 94% full.

### Ordering matters

This is blocked on W7 **on purpose**. Deleting first is what makes room, but it
strands the user with no working Muse Glimmer if the MLX build fails to serve. The
download fits without deleting this, so the safe order costs nothing.

Do not run this until W7 confirms the MLX copy both serves on oMLX and loads in LM
Studio.

### Contents

Two files: `muse-glimmer-30B-kquant-17gb.gguf` and `mmproj-kquant.gguf` (the
multimodal projector).

### W1 found it is already an orphan

`lms ls` reports 3 models and 32.96 GB, and it does **not** list this GGUF. LM
Studio's store is now `~/.cache/huggingface/hub`, so `~/.lmstudio/models` is a legacy
tree that LM Studio no longer indexes. The 17 GB buys nothing today, not even a
fallback inside LM Studio, which strengthens the case to delete it. Disk is 97% full
(35 GB free), not the 94% this ticket was written against.

### From W7 — the oMLX half of the precondition is met, the LM Studio half is not

W7 confirms the MLX 4-bit copy **serves on oMLX**: it passes every functional check,
calls tools, and answers at 65,536 context. It does **not** confirm the copy loads in
LM Studio — nothing was loaded there, so that half of the precondition above is still
open and belongs to whoever takes this ticket.

**Read W7 before deleting anything.** It measures Muse Glimmer at 64.5 s to first token
on a 12.8k prompt, which is the latency that removed the previous `--muse` profile, and
[Decide the roster now that Bonsai prefills at ~200 tok/s](13-roster-after-prefill.md)
may drop the model from the roster entirely. That does not reverse this ticket — a GGUF
oMLX can never read is dead weight either way — but if the roster drops Muse Glimmer,
the 19.41 GB **MLX** copy comes into question too, and that is W13's call, not this
one's.

### Confirm before deleting

This is the user's separate tool and an irreversible 17 GB delete. Confirm at the
moment of deletion, then verify `lms ls` afterwards.

## Resolution

**Deleted, with the user's confirmation at the moment of deletion — but the
precondition failed first, and it inverts half of this ticket's premise.** The GGUF is
gone because it ran **nowhere**, not because one MLX copy now serves both tools.

### The precondition failed: the MLX copy does not load in LM Studio

W7 met the oMLX half. This ticket owned the LM Studio half, and it does not hold:

```
$ lms load muse-glimmer-30b -y
ValueError: Model type muse_glimmer not supported.
Error: No module named 'mlx_vlm.speculative.drafters.muse_glimmer'
```

LM Studio **indexes** the shared copy correctly — `lms ls --json` resolves
`muse-glimmer-30b` to `mlx-community/Muse-Glimmer-30B-4bit`, safetensors, 19.44 GB —
but its MLX runtime cannot instantiate the architecture. The runtime is
`mlx-llm-mac-arm64-apple-metal-advsimd@1.11.0`, carrying **mlx_vlm 0.6.5**, whose
`models/` directory holds `bonsai`, `glm_moe_dsa`, `glm4v_moe`, `qwen3_5` and 90 more —
and **no `muse_glimmer`**. `lms runtime update` reports every selected runtime already
up to date, so no available update closes the gap.

This is the same gap [W2](02-confirm-upgrade-target.md) found: upstream mlx-vlm needs
**0.6.12** for this model, and oMLX serves it only because it **vendors** the
implementation. LM Studio has nothing to vendor from at 0.6.5.

**So weight sharing is one-directional for this model.** One copy on disk, but only
oMLX reads it. Constraint 2 is still met; constraint 10 is not, for Muse Glimmer.

### Deleting anyway — the reason changed, the answer did not

The ticket's stated case ("the MLX copy serves both tools, so the GGUF is a duplicate")
is false. The case that survives is W1's: the GGUF is an **orphan**. It sits in
`~/.lmstudio/models`, a legacy tree LM Studio no longer indexes; it appears in neither
`lms ls` nor `.internal/gguf-metadata-cache.json`. It was therefore the *only* artifact
that could ever run Muse Glimmer inside LM Studio — but only after the user re-registers
the legacy folder by hand, which had not happened in the two days it sat there.

The user was given the three options — delete, move it into the indexed store to make it
work, or keep it orphaned — and **chose delete**, accepting Muse Glimmer as oMLX-only.

### What was deleted

| Path | Size |
|---|---|
| `~/.lmstudio/models/lmstudio-community/Muse-Glimmer-30B-GGUF/muse-glimmer-30B-kquant-17gb.gguf` | 16.76 GB |
| `…/mmproj-kquant.gguf` (multimodal projector) | 1.40 GB |
| **Total** | **18.16 GB (16.9 GiB)** |

The emptied parent `lmstudio-community/` went too. `~/.lmstudio/models/` is now **empty** —
the legacy tree holds nothing.

### Post-checks

- `lms ls` is **unchanged** across the delete: 5 models, 52.47 GB, both before and
  after. That identity *is* the proof the GGUF was an orphan — LM Studio never counted it.
- Free disk did **not** move: 47 GiB, 95% full, before and after. Eleven APFS Time
  Machine local snapshots hold the space, one taken at 13:18 today, minutes before the
  delete. This is exactly the purgeable-space behaviour [W4](04-upgrade-omlx-stack.md)
  documented and constraint 11 records — macOS releases it under pressure. The 16.9 GiB
  is recovered, not lost; it is simply not yet visible in `df`.

### What this hands to W9

[Rewrite opencode.json](09-rewrite-opencode-json.md) intends to mirror all three models
under the `lmstudio` provider (constraint 10). **Muse Glimmer cannot be declared there** —
the runtime cannot load it in either format now. Bonsai and GLM are more promising: both
architectures are present in mlx_vlm 0.6.5. Neither is *proven*, though — indexing did not
predict loading for Muse Glimmer, so it cannot be trusted to predict it for them either.
That verification is now
[Verify which roster models actually load in LM Studio](16-lmstudio-load-check.md), which
blocks W9.
