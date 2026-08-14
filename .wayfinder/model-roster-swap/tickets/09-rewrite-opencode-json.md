---
id: W9
title: Rewrite opencode.json — both the mlx and lmstudio providers
map: model-roster-swap
labels: [wayfinder:task]
status: closed
assignee: claude
blocked_by: [W1, W5, W6, W7, W12, W13, W16]
---

## Question

Declare exactly the three models under the `mlx` provider, and mirror them under the
`lmstudio` provider.

### `mlx` provider

Replace all four current entries with the three new ones. Each keeps
`"temperature": false`, so opencode omits the option and oMLX falls back to the
model's own `generation_config.json`.

Context is **65,536 / 8,192 output for all three**, flat, so the first comparison is
single-variable. Raising it per model is deferred to the fog, gated on the prefill
transient rather than KV size.

The model **keys must be the ids oMLX actually serves** — that is, the on-disk
`<org>/<repo>` path, not LM Studio's display id. `lms ls` shows `zai-org/glm-4.7-flash`
but the directory is `lmstudio-community/GLM-4.7-Flash-MLX-6bit`. W1 records the
authoritative pairs. Getting this wrong breaks `-m mlx/<id>`, because `mlx` is a
custom `@ai-sdk/openai-compatible` provider with no models.dev entry, so a model
resolves only while its entry exists.

### `lmstudio` provider

It **stays**, and it declares the models with the same context limits as their `mlx`
twins, so the same model can be A/B'd across both runtimes. Its current entries
(`macaw-mlx`, `meta/muse-glimmer`) are both wrong and go. Use the ids LM Studio's own
OpenAI endpoint serves on port 1234.

**It declares fewer than three. [W10](10-remove-muse-gguf.md) killed the Muse Glimmer
row:** LM Studio's MLX runtime carries mlx_vlm 0.6.5, which has no `muse_glimmer`
module, so `lms load muse-glimmer-30b` fails outright — and W10 deleted the GGUF that
was its only other route. Muse Glimmer is **oMLX-only**; do not declare it here.

Whether GLM and Bonsai survive is
[Verify which roster models actually load in LM Studio](16-lmstudio-load-check.md),
which now blocks this ticket and hands over a verdict table. Take that table as
authoritative and **declare only the models that load and answer** — W10 proved LM
Studio indexes models it cannot run, so a declaration made from `lms ls` alone is a
guess.

Note the working tree also reformatted the `smart-coding` MCP command onto multiple
lines. That is cosmetic; keep or revert deliberately, do not leave it as an accident.

### Leave alone

- `"model": "vercel/alibaba/qwen3.8-max"` — the cloud default for a bare `opencode`.
- `disabled_providers`, `permission`, `mcp`, `compaction`.
- The `@advisor` path, which is not declared here at all.

### Validate

`python3 -m json.tool opencode.json >/dev/null`, then `opencode agent list` to
confirm agents and model references still resolve.

## Resolution

**Done. `mlx` declares the three, `lmstudio` declares two, and both halves are proved on
the wire and end to end — but the block needed a lever this ticket did not name.**

Method, raw bodies and the paired control: [assets/w9-opencode-json](../assets/w9-opencode-json/).

### 1. What the file now declares

| Provider | Key | Context / output | Extra |
|---|---|---|---|
| `mlx` | `lmstudio-community/GLM-4.7-Flash-MLX-6bit` | 32,768 / 8,192 | — |
| `mlx` | `prism-ml/Ternary-Bonsai-27B-mlx-2bit` | 65,536 / 8,192 | — |
| `mlx` | `mlx-community/Muse-Glimmer-30B-4bit` | 65,536 / 8,192 | — |
| `lmstudio` | `zai-org/glm-4.7-flash` | 32,768 / 8,192 | `options.stop` |
| `lmstudio` | `prism-ml/bonsai-27b` | 65,536 / 8,192 | — |

Every row keeps `"temperature": false`. The context numbers are **not** the flat 65,536
this ticket asked for: [W12](12-glm-context-cap.md) settled GLM at 32,768, and
[W13](13-roster-after-prefill.md) kept 65,536 for the other two. The `mlx` numbers match
`DESIRED` in `scripts/patch-omlx-mtp.mjs` exactly, which pins each model's safety rail one
4,096-token block above its declared budget.

