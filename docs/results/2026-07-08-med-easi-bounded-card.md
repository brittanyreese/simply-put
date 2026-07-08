# Bounded eval card: Med-EASi canonical test split (n=30)

First non-simulated run of the harness. Real metric providers, not the
stub: OpenRouter generates and judges, Bumblebee scores faithfulness,
omission, and BERTScore natively. Thirty items from Med-EASi's own
`test.csv`, each run under all three modes.

- Generator: `openai/gpt-4o-mini`
- Judge: `anthropic/claude-haiku-4.5`
- Faithfulness / omission: `FacebookAI/roberta-large-mnli` (NLI both directions)
- BERTScore: `FacebookAI/roberta-large` base encoder
- Corpus: the Med-EASi `test` split (300 items), first 30 by id

## Results (mean over 30 items)

| metric | iterative | single_shot | self_refine |
|--------|-----------|-------------|-------------|
| FK grade | 7.36 | 10.27 | 7.49 |
| grade <= 8 compliance | 70% | 23% | 77% |
| faithfulness (source to candidate) | 0.838 | 0.866 | 0.818 |
| omission (candidate to source) | 0.838 | 0.867 | 0.817 |
| BERTScore F1 | 0.996 | 0.998 | 0.998 |
| SARI | 0.438 | 0.413 | 0.436 |

## Gate outcomes

| gate | result | detail |
|------|--------|--------|
| grade_band_compliance | pass | iterative 70% at FK <= 8 (target 50%) |
| bounded_omission | pass | iterative omission CI lower 0.767 (target 0.70) |
| moderate_judge_human_kappa | fail | 0.0 on every axis, no human labels loaded |

Iterative against the controls is not a gate. It is a two-axis tradeoff,
reported as a dominance relation (ADR-0005):

| iterative vs | grade | faithfulness | relation |
|--------------|-------|--------------|----------|
| single_shot | 0.70 > 0.23 | 0.838 < 0.866 | tradeoff |
| self_refine | 0.70 < 0.77 | 0.838 > 0.818 | tradeoff |

## Reading

The grade result supports the thesis. The two modes with a deterministic
readability gate (iterative, self_refine) land near 7th grade and clear the
8th-grade ceiling 70 to 77 percent of the time. Ungated single_shot sits at
10th grade and clears it 23 percent of the time. The tool-feedback loop is
what moves grade.

Iterative dominates neither control at this sample size. Against single_shot
it wins grade by a wide margin and gives up a little faithfulness, because
single_shot barely edits and stays at 10th grade. Against self_refine the two
trade in the other direction, and self_refine is the stronger rival on grade.
So the sharp claim the review cares about, that external feedback beats
self-critique, comes out unproven at this sample size rather than settled. A
blended gate would have hidden that. Separate axes show it.

The kappa failure is an artifact. No `human_labels` rows are loaded, so
`judge_vs_human_kappa` returns zero.

## Caveats

- n=30. CIs are wide (iterative FK runs 6.65 to 8.04).
- SLE is nil throughout. The `liamcripwell/sle-base` checkpoint carries a
  tokenizer Bumblebee cannot load, so the metric degrades to nil by design.
- BERTScore sits near 0.997 for every mode and barely discriminates, as
  mean-pooled roberta embeddings tend to.

## Open work before a full 300-item run

Done since this card: the `iterative_beats_controls` gate is retired in favor
of the `dominance/1` relation above (ADR-0005). Remaining:

1. Acquire ASSET or PLABA human ratings to make the kappa gate real. Needs a
   long-to-wide pivot and a rating-scale mapping (ASSET rates on a 0 to 100
   scale, and `human_labels` validates 1 to 5), plus paid judge calls over the
   labeled subset.
2. Run the full test split, where the three gates and the dominance relation
   carry meaning and the CIs tighten.
