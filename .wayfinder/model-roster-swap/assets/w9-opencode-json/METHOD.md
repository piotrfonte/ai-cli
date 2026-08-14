# W9 — method and raw results

## The question the wire stub answers

`opencode.json` can put an `options` object on a model entry, but the schema types it
as a bare `{"type": "object"}`. Nothing states that a key inside it reaches the HTTP
request body. W16 requires GLM to carry `stop: ["<|user|>", "<|observation|>"]` under
LM Studio, so the declaration is honest only if that key arrives on the wire.

`wire-stub.py` is a stub OpenAI-compatible server. It answers `/v1/models`, records the
exact `/v1/chat/completions` body opencode sends to `wire.json`, and returns a two-chunk
SSE reply so the turn completes. Run it on the port the provider's `baseURL` names
(1234 for `lmstudio`, 10081 for `mlx`), then run one `opencode run --model …` turn.

```bash
python3 wire-stub.py &                     # binds 127.0.0.1:1234
opencode run --model 'lmstudio/zai-org/glm-4.7-flash' 'say OK'
python3 -c "import json;print(json.load(open('wire.json')))"
```

No model loads and no weights are read, so a body check costs about two seconds.

## Result — the body opencode sends

```json
{
  "model": "zai-org/glm-4.7-flash",
  "max_tokens": 8192,
  "stop": ["<|user|>", "<|observation|>"],
  "tool_choice": "auto",
  "stream": true,
  "stream_options": { "include_usage": true }
}
```

17 tools accompanied it. `temperature` is absent, which is `"temperature": false` doing
its job. The Bonsai row, which declares no `options`, sends no `stop` key.

All three `mlx` rows were checked the same way against a stub on 10081:

| Declared key | `model` sent | `max_tokens` | `temperature` | `stop` |
|---|---|---|---|---|
| `lmstudio-community/GLM-4.7-Flash-MLX-6bit` | same | 8192 | absent | absent |
| `prism-ml/Ternary-Bonsai-27B-mlx-2bit` | same | 8192 | absent | absent |
| `mlx-community/Muse-Glimmer-30B-4bit` | same | 8192 | absent | absent |

The two-level `<org>/<repo>` id goes out unchanged, which is what oMLX's
`resolve_model_id()` needs (W1).

## Why the path works, read from the opencode 1.18.16 bundle

Two functions carry it. The first maps a model's config `options` onto a provider key:
for `npm: "@ai-sdk/openai-compatible"` the key is the provider id up to the first dot,
so `providerOptions` becomes `{ lmstudio: {...} }`. The second is the AI SDK's
`getArgs` for openai-compatible, which builds the body as

```js
{ model, max_tokens, temperature, …, stop: H, seed: L,
  ...Object.fromEntries(Object.entries({...B[this.providerOptionsName]})
      .filter(([d]) => !Object.keys(g.shape).includes(d))), … }
```

`providerOptionsName` is also `lmstudio`, and any key not in the known-options schema
`g` is spread into the body verbatim. The spread comes after `stop: H`, so a declared
`stop` wins over the SDK's own `stopSequences`. This is a general lever: any body
parameter the endpoint understands can be declared per model.

## Paired stop control, on one GLM load in LM Studio

Same load (`--context-length 32768`, 22.68 GiB), same prompt, one parameter apart:

| Run | `stop` | `max_tokens` | finish_reason | completion tokens | content |
|---|---|---|---|---|---|
| control | none | 300 | **length** | 299 | `SHARING OK<\|user\|>thought: The user wants me to confirm…` |
| declared | `["<\|user\|>","<\|observation\|>"]` | 8192 | **stop** | 115 | `SHARING OK` |

This reproduces W16's fault on the current box and shows the declaration removes it.
The control uses a 300-token cap on purpose: it exposes the runaway in about ten
seconds rather than the 291.89 s a full 8192-token cap costs.

## End to end through opencode

MCP was disabled for these runs through an `OPENCODE_CONFIG_CONTENT` overlay, because
oMLX was down and `smart-coding` embeds against it.

| Model | LM Studio load | Turn | Answer |
|---|---|---|---|
| `lmstudio/zai-org/glm-4.7-flash` | 10.26 s, 22.68 GiB | 35.0 s | `SHARING OK` |
| `lmstudio/prism-ml/bonsai-27b` | 5.74 s, 7.94 GiB | 53.3 s | `SHARING OK` |

Each turn includes a cold prefill of opencode's full agentic prompt with 17 tools.
These are not benchmarks — one sample each, at each runtime's defaults.

## Two facts the ticket did not expect

**`lmstudio` is a built-in models.dev provider.** `~/.cache/opencode/models.json` holds
an `lmstudio` entry with `qwen/qwen3-coder-30b`, `qwen/qwen3-30b-a3b-2507` and
`openai/gpt-oss-20b`. A `provider.lmstudio.models` block **extends** that roster rather
than replacing it, so `opencode models` listed five rows, three of them for models this
box does not hold. `whitelist` cuts the list to exactly the declared pair:

```
lmstudio/prism-ml/bonsai-27b
lmstudio/zai-org/glm-4.7-flash
mlx/lmstudio-community/GLM-4.7-Flash-MLX-6bit
mlx/mlx-community/Muse-Glimmer-30B-4bit
mlx/prism-ml/Ternary-Bonsai-27B-mlx-2bit
```

The `mlx` provider needs no whitelist: models.dev has no `mlx` entry, so it starts empty.

**`limit.context` never reaches LM Studio.** It is the client's budget. LM Studio fixes
context at load time, and a bare `lms load zai-org/glm-4.7-flash` produced

```
The number of tokens to keep from the initial prompt is greater than the context
length. Try to load the model with a larger context length, or provide a shorter input
```

on every turn, in about two seconds — opencode's system prompt plus 17 tools already
exceeds the default. `--context-length 32768` fixed it. So a working cross-runtime A/B
needs a load-time flag that nothing in this repo owns.

## Box state left behind

LM Studio: no model loaded, server stopped. oMLX stayed down throughout. `lms ls` now
reports **6** models — including `mlx-community/Muse-Glimmer-30B-4bit` (19.44 GB) and
the `muse_glimmer_assistant` DFlash drafter (5.11 GB) — read from the HF cache, while
`~/.lmstudio/models` still holds only the two symlinks W16 made. So the configured
`downloadsFolder` is indexed now, against W16's finding. It changes nothing for Muse:
LM Studio indexes what it cannot load (W10).
