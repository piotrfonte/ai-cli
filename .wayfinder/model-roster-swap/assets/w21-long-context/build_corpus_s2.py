#!/usr/bin/env python3
"""W21 Stage 2 — build the coding-suite corpus, and prove it leaks no answer.

  python3 build_corpus_s2.py

Stage 2 CANNOT re-use Stage 1's corpus.txt. The W14 tasks are drawn from this
repository's real code, and Stage 1's corpus is this repository's real code, so
putting them together hands the model the answers:

  * T2 asks for `mergeModelSettings`. The real scripts/patch-omlx-mtp.mjs is that
    merge, both key spellings and all.
  * T4 asks for `blockingErrors`. The real plugins/post-edit-check.js is that logic.
  * T1 serves three scripts/* files through tools, in a SIMULATED form carrying a
    planted decoy. The real versions of those paths would contradict them.

So four files are excluded by name, and `verify()` then proves by string search
that no task's answer identifier survives anywhere in the corpus. A quiet leak here
would inflate Stage 2 against W14 and void the comparison, which is the whole point
of the run.

Stage 2's corpus is also SMALLER than Stage 1's, and deliberately. Stage 1 sent one
turn; these tasks are multi-turn, and the conversation grows on top of the corpus.
GLM's real client budget is 32,768 with 8,192 reserved for output, so the corpus is
sized to leave room for the whole exchange rather than only the first prompt.
"""

import os
import sys

REPO = os.path.abspath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "..")
)

# Fixed order.
FILES = [
    "opencode.json",
    "ai.sh",
]

# Excluded by name, with the reason. Do not add any of these back.
EXCLUDED = {
    "scripts/patch-omlx-mtp.mjs": "T1 simulates this path; and it IS T2's answer",
    "scripts/patch-opencode-mem-cap.mjs": "T1 simulates this path (holds its decoy)",
    "scripts/patch-smart-coding-excludes.mjs": "T1 simulates this path",
    "plugins/post-edit-check.js": "it IS T4's answer",
}

# Any of these appearing in the corpus means an answer leaked.
FORBIDDEN = [
    "applyDesired",        # T1's answer
    "mergeSettings",       # T1's decoy
    "mergeModelSettings",  # T2's answer
    "blockingErrors",      # T4's answer
]

MODELS = {
    "muse": "mlx-community/Muse-Glimmer-30B-4bit",
    "glm": "lmstudio-community/GLM-4.7-Flash-MLX-6bit",
    "bonsai": "prism-ml/Ternary-Bonsai-27B-mlx-2bit",
}


def build():
    parts = []
    for rel in FILES:
        assert rel not in EXCLUDED, f"{rel} is on the exclusion list"
        with open(os.path.join(REPO, rel), encoding="utf-8") as fh:
            parts.append(f"===== FILE: {rel} =====\n{fh.read()}\n")
    return "".join(parts)


def verify(corpus):
    """Fail loudly rather than measure a contaminated run."""
    bad = [t for t in FORBIDDEN if t in corpus]
    if bad:
        print(f"CONTAMINATED: corpus contains {bad}", file=sys.stderr)
        return False
    for rel in EXCLUDED:
        if f"FILE: {rel}" in corpus:
            print(f"CONTAMINATED: corpus includes excluded {rel}", file=sys.stderr)
            return False
    return True


def token_counts(text):
    from transformers import AutoTokenizer

    out = {}
    for tag, repo_id in MODELS.items():
        tok = AutoTokenizer.from_pretrained(
            os.path.expanduser(f"~/.omlx/models/{repo_id}"), trust_remote_code=True
        )
        out[tag] = len(tok.encode(text, add_special_tokens=False))
    return out


def main():
    corpus = build()
    if not verify(corpus):
        return 1

    here = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(here, "corpus-s2.txt"), "w", encoding="utf-8") as fh:
        fh.write(corpus)

    print(f"clean. chars: {len(corpus)}")
    counts = token_counts(corpus)
    for tag, n in counts.items():
        print(f"tokens[{tag}]: {n}")
    worst = max(counts.values())
    print(f"\nworst-case corpus: {worst}")
    print(f"GLM budget 32768 - output 8192 = 24576 for prompt")
    print(f"headroom for the growing conversation: {24576 - worst} tokens")
    return 0


if __name__ == "__main__":
    sys.exit(main())
