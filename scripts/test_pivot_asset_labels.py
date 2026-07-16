#!/usr/bin/env python3
"""Minimal self-check for pivot_asset_labels.py. Run: python3 scripts/test_pivot_asset_labels.py"""

from pivot_asset_labels import bucket, pivot

assert bucket(0) == 1
assert bucket(20) == 1
assert bucket(21) == 2
assert bucket(60) == 3
assert bucket(61) == 4
assert bucket(100) == 5

records = [
    {"original": "A", "simplification": "a", "aspect": 0, "rating": 90},
    {"original": "A", "simplification": "a", "aspect": 1, "rating": 50},
    {"original": "A", "simplification": "a", "aspect": 2, "rating": 10},
    # missing simplicity aspect -> dropped
    {"original": "B", "simplification": "b", "aspect": 0, "rating": 90},
    {"original": "B", "simplification": "b", "aspect": 1, "rating": 50},
]
rows = pivot(records)
assert len(rows) == 1
row = rows[0]
assert row["fidelity"] == 5   # mean 90 -> bucket 5
assert row["fluency"] == 3    # mean 50 -> bucket 3
assert row["simplicity"] == 1  # mean 10 -> bucket 1
assert row["annotator"] == "asset_worker_mean"
assert row["item_id"].startswith("asset_")

print("ok")
