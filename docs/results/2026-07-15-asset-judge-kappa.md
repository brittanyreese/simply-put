# Judge calibration: quadratically-weighted kappa vs. ASSET human ratings

Date: 2026-07-15. Judge: `anthropic/claude-haiku-4.5` via OpenRouter.
Labels: 100 ASSET pairs (Alva-Manchego et al. 2020, `ratings` config),
every complete (original, simplification) pair in the release. Each pair
carries 15 worker ratings per aspect on a 0-100 scale. The pivot script
(`scripts/pivot_asset_labels.py`) takes the per-aspect mean and buckets
it into quintiles (1-5), mapping ASSET's meaning-preservation aspect to
this repo's fidelity axis. The raw data stays out of the repo (CC BY-NC
4.0). The script reproduces the CSV from the public release.

## Result (quadratically-weighted Cohen's kappa, n=100)

| axis | kappa | Landis-Koch reading |
|------|-------|---------------------|
| fidelity | 0.765 | substantial |
| fluency | 0.722 | substantial |
| simplicity | 0.223 | fair |

The `moderate_judge_human_kappa` gate requires >= 0.41 on every axis, so
this is a FAIL, driven entirely by the simplicity axis.

## Reading

The judge tracks human raters closely on whether meaning survived and
whether the output reads as fluent English. It diverges on what counts
as *simpler*. That is consistent with the rest of this repo's design:
simplicity is the axis the pipeline never asks the judge to decide,
because the deterministic Flesch-Kincaid gate owns it (ADR-0002). On
this evidence that division of labor is more than a design preference.
The judge would be the wrong tool for the one job it was never given.

## Caveats

- ASSET is general-domain English, not medical text. Domain-relevant
  calibration (PLABA TREC per-item judgments) is still open.
- Bucketing the mean of 15 workers into quintiles and comparing against
  a single judge rating attenuates kappa. Part of the simplicity gap may
  be construct mismatch between ASSET's "is this simpler?" instruction
  and the judge rubric's 1-5 simplicity scale.
- Only one judge model and one prompt were tested, and neither the
  position-swap nor the verbosity-bias check has run on this subset yet
  (`SimplyPut.JudgeValidation` has both tests).
