# Full-split eval card: Med-EASi canonical test split (n=300)

Batch `8fd22f93-2c25-403b-8eeb-a6bb7aa58961`, run 2026-07-15 (CDT).
Rewriter: `openai/gpt-4o-mini`. Judge: `anthropic/claude-haiku-4.5`
(cross-vendor, ADR-0003), both via OpenRouter. Metrics ran on the
Bumblebee provider (`METRIC_PROVIDER=bumblebee`), so faithfulness and
omission are real NLI entailment scores. All 300 items of the canonical test split ran under
each of the three modes. Reprint the card any time with
`mix simply_put.eval --report 8fd22f93-2c25-403b-8eeb-a6bb7aa58961`
(the kappa gate makes about 100 paid judge calls per reprint).

The original process died at 780 of 900 rows when the EXLA application
crashed mid-run. A resume script filled in the 120 missing self_refine
items under the same batch id. Rows are written independently per item,
so the crash cost wall-clock time and nothing else.

## Results (mean over 300 items, 95% bootstrap CI where shown)

| metric | iterative | single_shot | self_refine |
|--------|-----------|-------------|-------------|
| FK grade | 7.03 (6.75-7.33) | 8.38 (7.97-8.79) | 7.04 (6.72-7.36) |
| grade <= 8 compliance | 72.7% | 51.0% | 74.3% |
| faithfulness (source to candidate) | 0.886 | 0.927 | 0.893 |
| omission (candidate to source) | 0.891 | 0.932 | 0.899 |
| BERTScore F1 | 0.998 | 0.998 | 0.998 |
| SARI | 0.401 | 0.403 | 0.393 |

## Gate outcomes

| gate | result | detail |
|------|--------|--------|
| grade_band_compliance | pass | iterative 72.7% at FK <= 8 (target 50%) |
| bounded_omission | pass | iterative omission CI lower 0.872 (target 0.70) |
| moderate_judge_human_kappa | fail | simplicity 0.21, fidelity 0.77, fluency 0.68 (target >= 0.41 on every axis) |

Dominance (ADR-0005), grade compliance and faithfulness kept apart:

| iterative vs | grade | faithfulness | relation |
|--------------|-------|--------------|----------|
| single_shot | 72.7% > 51.0% | 0.886 < 0.927 | tradeoff |
| self_refine | 72.7% < 74.3% | 0.886 < 0.893 | iterative_dominated |

## Reading

The deterministic gate still owns the grade axis. Both gated modes land
at 7th grade and clear the 8th-grade ceiling 72.7% and 74.3% of the time.
Ungated single_shot sits at 8.4 and clears it 51.0% of the time, a higher
baseline than the bounded card's 23% because the full split contains many
easier items. Against single_shot the relation stays a tradeoff: the gate
buys 21.7 points of compliance for 0.041 of faithfulness.

The full split settles the question the bounded card left open, and the
answer cuts against the pipeline's own favorite mode. self_refine edges
iterative on both axes, by 1.6 points of compliance and 0.007 of
faithfulness, margins that sit inside overlapping CIs. The honest summary
is parity: external tool feedback shows no measurable advantage over
model self-critique on this corpus with this model pairing. A blended
verdict would have buried that. Separate axes surface it.

The kappa gate repeats the finding from the calibration card
(`2026-07-15-asset-judge-kappa.md`). Judge-human agreement is substantial
on fidelity and fluency but only fair on simplicity, the axis the
deterministic gate owns rather than the judge. The per-axis figures are a
live re-score of the ASSET set (about 100 judge calls) and drift by roughly
plus or minus 0.03 between reprints, so the exact number differs from the
other cards' reprints. The ordering (simplicity weakest) is what holds.

## Caveats

- SLE is nil throughout. The `liamcripwell/sle-base` tokenizer will not
  load in Bumblebee, so the metric degrades to nil by design.
- BERTScore sits near 0.998 for every mode and barely discriminates.
- The dominance relation compares point estimates. No significance test
  backs the self_refine edge, and the overlapping CIs say it may be zero.
- The parity result is tied to this exact generator and judge pairing
  and to the current feedback prompt. A stronger generator or a different
  prompt could move it.