### 2. The `stop` list reaches the wire, and it works

A stub OpenAI-compatible server on port 1234 recorded the body opencode sends. A model's
`options` object is spread verbatim into the request:

```json
{ "model": "zai-org/glm-4.7-flash", "max_tokens": 8192,
  "stop": ["<|user|>", "<|observation|>"], "tool_choice": "auto", "stream": true }
```

`temperature` is absent, as `"temperature": false` intends. The Bonsai row sends no
`stop`. All three `mlx` rows send their two-level id unchanged with `max_tokens: 8192`.

The mechanism, read from the opencode 1.18.16 bundle: model `options` become
`providerOptions.lmstudio`, and openai-compatible's `getArgs` spreads every key not in
its own options schema into the body — after `stop`, so a declared `stop` wins. **Any
body parameter the endpoint understands can be declared per model this way.**

Then the paired control, on one GLM load, one parameter apart:

| Run | `stop` | `max_tokens` | finish_reason | tokens | content |
|---|---|---|---|---|---|
| control | none | 300 | **length** | 299 | `SHARING OK<\|user\|>thought: The user wants me to…` |
| declared | the pair | 8192 | **stop** | 115 | `SHARING OK` |

So W16's fault is live on this box and the declaration removes it. End to end through
opencode: GLM answered `SHARING OK` in 35.0 s, Bonsai in 53.3 s, each including a cold
prefill of the full agentic prompt with 17 tools. Loads reproduced W16 — GLM 10.26 s /
22.68 GiB, Bonsai 5.74 s / 7.94 GiB.

### 3. The lever this ticket missed — `lmstudio` is a built-in provider

`~/.cache/opencode/models.json` already carries an `lmstudio` provider with
`qwen/qwen3-coder-30b`, `qwen/qwen3-30b-a3b-2507` and `openai/gpt-oss-20b`. A
`provider.lmstudio.models` block **extends** that roster; it does not replace it. Written
as this ticket describes, `opencode models` listed **five** LM Studio rows — three of them
models this box does not hold, each a dead pick in the picker. `whitelist` fixes it:

```json
"whitelist": ["zai-org/glm-4.7-flash", "prism-ml/bonsai-27b"]
```

The listing is now exactly the declared five across both providers. The `mlx` provider
needs no whitelist, because models.dev has no `mlx` entry — which is also why deleting
its rows would break `-m mlx/<id>`, as this ticket warns.

### 4. `limit.context` never reaches LM Studio

It is the client's budget only. LM Studio fixes context at **load** time, and a bare
`lms load zai-org/glm-4.7-flash` failed every turn in about two seconds with *"The number
of tokens to keep from the initial prompt is greater than the context length"* — opencode's
system prompt plus 17 tools already exceeds the default. `--context-length 32768` fixed
it. So the cross-runtime A/B needs a load-time flag that **nothing in this repo owns**,
next to the symlinks the map's fog already records.

### 5. Decisions taken on the ticket's open points

- **The multi-line `smart-coding` command stays.** It matches the `chrome-devtools` block
  below it and `python3 -m json.tool` accepts either form. Kept deliberately, not by
  accident.
- **The top-level `"model"` is left untouched, and it is not what this ticket names.** The
  working tree reads `zai/glm-5.2`, not `vercel/alibaba/qwen3.8-max`. The user changed it;
  it is the cloud default for a bare `opencode` and no business of the local roster.
  **CLAUDE.md still documents the Vercel gateway — [W11](11-rewrite-claude-md.md) owns that.**
- **Base URL moved to `127.0.0.1`** for the `lmstudio` block, matching `mlx` and the
  built-in entry, so no `localhost` IPv6 resolution can surprise it.

### 6. For W11, beyond the roster tables

`ai.sh` carries a stale comment beside the degraded-context overlay: *"the
max_context_window pin in model_settings.json still reads 65,536 here."* It reads 36,864
for GLM since W12. The code is correct; the comment is not.

### 7. Validation run

`python3 -m json.tool opencode.json` passes. `opencode agent list` resolves all eight
agents, `advisor (subagent)` included. `opencode models` lists the five declared rows and
nothing else. LM Studio was left with no model loaded and its server stopped; oMLX stayed
down throughout.
