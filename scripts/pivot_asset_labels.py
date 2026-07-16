#!/usr/bin/env python3
"""Pivot ASSET's raw human-ratings JSON into the wide CSV
SimplyPut.HumanLabels.Import expects.

Source: facebook/asset, config "ratings" (HuggingFace datasets-server),
one row per (original, simplification, aspect, worker). Fetched via
https://datasets-server.huggingface.co/rows?dataset=facebook%2Fasset&config=ratings&split=full
(paginated, 4500 rows total) and saved as a JSON array of records with
keys: original, simplification, original_sentence_id, aspect (int:
0=meaning, 1=fluency, 2=simplicity -- per the dataset's ClassLabel
order), worker_id, rating (int, 0-100).

Pivot logic:
  1. Group records by (original, simplification) text pair.
  2. Mean the 0-100 rating per aspect within each pair.
  3. Keep only pairs that have all 3 aspects rated (meaning, fluency,
     simplicity) -- a pair with a missing aspect can't fill all three
     required score columns.
  4. Map aspects to the importer's columns: meaning -> fidelity,
     fluency -> fluency, simplicity -> simplicity.
  5. Bucket each mean 0-100 score into an integer 1-5 (the importer
     requires ints): 0-20 -> 1, 21-40 -> 2, 41-60 -> 3, 61-80 -> 4,
     81-100 -> 5. Five equal-width buckets over the 0-100 scale.
  6. item_id = "asset_" + sha1(original + simplification)[:12], so
     re-running the pivot on the same source data is deterministic.
  7. annotator = "asset_worker_mean" (scores are an average across
     workers, not a single annotator's rating).
  8. Sample: sort by item_id, take the first 150 -- deterministic and
     cheap to reproduce without a random seed. Caps judge-call cost.

Usage:
    python3 pivot_asset_labels.py <input.json> <output.csv> [--limit 150]
"""

import argparse
import csv
import hashlib
import json
import sys
from collections import defaultdict

ASPECT_NAMES = {0: "meaning", 1: "fluency", 2: "simplicity"}
ASPECT_TO_COLUMN = {"meaning": "fidelity", "fluency": "fluency", "simplicity": "simplicity"}
CSV_COLUMNS = ["item_id", "original", "simplification", "simplicity", "fidelity", "fluency", "annotator"]


def bucket(score):
    """Map a 0-100 mean rating to an integer 1-5 bucket."""
    if score <= 20:
        return 1
    if score <= 40:
        return 2
    if score <= 60:
        return 3
    if score <= 80:
        return 4
    return 5


def pivot(records):
    groups = defaultdict(lambda: defaultdict(list))
    for rec in records:
        aspect = ASPECT_NAMES.get(rec["aspect"])
        if aspect is None:
            continue
        key = (rec["original"], rec["simplification"])
        groups[key][aspect].append(rec["rating"])

    rows = []
    for (original, simplification), by_aspect in groups.items():
        if not all(a in by_aspect for a in ("meaning", "fluency", "simplicity")):
            continue
        means = {ASPECT_TO_COLUMN[a]: sum(v) / len(v) for a, v in by_aspect.items()}
        item_id = "asset_" + hashlib.sha1((original + simplification).encode("utf-8")).hexdigest()[:12]
        rows.append({
            "item_id": item_id,
            "original": original,
            "simplification": simplification,
            "simplicity": bucket(means["simplicity"]),
            "fidelity": bucket(means["fidelity"]),
            "fluency": bucket(means["fluency"]),
            "annotator": "asset_worker_mean",
        })

    rows.sort(key=lambda r: r["item_id"])
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("input_json", help="Path to the raw ASSET ratings JSON (list of records)")
    parser.add_argument("output_csv", help="Path to write the pivoted wide CSV")
    parser.add_argument("--limit", type=int, default=150, help="Max rows to keep (default: 150)")
    args = parser.parse_args()

    with open(args.input_json, encoding="utf-8") as f:
        records = json.load(f)

    rows = pivot(records)
    print(f"pairs with all 3 aspects rated: {len(rows)}", file=sys.stderr)

    sample = rows[: args.limit]

    with open(args.output_csv, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=CSV_COLUMNS)
        writer.writeheader()
        writer.writerows(sample)

    print(f"wrote {len(sample)} rows to {args.output_csv}", file=sys.stderr)


if __name__ == "__main__":
    main()
