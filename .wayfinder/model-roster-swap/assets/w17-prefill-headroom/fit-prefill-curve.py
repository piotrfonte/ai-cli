#!/usr/bin/env python3
"""Fit the prefill cost curve and find each model's two-minute door charge.

W17 asks whether more memory headroom buys GLM more usable context. It does not.
Prefill cost grows as O(n^2), so a time budget caps context long before memory
does. This script shows that from measurements already on the map — it starts no
server and sends no request.

Model: t(n) = a*n + b*n^2
  a*n   — the linear pass over the prompt (matmuls, MoE routing)
  b*n^2 — attention

Two measured points fix a and b. Further measured points then TEST the fit: a rung
that costs much more than the fit predicts is the prefill throttle engaging, which
is a memory effect. A rung on the curve is running at its natural rate, where extra
memory can buy nothing.

Sources:
  GLM  — assets/w12-mla-kv-cap/README.md (ladder, max_tokens: 1, fresh nonce per rung)
  Muse — ticket 07 (12,882 tokens in 64.5 s; 65,536 tokens in 6 m 54 s)

Run: python3 fit-prefill-curve.py
"""

from __future__ import annotations

import math

BUDGET_SECONDS = 120.0  # the user's stated limit for a cold open of one big file


def fit(p1: tuple[int, float], p2: tuple[int, float]) -> tuple[float, float]:
    """Solve t = a*n + b*n^2 through two (tokens, seconds) points."""
    (n1, t1), (n2, t2) = p1, p2
    # t1/n1 = a + b*n1 ; t2/n2 = a + b*n2  ->  b from the difference
    b = (t2 / n2 - t1 / n1) / (n2 - n1)
    a = t1 / n1 - b * n1
    return a, b


def predict(a: float, b: float, n: int) -> float:
    return a * n + b * n * n


def tokens_for_budget(a: float, b: float, seconds: float) -> float:
    """Largest n with t(n) <= seconds. Positive root of b*n^2 + a*n - seconds."""
    disc = a * a + 4 * b * seconds
    return (-a + math.sqrt(disc)) / (2 * b)


def report(name: str, anchors, tests, note: str = "") -> None:
    a, b = fit(*anchors)
    print(f"\n{name}")
    print(f"  fit from {anchors[0][0]:,} and {anchors[1][0]:,} tokens")
    print(f"  a = {a:.4e} s/token      b = {b:.4e} s/token^2")
    if tests:
        print(f"  {'prompt':>10}  {'predicted':>10}  {'measured':>10}  {'ratio':>7}")
        for n, t in tests:
            p = predict(a, b, n)
            print(f"  {n:>10,}  {p:>9.1f} s  {t:>9.1f} s  {t / p:>6.2f}x")
    n_budget = tokens_for_budget(a, b, BUDGET_SECONDS)
    print(f"  door charge of {BUDGET_SECONDS:.0f} s lands at ~{n_budget:,.0f} tokens")
    if note:
        print(f"  note: {note}")


if __name__ == "__main__":
    print(f"Two-minute budget = {BUDGET_SECONDS:.0f} s cold, first token.")

    # GLM 4.7 Flash 6-bit. Anchors are the two rungs below the throttle; the two
    # test rungs were never seen by the fit.
    report(
        "GLM 4.7 Flash 6-bit (glm4_moe_lite)",
        anchors=((10256, 18.83), (24592, 75.17)),
        tests=[(32783, 116.00), (40976, 266.09)],
        note="ratio ~1.0 = natural rate; ratio >>1 = prefill throttle",
    )

    # Muse Glimmer 4-bit, the default profile. Only two measurements exist, so both
    # are anchors and the fit has no test point. The 65,536 rung may itself be
    # throttled, which would make b too large and the budget figure pessimistic.
    report(
        "Muse Glimmer 30B 4-bit (default profile)",
        anchors=((12882, 64.5), (65536, 414.0)),
        tests=[],
        note="two points, no test rung — indicative only",
    )

    print("\nGLM declares 32,768 (W12). That was chosen on memory grounds.")
    print("It lands within ~1.5% of the two-minute boundary by accident.")
