# W13 asset — does a growing conversation re-pay the cold prefill?

Measurement that resolved
[Decide the roster now that Bonsai prefills at ~200 tok/s](../../tickets/13-roster-after-prefill.md).

## The question

W6 measured Bonsai's cold prefill at 194 tok/s, giving 66.2 s on a 12.8k-token turn.
The ticket read that as the cost of a turn. It is the cost of a **visit**: turn 2 of an
agentic conversation is a strict extension of turn 1, so the paged cache may match the
prefix and prefill only the new tokens. Nobody had measured which.

## Method

`omlx 0.5.8.dev3`, ai.sh's flags (hot 8 GB, SSD ≤25 GB, guard 48, concurrency 2),
MCP-free. The KV cache was pruned to 5 GB first, and each run carries a unique nonce in
its first message, so turn 1 is genuinely cold.

**Every request uses `max_tokens: 1`, so wall time is prefill alone.** Never subtract
decode from the server log line — builds report `tok/s` differently.

- `measure-run1-large-append.py` — turn 1, then two ~9k-token appends, then a repeat of
  turn 1. Proved the prefix-extension hit and the warm restore.
- `measure-run2-real-append.py` — turn 1, then appends of ~480 and ~1920 tokens, the
  size a real tool result carries. Gives the per-turn cost.

Reproduce with the server up on port 10081:

```bash
python3 measure-run2-real-append.py "w13-$(date +%s)"
```

## Result

| Turn | Prompt | Cached | Fresh | Time |
|---|---|---|---|---|
| 1 — cold | 12,840 | 0 | 12,840 | 58.63 s |
| 2 — small tool result | 13,687 | 12,288 | 1,399 | 7.40 s |
| 3 — 2k tool result | 17,115 | 12,288 | 4,827 | 24.24 s |
| 4 — 2k tool result | 20,543 | 16,384 | 4,159 | 22.51 s |
| 5 — small tool result | 21,390 | 20,480 | 910 | 5.45 s |
| repeat of turn 1 | 12,840 | 12,288 | — | 3.18 s |

The cache hits on extension. The door charge is paid once per visit. Each later turn
prefills its fresh tokens at the model's ordinary ~190 tok/s.

**`cached_tokens` rounds down to a 2048-token block.** That is why turn 2 charges 1,399
fresh tokens for a ~500-token append — up to ~2k tokens of already-seen prefix are
re-prefilled every turn. Budget for it when estimating a turn.

Nothing spilled to the SSD tier at these sizes; the 8 GB hot tier absorbed it.
