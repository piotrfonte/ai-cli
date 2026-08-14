# Upstream report (written, not filed)

For [jundot/omlx](https://github.com/jundot/omlx). W17 decided to report the defect
rather than patch it locally, because the repo already carries one patch against oMLX's
source and `max_context_window` already neutralises the symptom. **The user decides
whether to file this.**

---

**Title:** Prefill admission charges a throttled-chunk transient, so a cold prefill can
abort mid-run against the physical Metal cap

**Version:** `0.5.8.dev3`, tag `v0.5.8.dev3` (`350dc08b`), `mlx 0.32.0`
**Hardware:** Apple M4 Max, 64 GiB, macOS 27.0
**Model:** `lmstudio-community/GLM-4.7-Flash-MLX-6bit` (`glm4_moe_lite`, 47 layers, MLA)

## Summary

`Scheduler._admission_estimate` prices a prompt with the transient of a **floor-size**
chunk (`_prefill_min_chunk_tokens`, 256), but prefill *starts* at
`prefill_step_size` (2048) and only shrinks after the throttle engages. On the first
large prefill after a model load the throttle has never run, so the real transient is a
2048-token chunk transient — up to an order of magnitude larger than what admission
charged. The request is admitted and then aborts against the physical cap, costing
several minutes and unloading the model.

## Observed

A 45,072-token prompt on an idle server, model already resident (~23 GB):

```
Memory pressure level: ok -> hard (current=48.1GB, soft=40.8GB, hard=45.6GB)
Prefill force-stopped at 20608 tokens: memory 50.3GB exceeds physical cap 50.3GB
Unloading model: GLM-4.7-Flash-MLX-6bit (immediate abort)   freed=36.13GB
```

Admission had quoted **`KV+SDPA 1.55 GB`** for this request. The real transient passed
**14 GB**. The prompt was admitted, ran for about five minutes, then aborted and took
the loaded model with it.

A 40,976-token prompt on the same server succeeds, but only because the throttle wins a
race: it pauses the request, evicts pooled Metal buffers and resumes at a smaller chunk.
It costs 266 s against ~182 s predicted from the same model's un-throttled curve.

## Cause

`scheduler.py:8833`:

```python
if self._prefill_speed_priority:
    charge_tokens = max(1, int(self.config.prefill_step_size))
else:
    charge_tokens = max(1, self._prefill_min_chunk_tokens)   # 256
```

and `_admission_transient_bound` (`scheduler.py:3626`) floors that charge with
`_prefill_transient_tracker.observed_max_bytes` — deliberately built from
**floor-size samples only**. Its docstring states the assumption:

> big-chunk transients differ by an order of magnitude on some models (Qwen3.6: ~3GB at
> 2048 tokens) and belong to the throttle, which shrinks chunks long before admission's
> charge is relevant.

The assumption fails in one specific state: a **cold** server, where no floor-size
sample exists yet and the throttle has never engaged. There the charge is a prediction
for a 256-token chunk, while the prefill actually runs 2048-token chunks from its first
step. Admission is using the throttled steady state — a **lower** bound on the peak — as
if it were an upper bound.

The `_prefill_speed_priority` branch already prices the un-throttled regime correctly.
The bug is that the cold, not-yet-throttled regime takes the other branch.

## Suggested fix

Charge `prefill_step_size` whenever the session has no floor-size transient sample yet,
falling back to the current floor-chunk charge once the throttle has actually engaged
and the tracker holds real samples. That reuses the branch above rather than adding a
new estimator, and it keeps the gemma-4 result the current behaviour was tuned for
(80k rejected while 60k completed at 32-token chunks), because by then samples exist.

## Workaround

Pin `max_context_window` per model in `model_settings.json` below the size that aborts.
`validate_context_window` (`server.py:1618`) runs on the tokenized prompt before
scheduling, so an oversized prompt is rejected in **1.67 s** with HTTP 400 instead of
running for five minutes and unloading the model.

## Note on a second, opposite defect

We reached this by fixing the inverse error. `estimate_mla_kv_bytes_per_token` returns
early at `if cache_list is None`, because `mlx_lm/models/glm4_moe_lite.py` defines no
`make_cache`, so the scheduler leaves `cache_list_for_tq` at `None`
(`scheduler.py:11580`). MLA KV was therefore charged with the MHA formula:
**~374 KB/token against a real 52.9** — a factor of 7.08. oMLX's own vendored
`glm_moe_dsa` model does define `make_cache`, so GLM-5.2 is unaffected.

That over-count was masking the under-count reported here: it rejected these prompts
cleanly, for the wrong reason. We correct it locally by deriving the layer count from
the config when `cache_list is None`, which is exact for `glm4_moe_lite` because it is
uniform full attention. Happy to send that as a separate patch if it is wanted.
