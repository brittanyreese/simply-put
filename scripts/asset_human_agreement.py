#!/usr/bin/env python3
"""Inter-annotator (human-human) agreement on ASSET's raw worker ratings.

The judge-vs-human kappa gate reads simplicity at 0.24 and calls it a fail.
That number is only interpretable against the human-human ceiling: if humans
agree on simplicity about as poorly, 0.24 is near the ceiling, not a judge
defect. The pivot that built `human_labels` averaged the 15 workers per pair
into one score, discarding exactly the signal needed to compute that ceiling.
This reads the raw ratings and computes it.

Krippendorff's alpha (interval), not pairwise Cohen: ASSET's workers are not a
fixed panel (different worker sets per pair), so alpha is the right tool -- it
handles any number of raters and missing data (deep-dive 3.1). Computed on the
raw 0-100 scale and on the same 1-5 buckets the judge kappa used, so the
simplicity comparison is apples-to-apples.

Usage: python3 asset_human_agreement.py <asset_ratings.json>
"""

import json
import sys
from collections import defaultdict

ASPECT_NAMES = {0: "meaning/fidelity", 1: "fluency", 2: "simplicity"}


def bucket(score):
    # Same five equal-width buckets as scripts/pivot_asset_labels.py.
    if score <= 20:
        return 1
    if score <= 40:
        return 2
    if score <= 60:
        return 3
    if score <= 80:
        return 4
    return 5


def krippendorff_alpha_interval(units):
    """units: list of lists, each inner list = the values one item got from
    its raters. Interval metric (squared difference); quadratic, so it matches
    the judge's quadratically-weighted kappa disagreement metric."""
    # Keep only units rated by >= 2 raters (a lone rating is not pairable).
    units = [u for u in units if len(u) >= 2]
    n = sum(len(u) for u in units)  # total pairable values
    if n < 2:
        return None

    # Observed disagreement.
    do_sum = 0.0
    for u in units:
        m = len(u)
        pair_sum = 0.0
        for i in range(m):
            for j in range(m):
                if i != j:
                    pair_sum += (u[i] - u[j]) ** 2
        do_sum += pair_sum / (m - 1)
    do = do_sum / n

    # Expected disagreement over the full multiset of values.
    allvals = [v for u in units for v in u]
    s1 = sum(allvals)
    s2 = sum(v * v for v in allvals)
    # sum_{c,k}(a_c-a_k)^2 over ordered pairs = 2*(n*S2 - S1^2)
    de = (2.0 * (n * s2 - s1 * s1)) / (n * (n - 1))
    if de == 0:
        return 1.0
    return 1.0 - do / de


def _self_check():
    # Perfect agreement -> alpha 1.
    assert abs(krippendorff_alpha_interval([[1, 1], [5, 5]]) - 1.0) < 1e-9
    # Hand-computed: units [1,2],[4,5]. do=1.0, de=80/12=6.667, alpha=1-1/6.667.
    a = krippendorff_alpha_interval([[1, 2], [4, 5]])
    assert abs(a - (1.0 - 1.0 / (80.0 / 12.0))) < 1e-9, a
    # All raters identical across everything but one flip -> still high.
    assert krippendorff_alpha_interval([[3, 3, 3], [3, 3, 3]]) == 1.0


def main():
    _self_check()
    path = sys.argv[1]
    with open(path) as f:
        rows = json.load(f)

    # Group ratings by (aspect, item) -> list of worker ratings.
    raw = defaultdict(lambda: defaultdict(list))
    buck = defaultdict(lambda: defaultdict(list))
    workers = defaultdict(set)
    for r in rows:
        a = r["aspect"]
        key = (r["original"], r["simplification"])
        raw[a][key].append(r["rating"])
        buck[a][key].append(bucket(r["rating"]))
        workers[a].add(r["worker_id"])

    print(f"records={len(rows)}")
    for a in sorted(ASPECT_NAMES):
        units_raw = list(raw[a].values())
        units_buck = list(buck[a].values())
        raters = [len(u) for u in units_raw]
        alpha_raw = krippendorff_alpha_interval(units_raw)
        alpha_buck = krippendorff_alpha_interval(units_buck)
        print(
            f"aspect={ASPECT_NAMES[a]:16s} items={len(units_raw)} "
            f"raters/item~{min(raters)}-{max(raters)} distinct_workers={len(workers[a])} "
            f"alpha_raw0_100={alpha_raw:.3f} alpha_1_5buckets={alpha_buck:.3f}"
        )


if __name__ == "__main__":
    main()
