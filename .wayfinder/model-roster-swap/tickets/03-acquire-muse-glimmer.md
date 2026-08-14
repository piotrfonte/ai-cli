---
id: W3
title: Get Muse Glimmer 30B 4-bit MLX into the LM Studio store
map: model-roster-swap
labels: [wayfinder:task]
status: closed
assignee: claude
blocked_by: []
---

## Question

Is `mlx-community/Muse-Glimmer-30B-4bit` on disk, in LM Studio's store, in the flat
`<org>/<repo>` layout the rest of the map assumes?

**HITL.** The user downloads models by hand in LM Studio; `ai.sh` no longer downloads
anything. This ticket hands over a precise instruction and then verifies the result.

### Steps

1. Fetch `mlx-community/Muse-Glimmer-30B-4bit` (~17 GB) in LM Studio.
   - The `mxfp4` sibling exists and is **not** what we want. Confirm the 4-bit repo.
   - `pipenetwork/Muse-Glimmer-30B-MLX-4bit` and `RadixArk/Muse-Glimmer-q4-MLX` are
     third-party mirrors. Prefer `mlx-community`.
2. Confirm it lands under `~/.cache/huggingface/hub/mlx-community/Muse-Glimmer-30B-4bit`
   and that `lms ls` reports it.
3. Record its arch string, real on-disk size, and whether LM Studio treats it as a
   VLM.

### Watch for

If LM Studio refuses the repo or writes it somewhere else, **stop and record that**
— the fallback is a decision, not a substitution to make on the spot. It would put
the sharing mechanism from W1 under strain, and sharing is a blocker.

### Disk

59 GB free before this download; the Muse GGUF is not deleted until W10, so the
download must fit without it. It does.

## Resolution

**Done. The download finished at 22:24 on 2026-08-11, complete and correct.** W1 caught
this ticket mid-flight, with shard 3 of 4 still a `.part` file. It is now whole. LM
Studio wrote it exactly where the map assumes, so the sharing mechanism from W1 needs
no strain and no fallback decision.

### The three checks

1. **Right repo, right quant.** `mlx-community/Muse-Glimmer-30B-4bit`, not a mirror
   and not the mxfp4 sibling. `config.json` reports
   `quantization: {bits: 4, group_size: 64, mode: affine}` — the flat 4-bit affine
   quant the ticket asked for.
2. **Right place.** `~/.cache/huggingface/hub/mlx-community/Muse-Glimmer-30B-4bit`,
   in the flat `<org>/<repo>` layout, matching GLM and Bonsai. `lms ls` lists it.
3. **Complete.** All 4 shards present, no `downloading_*.part` file anywhere in the
   store. The shards sum to **19.41 GB** against the index's declared
   `total_size: 19414521856` — an exact match inside safetensors header overhead.
   2278 tensors across the 4 shards.

```
$ lms ls
You have 4 models, taking up 52.41 GB of disk space.

LLM                                  PARAMS    ARCH             SIZE        DEVICE
muse-glimmer-30b                     30B       muse_glimmer     19.44 GB    Local
prism-ml/bonsai-27b (1 variant)      27B       qwen3_5           8.52 GB    Local
zai-org/glm-4.7-flash (1 variant)    30B       glm4_moe_lite    24.36 GB    Local
```

### Recorded facts

| | |
|---|---|
| `model_type` | `muse_glimmer` |
| `architectures` | `MuseGlimmerForConditionalGeneration` |
| oMLX served id / settings leaf key | `Muse-Glimmer-30B-4bit` |
| On disk | 19.41 GB (`lms ls` says 19.44 GB) |
| Quant | 4-bit affine, group size 64 |
| Text side | 52 layers, hidden 6656, **2 KV heads**, head_dim 128 |
| Native window | 131,072 |
| Vision | `vision_config` present; **815 of 2278 tensors** are vision/adapter |

**LM Studio treats it as an LLM, not a VLM** — `lms ls` groups it under `LLM` with no
vision marker, despite the vision tower. oMLX disagrees and is right: W2 confirms
`muse_glimmer` is in the target's `VLM_MODEL_TYPES`, so oMLX routes it to
`VLMBatchedEngine`.

Note the config carries **no `language_model_only` key at all**, where Bonsai sets it
explicitly to `False`. Do not read the absence as "text only" — 815 vision tensors are
in the checkpoint and will load.

### For W7

- **KV is cheap, close to GLM's.** 2 KV heads × 128 head_dim × 52 layers ⇒ ~52
  KB/token at fp16, so ~**3.4 GB at 65 k**. As the map already argues for this model,
  the risk is the prefill transient and the dense 30B forward pass, not KV size.
- **The oMLX symlink does not exist yet.** `~/.omlx/models/mlx-community/` holds only
  the three dangling links to departed models (Gemma, two Qwen quants). W8 owns
  creating the Muse link. W7 does not have to wait for it: W1 established that oMLX
  also scans `~/.cache/huggingface/hub` on its own, because
  `~/.omlx/settings.json` sets `huggingface.hf_cache_enabled: true`, and Muse Glimmer
  was already visible to oMLX by that route while still downloading.
- **W2 raises a load-correctness hazard that lands squarely on this artifact.** oMLX
  vendors mlx-vlm PR #1839's `QuantizedNormedEmbedding`; without it, quantizing
  `embed_tokens` silently drops the weightless `embed_norm` and logits collapse. This
  is a quantized checkpoint, so W7 must serve it on the **upgraded oMLX as a whole**
  and never on a hand-bumped mlx-vlm.

### Disk, worse than this ticket assumed

The ticket was written against 59 GB free and noted the download would fit without
deleting the GGUF. It did. But free space is now **13 GiB at 99% full**, not the 35 GB
W1 measured, because these 19.41 GB landed. Deleting the Muse GGUF (W10) recovers 17 GB
and is now the largest single reclaim available — still correctly blocked on W7.
