# Full-split eval card: Med-EASi test split (n=300), SLE + significance

Batch `a227fe3e-4440-431b-85f0-e703bf949916`, run 2026-07-22 (CDT).
Rewriter: `openai/gpt-4o-mini`. Judge: `anthropic/claude-haiku-4.5`
(cross-vendor, ADR-0003), both via OpenRouter. Metrics ran on the
Bumblebee provider (`METRIC_PROVIDER=bumblebee`), so faithfulness,
omission, and SLE are real model inference. All 300 items of the
canonical test split ran under each of the three modes. Reprint with
`mix simply_put.eval --report a227fe3e-4440-431b-85f0-e703bf949916`
(the kappa gate makes about 100 paid judge calls per reprint).

This card supersedes the 2026-07-15 card
([`2026-07-15-med-easi-full-split.md`](2026-07-15-med-easi-full-split.md))
on two axes that were caveats there and are resolved here:

- **SLE is now populated.** The `liamcripwell/sle-base` tokenizer would not
  load before; it needs `roberta-base`'s tokenizer, not `sle-base`'s own
  (the model is a RoBERTa-base fine-tune). SLE now discriminates: the gated
  modes read simpler than ungated single_shot.
- **The dominance edge now carries a paired significance test.** Each
  iterative-minus-control difference reports a 95% paired bootstrap CI and
  whether it excludes zero, so the self_refine parity is demonstrated, not
  asserted.

This run also exercised, for the first time, the `mix simply_put.eval`
Bumblebee path end to end; the 2026-07-15 card was produced from `iex`.
That surfaced and fixed a latent bug: the task booted only `:ecto_sql`, so
the first checkpoint download crashed on Bumblebee's `:httpc_bumblebee`
profile. The task now starts `:inets`/`:ssl`/`:exla`/`:bumblebee` for a
real run.

## Results (mean over 300 items, 95% bootstrap CI where shown)

| metric | iterative | single_shot | self_refine |
|--------|-----------|-------------|-------------|
| FK grade | 7.12 (6.83-7.43) | 8.43 (8.03-8.79) | 7.17 (6.86-7.50) |
| grade <= 8 compliance | 69.0% | 47.7% | 70.7% |
| faithfulness (source to candidate) | 0.889 (0.868-0.908) | 0.930 (0.913-0.945) | 0.889 (0.868-0.909) |
| omission (candidate to source) | 0.901 | 0.931 | 0.898 |
| SLE (simplicity) | 2.17 (2.06-2.28) | 1.79 (1.65-1.92) | 2.12 (2.00-2.24) |
| SARI | 0.400 | 0.403 | 0.398 |

BERTScore F1 is omitted from the table as a documented null. See below.

## Gate outcomes

| gate | result | detail |
|------|--------|--------|
| grade_band_compliance | pass | iterative 69.0% at FK <= 8 (target 50%) |
| bounded_omission | pass | iterative omission CI lower 0.882 (target 0.70) |
| moderate_judge_human_kappa | fail | simplicity 0.24, fidelity 0.77, fluency 0.70 (target >= 0.41 on every axis) |

## Dominance (ADR-0005), grade and faithfulness kept apart, with significance

| iterative vs | grade | faithfulness | relation | grade diff (95% CI) | faithfulness diff (95% CI) |
|--------------|-------|--------------|----------|---------------------|----------------------------|
| single_shot | 69.0% > 47.7% | 0.889 < 0.930 | tradeoff | +0.213 (0.163 to 0.263), clears zero | -0.040 (-0.060 to -0.022), clears zero |
| self_refine | 69.0% < 70.7% | 0.889 ~ 0.889 | tradeoff | -0.017 (-0.057 to 0.023), spans zero | +0.001 (-0.018 to 0.018), spans zero |

## Reading

The deterministic gate still owns the grade axis. Both gated modes sit at
7th grade and clear the 8th-grade ceiling 69.0% and 70.7% of the time,
against 47.7% for ungated single_shot. SLE agrees: the gated modes score
higher simplicity (2.17, 2.12) than single_shot (1.79), an independent
model-based signal pointing the same way as FK.

Against single_shot the relation is a real tradeoff, and now with backing:
the gate buys 21.3 points of grade compliance (CI 16.3 to 26.3, excludes
zero) for 0.040 of faithfulness (CI -0.060 to -0.022, excludes zero). Both
differences clear zero, so the tradeoff is not an artifact of sampling.

Against self_refine the paired test settles what point estimates could not.
Neither the grade difference (-1.7 points, CI crosses zero) nor the
faithfulness difference (+0.001, CI crosses zero) is distinguishable from
zero. External tool feedback shows no measurable advantage over model
self-critique on this corpus with this model pairing. The "tradeoff" label
is a point-estimate artifact. The honest reading is parity. A blended
verdict would have buried this. Separate axes plus a paired test surface it.

The kappa gate repeats the calibration finding: judge-human agreement is
substantial on fidelity (0.77) and fluency (0.70), only fair on simplicity
(0.24), the axis the deterministic gate owns rather than the judge. These
per-axis figures are a live re-score of the ASSET set (about 100 judge calls),
so they drift by roughly plus or minus 0.03 between reprints. The ordering
(simplicity weakest) is stable. The exact number is not a fixed reference.

## Memory footprint (Phase M)

All four checkpoints loaded in-process (SummaC `roberta-large-mnli`,
BERTScore `roberta-large`, SLE `sle-base`, QAFactEval `t5-base` question-gen
+ `roberta-base-squad2` extraction) plus the EXLA runtime peak at about
**4.8 GB resident (RSS)** on CPU. `:erlang.memory(:total)` reports only
96 MB, because the model tensors sit in EXLA's host allocations, outside
the BEAM heap. RSS is the number a deploy target must budget for, not the
BEAM figure. Measured 2026-07-22 with a one-item iterative run after a warm
(cached) checkpoint load.

## BERTScore: a documented null

BERTScore F1 reads 0.998 for all three modes (95% CI 0.998 to 0.999), a
flat null that cannot separate them. The cause is the metric, not the
pipeline: cosine similarity between pooled sentence embeddings saturates
near 1.0 when candidate and reference share most of their content, which
every readable rewrite of a short sentence does. The metric stays wired in
the harness (`SimplyPut.MetricProvider.BertScore`, real Bumblebee
inference) so the native code still runs, but a number
that never moves belongs in a null note, not in the results table beside
the axes that discriminate.

## Caveats

- The parity result is tied to this exact generator and judge pairing and
  to the current feedback prompt. A stronger generator or a different
  prompt could move it.
- Compliance shifted a few points from the 2026-07-15 card (iterative
  72.7% -> 69.0%) because this is a fresh generation run; the qualitative
  story (gate owns grade, self_refine parity, kappa fails on simplicity) is
  unchanged.
