# Methodology/Analysis/Results/Interpretation Review: Phase 1 Eval Harness

Three reviewers checked the Phase 1 evaluation harness. Each worked independently, blind to the others' notes. One covered methods (labeled "Methodology" below). Another covered domain and construct validity. The third played devil's advocate. Scope is measurement, statistical, and construct validity. Code style and Iron Laws are covered by a prior review.

Reviewed materials: `docs/plans/phase1-health-demo/plan.md`, `docs/plans/public-demo-repo/research/methodology-grounding-brief.md`, ADRs 0001-0004, `lib/simply_put/eval_runner.ex`, `lib/simply_put/stats.ex`, `lib/simply_put/judge_validation.ex`, `lib/simply_put/metric_provider.ex`.

## Decision: Major Revision

All three reviewers agree, independently, that the architecture (deterministic gate, bounded retry, dual-axis cross-vendor judge, negative controls) is well-grounded in the cited literature. The current gate outputs are not yet valid evidence, though. What's blocking that is a handful of gaps in how the gates are wired up, not a redesign.

## Consensus findings (raised by 2-3 reviewers independently)

| # | Finding | Raised by | Severity |
|---|---|---|---|
| 1 | `at_least(_, nil) → true` (`eval_runner.ex:201`): a missing/empty negative control is scored as "iterative beat it," inverting the point of a control | Methodology, Devil's Advocate | Highest, fix first |
| 2 | All 4 success gates read only the point estimate; `Stats.bootstrap_ci/3` is computed in `summary/1` and never consulted by any gate | Methodology, Devil's Advocate | High |
| 3 | Judge validated on ASSET/PLABA, deployed on Med-EASi (health domain): validity doesn't transport | Methodology, Domain, Devil's Advocate (all 3) | High |
| 4 | `faithfulness_score` = mean(SummaC entailment, QAFactEval-overlap) is a two-construct composite that two of the four gates depend on | All 3 (Domain escalates this to "anti-correlated with the task," see below) | High |
| 5 | Landis-Koch 0.41 "moderate" threshold (calibrated for unweighted nominal kappa) applied to quadratically-weighted ordinal kappa without justification | Methodology, Devil's Advocate | Medium |
| 6 | No `:metric_provider` config anywhere. `MetricProvider.Stub` populates every eval row in this environment, and two gates key on the resulting constant faithfulness value (`0.875`) | Devil's Advocate (headline finding), Domain | Critical: none of the findings above can be reported until this is fixed |

## High-value single-reviewer findings (uncontradicted, high confidence)

- Grade-band floor is backwards (Domain): the 6.0 floor in `grade_band_gate` fails rewrites for reading *below* 6th grade. AMA/CDC/NIH health-literacy guidance targets ≤6th grade, not a [6,8] band. FK and SMOG are also non-commensurate scales (SMOG typically reads 1-3 grades higher for the same passage). Requiring both jointly in a narrow 2-grade window is either near-unsatisfiable or satisfiable only by a specific surface shape.
- SummaC direction is backwards for "omission" (Domain): SummaC's premise(source)-to-hypothesis(candidate) entailment detects *additions* (hallucination), not *omissions*. Using it inside `bounded_omission_gate` doesn't match the gate's own name. A rewrite that silently drops a contraindication can still score high.
- PlainQAFact elaboration false-positive, unmitigated (Domain): both halves of `faithfulness_score` penalize legitimate elaboration (defining jargon, "this means..." clauses), which is a core behavior of good plain-language health rewriting. Already named as a risk in the plan's own risk section, never mitigated in code.
- PLABA mislabeled as general-domain (Domain): PLABA (Plain Language Adaptation of Biomedical Abstracts) is biomedical, not general-domain. Pooling it with ASSET under one "human ground truth" kappa risks masking per-domain disagreement (Simpson's-paradox-style).

## Resolved (not a defect)

Devil's Advocate's own code-verified re-check of the run_mode negative-control design: `single_shot` calls the judge (holds judge constant, isolates retries) and `self_refine` skips the judge but keeps retries (isolates the judge). The factorial design is clean: the confound the grounding brief worried about does not exist. Credit stands once `faithfulness_score` stops being a stub constant.

## Revision roadmap

**Must fix before treating any gate output as evidence:**
1. Wire a real `:metric_provider` (or explicitly gate on `Stub` and label every report "SIMULATED: no live metrics").
2. `at_least(_v, nil) → false` (fail-closed on a missing control, not fail-open).
3. Gate `iterative_beats_controls_gate` / `bounded_omission_gate` on the CI (e.g. lower bound clearing the threshold), not the bare point estimate.

**Should fix before calling this a health-literacy validation:**
4. Drop or evidence the 6.0 floor in `grade_band_gate`. Reconcile the FK/SMOG scale mismatch empirically on Med-EASi before requiring joint band membership.
5. Stop averaging SummaC + QAFactEval-overlap into one number. Report components separately, and for the omission gate use the correct direction (candidate-to-source recall).
6. Re-validate judge kappa in-domain on a small hand-labeled Med-EASi sample. Keep ASSET/PLABA as a secondary generalization check, and split PLABA out from ASSET in reporting since it's biomedical, not general-domain.

**Worth fixing:**
7. Justify or drop the Landis-Koch 0.41 borrow for a quadratically-weighted kappa.
8. Log the judge error/dropout rate in `judge_vs_human_kappa/0` (silent `Enum.reject(&is_nil/1)` risks a biased retained sample if errors aren't random).

## What's already right (preserve, don't relitigate)

- Deterministic external gate over LLM self-report (ADR-0002): correctly matches the self-correction literature (Kamoi 2024, Huang 2023).
- Cross-vendor judge split (ADR-0003): real, not cosmetic. It directly applies Verga et al. (2024) and Wataoka et al. (2024).
- Two-axis judge scoring (simplicity/fidelity separate, not blended): matches Cripwell et al. (2024).
- Quadratically-weighted kappa as the choice of estimator (the defect is only the borrowed threshold, not the weighting itself).
- Bounded 3-attempt retry with explicit `:hold` state: well-grounded (Kamoi 2024, Shinn et al. 2023, Wen et al. 2024).
- Epistemic honesty throughout the plan and ADRs: proxies are named as proxies. The pooled BERTScore/QAOverlap metric and the Stub default are both documented as shortcuts, with upgrade paths spelled out instead of being hidden.
