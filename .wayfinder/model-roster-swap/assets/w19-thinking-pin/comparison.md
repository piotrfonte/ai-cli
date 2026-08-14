## GLM, thinking on vs off

| Run | T1 tool chain | T2 merge | T3 bash | T4 extend | pass@1 | pass@<=2 |
|---|---|---|---|---|---|---|
| GLM control (thinking on) | 1 1 1 | 1 1 P | P P F | F 1 P | **6/12** | **6/12** |
| GLM pinned (thinking off) | 1 1 1 | F F F | F F F | F 2 F | **3/12** | **4/12** |

## Cost

| Run | Wall | Completion tokens | Reasoning chars | Runaways | Recoveries | min/solved |
|---|---|---|---|---|---|---|
| GLM control (thinking on) | 23.0 min | 76,810 | 151,688 | 4/12 | 0/12 | **3.83** |
| GLM pinned (thinking off) | 1.9 min | 6,897 | 0 | 0/12 | 1/12 | **0.47** |

## Against the pre-registered bar

- **Floor** — needs >= 9/12 solved: got **4/12** -> FAIL
- **Speed** — needs <= 3.46 min/solved: got **0.47** -> PASS

**Verdict: GLM DOES NOT TAKE the default back.**

The floor is checked first and it is the binding one: the speed number is not reached unless the capability floor is cleared.

## Roster, min/solved

| Model | Wall | Solved | min/solved |
|---|---|---|---|
| GLM, thinking off | 1.9 min | 4/12 | **0.47** |
| Muse Glimmer (default) | 38.1 min | 11/12 | **3.46** |
| GLM, thinking on | 23.0 min | 6/12 | **3.83** |
| Bonsai | 32.7 min | 8/12 | **4.09** |

## Verdict changes, task by task

- **T1_tool_chain** — on: `1 1 1` -> off: `1 1 1`
- **T2_merge_module** — on: `1 1 P` -> off: `F F F`
- **T3_bash_prune** — on: `P P F` -> off: `F F F`
- **T4_extend_no_regress** — on: `F 1 P` -> off: `F 2 F`

## Failure detail, pinned run

- `T2_merge_module`[0] -> **fail** — FAIL A2 two-level key written -> {"lmstudio-community/GLM-4.7-Flash-MLX-6bit":{},"GLM-4.7-Flash-MLX-6bit":{}} A3 leaf key written -> {"lmstudio-community/GLM-4.7-Flash-MLX-6bit":{},"GLM-4.7-Flash-MLX-6bit":{}} A4 changed is true on create -> false D2 new key a
- `T2_merge_module`[1] -> **fail** — FAIL A5 version defaults to 1
- `T2_merge_module`[2] -> **fail** — FAIL F1 changed true on differing value -> false
- `T3_bash_prune`[0] -> **fail** — FAIL oldest block 'block one' survived second-oldest 'block two' survived over-deleted: 'block three' is gone over-deleted: newest 'block four' is gone (started at 400 KB with four 100 KB blocks; budget 250 KB)
- `T3_bash_prune`[1] -> **fail** — bash -n failed: /private/tmp/claude-501/-Users-p-Development-ai-cli/81e346af-d8c2-4528-b1be-4c32f6c93805/scratchpad/w19/suite/lmstudio-community_GLM-4.7-Flash-MLX-6bit/T3_bash_prune-1/fn.sh: line 7: syntax error near unexpected token `(' /private/tmp/claude-50
- `T3_bash_prune`[2] -> **fail** — FAIL oldest block 'block one' survived second-oldest 'block two' survived directory is still 400 KB, over the 250 KB budget (started at 400 KB with four 100 KB blocks; budget 250 KB) find: -printf: unknown primary or operator
- `T4_extend_no_regress`[0] -> **fail** — FAIL A2 filters severity 1 and unedited files, sorted by file then line -> b.js:9:no-undef,b.js:3:eqeqeq,a.js:5:no-undef A3 message carried through -> {"file":"b.js","line":9,"rule":"no-undef","message":"undef b9"} B1 parse errors first within a file, unedited
- `T4_extend_no_regress`[1] -> **pass@2** — PASS
- `T4_extend_no_regress`[2] -> **fail** — file:///private/tmp/claude-501/-Users-p-Development-ai-cli/81e346af-d8c2-4528-b1be-4c32f6c93805/scratchpad/w19/suite/lmstudio-community_GLM-4.7-Flash-MLX-6bit/T4_extend_no_regress-2/mod.mjs:31 return a.file.localeCompare(b.file); ^ TypeError: Cannot read prope
