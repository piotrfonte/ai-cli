#!/usr/bin/env python3
"""Flip the DFlash settings block for Muse Glimmer on or off.

oMLX reads ~/.omlx/model_settings.json at MODEL LOAD, so a change needs a server
restart. Keys are written under BOTH the two-level id and the bare directory leaf:
oMLX resolves a request to the leaf and keys settings by it, so a two-level-only
entry is silently never consulted (the bug that made MTP inert for weeks).

Non-destructive: it touches only the dflash_* keys, and leaves every other model
and every other key alone -- including max_context_window, and anything the oMLX
admin panel set.

Usage: set-dflash.py on|off [--no-quant]
"""
import json
import os
import sys

PATH = os.path.expanduser(os.environ.get("OMLX_MODEL_SETTINGS",
                                         "~/.omlx/model_settings.json"))
IDS = ["mlx-community/Muse-Glimmer-30B-4bit", "Muse-Glimmer-30B-4bit"]
DRAFTER = "meta-models/Muse-Glimmer-30B-assistant"
DFLASH_KEYS = ("dflash_enabled", "dflash_draft_model", "dflash_draft_quant_enabled",
               "dflash_draft_quant_weight_bits", "dflash_draft_quant_activation_bits",
               "dflash_draft_quant_group_size")


def main() -> int:
    mode = sys.argv[1] if len(sys.argv) > 1 else "off"
    quant = "--no-quant" not in sys.argv[2:]
    if mode not in ("on", "off"):
        print(__doc__)
        return 2

    with open(PATH) as f:
        data = json.load(f)
    models = data.setdefault("models", {})

    for model_id in IDS:
        entry = models.setdefault(model_id, {})
        for key in DFLASH_KEYS:
            entry.pop(key, None)
        if mode == "on":
            entry["dflash_enabled"] = True
            entry["dflash_draft_model"] = DRAFTER
            # True alone yields w4a16:gs64 from DFlashEngine._build_quant_spec's own
            # fallbacks -- the registry's w4 for this model, asked for explicitly
            # because engine_pool never consults the registry default.
            entry["dflash_draft_quant_enabled"] = quant

    with open(PATH, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")

    print(f"dflash {mode}" + (" (drafter unquantized, BF16)" if mode == "on" and not quant else ""))
    for model_id in IDS:
        print(f"  {model_id}: {json.dumps(models[model_id], sort_keys=True)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
