# ASSET human-human agreement: a ceiling for the simplicity gate

The judge-vs-human kappa gate fails on simplicity (0.24) and passes on
fidelity (0.77) and fluency (0.70). A bare fail is not interpretable on its
own. A judge cannot be held to an agreement level that humans themselves do
not reach on the same axis. This card computes the human-human ceiling ASSET
supports, so the 0.24 can be read against it rather than against a naive 1.0.

The `human_labels` table cannot answer this: the pivot that built it
(`scripts/pivot_asset_labels.py`) averaged the 15 workers per pair into one
score, leaving one annotator per item and no way to measure inter-annotator
agreement. This reads ASSET's raw ratings directly
(`scripts/asset_human_agreement.py`, run over `.scratch/asset/asset_ratings.json`,
not committed, CC BY-NC).

## Method

100 (original, simplification) pairs, each rated 0-100 on three aspects by
15 workers (31 distinct workers across the set), 4,500 ratings total. Agreement
is Krippendorff's alpha with the interval metric, the right estimator here
because the workers are not a fixed panel (the deep-dive's 3.1 names alpha for
a variable rater set). The interval metric squares rating differences, the same
disagreement shape as the judge's quadratically-weighted Cohen's kappa, so the
1-5 bucketed column below is the closest apples-to-apples comparison. The
estimator carries a hand-computed self-check (`_self_check`) that runs on every
invocation.

## Results

| aspect | human-human alpha (0-100) | human-human alpha (1-5 buckets) | judge-vs-human kappa |
|--------|---------------------------|---------------------------------|----------------------|
| fidelity (meaning) | 0.587 | 0.563 | 0.77 |
| fluency | 0.561 | 0.562 | 0.70 |
| simplicity | 0.435 | 0.429 | 0.24 |

Judge-vs-human kappa is from the n=300 card
([`2026-07-22-med-easi-full-split-sle-significance.md`](2026-07-22-med-easi-full-split-sle-significance.md)).

## Reading

Two findings, and they pull in opposite directions, so state both.

First, simplicity is the hardest axis for humans too. Its human-human alpha
(0.43) is well below fidelity and fluency (about 0.56 each), because people
agree less about whether a rewrite is simpler than about whether it kept the
meaning or reads fluently. That belongs to the construct rather than the judge,
and it is why this repo lets the deterministic FK gate own simplicity (ADR-0002).
Bucketing does not explain the gap, since raw and 1-5 alpha agree to within
0.01 per aspect.

Second, the judge is still weaker on simplicity, not merely sitting at a low
ceiling. On fidelity and fluency the judge (0.77, 0.70) scores *above* the
human-human alpha (0.56, 0.56), which is expected rather than flattering: the
judge is scored against the mean of 15 workers, a denoised target that is
easier to match than any single human is to match another. Yet on simplicity
the judge (0.24) falls *below* even the human-human floor (0.43), despite that
same denoising advantage. The low number is not fully absorbed by "simplicity
is subjective." The residual gap, 0.24 against a 0.43 ceiling, is the real
result.

In one line, the judge tracks meaning and fluency better than humans track each
other, and simplicity worse. The gate fail is not a scoring artifact, but its
severity was overstated by comparing 0.24 to 1.0 instead of to 0.43.

## Bearing on the gate

- It does not move the gate. Simplicity still fails against the 0.41 Landis-Koch
  threshold, and the FK gate still owns that axis by design.
- It does change the story attached to the fail: the ceiling for this axis is
  about 0.43, not the 0.7-plus the other two axes reach, and the judge's
  shortfall is a roughly 0.19 gap below the human bar, not a 0.76 gap below a
  perfect one.
- A stricter follow-up, if wanted: compute judge-vs-human with the same
  Krippendorff estimator (treating the judge as one more rater) so the two
  columns use one method end to end. The Cohen-vs-Krippendorff mismatch is small
  at these rater counts but is a real caveat on the head-to-head.
