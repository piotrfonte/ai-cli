#!/usr/bin/env python3
"""What the drafter actually costs in memory, quantized and not.

The server never logs this: engine_pool's "Loaded model ... actual: 2.52GB" is a lazy
figure. Run with the server down.
"""
import mlx.core as mx
from omlx.patches.dflash_draft_config import install_dflash_draft_config_normalizer
from dflash_mlx.runtime.loading import load_draft_bundle

install_dflash_draft_config_normalizer()
REF = "meta-models/Muse-Glimmer-30B-assistant"

for label, spec in (("w4a16:gs64 (what W15 ran)", "w4a16:gs64"), ("unquantized BF16", None)):
    mx.clear_cache()
    before = mx.get_active_memory()
    draft, _meta = load_draft_bundle(REF, draft_quant=spec)
    mx.eval(draft.parameters())
    after = mx.get_active_memory()
    print(f"{label:<28} {(after - before) / 2**30:6.2f} GB active")
    del draft
    mx.clear_cache()
