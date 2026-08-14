## Per-task verdicts

`1` = pass@1  ·  `2` = pass@2 (one repair)  ·  `F` = fail  ·  `P` = protocol failure

| Model | T1 tool chain | T2 merge module | T3 bash repair | T4 extend, no regress | pass@1 | pass@≤2 |
|---|---|---|---|---|---|---|
| GLM-4.7-Flash-MLX-6bit | 1 1 1 | 1 1 P | P P F | F 1 P | **6/12** | **6/12** |
| Ternary-Bonsai-27B-mlx-2bit | 1 1 1 | 1 P 2 | F P F | 2 2 1 | **5/12** | **8/12** |
| Muse-Glimmer-30B-4bit | 1 1 1 | 1 1 1 | 2 F 2 | 1 1 1 | **9/12** | **11/12** |

## Cost, recorded but not scored

| Model | Samples? | Runs | Wall | Completion tokens | Reasoning chars | Runaways |
|---|---|---|---|---|---|---|
| GLM-4.7-Flash-MLX-6bit | yes | 12 | 23.0 min | 76,810 | 151,688 | 4/12 |
| Ternary-Bonsai-27B-mlx-2bit | yes | 12 | 32.7 min | 50,919 | 107,639 | 2/12 |
| Muse-Glimmer-30B-4bit | yes | 12 | 38.1 min | 42,097 | 155,252 | 0/12 |

## Failure detail

**GLM-4.7-Flash-MLX-6bit**

- `T2_merge_module`[2] → **protocol_fail** — hit max_tokens before finishing
- `T3_bash_prune`[0] → **protocol_fail** — hit max_tokens before finishing
- `T3_bash_prune`[1] → **protocol_fail** — hit max_tokens before finishing
- `T3_bash_prune`[2] → **fail** — FAIL oldest block 'block one' survived second-oldest 'block two' survived directory is still 512 KB, over the 250 KB budget (started at 512 KB with four 100 KB blocks; budget 250 KB) find: -printf: unknown primary or operator
- `T4_extend_no_regress`[0] → **fail** — FAIL A2 filters severity 1 and unedited files, sorted by file then line A3 message carried through B1 parse errors first within a file, unedited file contributes only its parse error B3 only the severity-2 parse error appears for an unedite
- `T4_extend_no_regress`[2] → **protocol_fail** — hit max_tokens before finishing

**Ternary-Bonsai-27B-mlx-2bit**

- `T2_merge_module`[1] → **protocol_fail** — hit max_tokens before finishing
- `T2_merge_module`[2] → **pass@2** — PASS
- `T3_bash_prune`[0] → **fail** — FAIL over-deleted: 'block three' is gone over-deleted: newest 'block four' is gone the cache directory itself was destroyed (started at 512 KB with four 100 KB blocks; budget 250 KB)
- `T3_bash_prune`[1] → **protocol_fail** — hit max_tokens before finishing
- `T3_bash_prune`[2] → **fail** — FAIL oldest block 'block one' survived second-oldest 'block two' survived directory is still 512 KB, over the 250 KB budget (started at 512 KB with four 100 KB blocks; budget 250 KB) du: : No such file or directory du: : No such file or dir
- `T4_extend_no_regress`[0] → **pass@2** — PASS
- `T4_extend_no_regress`[1] → **pass@2** — PASS

**Muse-Glimmer-30B-4bit**

- `T3_bash_prune`[0] → **pass@2** — FAIL over-deleted: 'block three' is gone (started at 512 KB with four 100 KB blocks; budget 250 KB)
- `T3_bash_prune`[1] → **fail** — FAIL oldest block 'block one' survived second-oldest 'block two' survived directory is still 512 KB, over the 250 KB budget (started at 512 KB with four 100 KB blocks; budget 250 KB)
- `T3_bash_prune`[2] → **pass@2** — FAIL over-deleted: 'block three' is gone (started at 512 KB with four 100 KB blocks; budget 250 KB)

