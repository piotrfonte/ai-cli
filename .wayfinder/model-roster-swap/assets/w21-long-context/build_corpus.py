#!/usr/bin/env python3
"""W21 Stage 1 — build the load-bearing corpus and report its size per tokenizer.

The corpus is real source from this repo, concatenated in a fixed order with one
header line per file. Nothing is generated, planted or paraphrased: an agentic
session holds exactly this kind of text, and a fact retrieved from it is a fact
the model read rather than one it invented.

  python3 build_corpus.py            # write corpus.txt, print token counts
  python3 build_corpus.py --sizes    # print counts only, write nothing

File order is chosen for DEPTH SPREAD, not for realism of ordering: two small
files at the head and one at the tail bracket the large one in the middle, so a
needle can sit at ~2 %, ~10 %, ~30 %, ~50 %, ~70 % and ~92 % of the window.
"""

import argparse
import os
import sys

REPO = os.path.abspath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "..")
)

# Fixed order. Do not reorder without re-deriving every needle depth.
FILES = [
    "opencode.json",
    "scripts/patch-omlx-mtp.mjs",
    "ai.sh",
    "plugins/post-edit-check.js",
]

MODELS = {
    "muse": "mlx-community/Muse-Glimmer-30B-4bit",
    "glm": "lmstudio-community/GLM-4.7-Flash-MLX-6bit",
    "bonsai": "prism-ml/Ternary-Bonsai-27B-mlx-2bit",
}


def build():
    parts = []
    for rel in FILES:
        with open(os.path.join(REPO, rel), encoding="utf-8") as fh:
            body = fh.read()
        parts.append(f"===== FILE: {rel} =====\n{body}\n")
    return "".join(parts)


def token_counts(text):
    from transformers import AutoTokenizer

    out = {}
    for tag, repo_id in MODELS.items():
        path = os.path.expanduser(f"~/.omlx/models/{repo_id}")
        tok = AutoTokenizer.from_pretrained(path, trust_remote_code=True)
        out[tag] = len(tok.encode(text, add_special_tokens=False))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sizes", action="store_true")
    args = ap.parse_args()

    corpus = build()
    here = os.path.dirname(os.path.abspath(__file__))
    if not args.sizes:
        with open(os.path.join(here, "corpus.txt"), "w", encoding="utf-8") as fh:
            fh.write(corpus)

    print(f"chars: {len(corpus)}")
    for rel in FILES:
        off = corpus.index(f"===== FILE: {rel} =====")
        print(f"  {off / len(corpus) * 100:5.1f}%  {rel}")
    for tag, n in token_counts(corpus).items():
        print(f"tokens[{tag}]: {n}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
