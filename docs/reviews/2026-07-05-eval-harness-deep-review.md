# Deep Review: Eval Harness + Core Engine (four-lens panel)

Second-pass review of the Phase 1 evaluation harness and the modified core engine, run as four independent read-only lenses: statistical/methods rigor and research grounding, core-engine correctness and Iron Laws, Phoenix LiveView and Ecto schema, and test-suite quality. It extends `2026-07-04-eval-harness-methodology-review.md`, which covered validity of the gate outputs only. Scope here adds the rewrite engine, readability formulas, OpenRouter adapter, LiveView dashboard, migrations, and the test suite.

## Tier A: fixed in this pass (confirmed correctness bugs)

Three confirmed bugs were fixed before this doc was written, with tests. They are recorded here for the audit trail. Treat them as closed work, already done.

| Finding | File | Fix |
|---|---|---|
| Test-split leakage guard bypass: `get_change/2` cannot tell "unchanged" from "changed to nil", so `%{split: nil}` slipped past the frozen-split guard, enabling a nil-then-`:train` two-step leak | `corpus_item.ex:49` | Guard on change-map key presence, reject any move of a `:test` row including to nil. Test: `corpus_item_test.exs` "refuses to null out a test-split item's split" |
| Tokenizer skewed the core FK/SMOG metric: sentence splitter broke on decimals ("3.5 mg") and abbreviations, inflating sentence count and deflating FK grade; word tokenizer dropped all-numeric tokens | `readability.ex:103,107` | Word class now includes digits and drops pure-punctuation tokens. Sentence split now happens only on a terminator followed by whitespace or end-of-string. Tests: `readability_test.exs` "tokenization" describe |
| In-loop judge scorer decoded raw model output, so a fenced or preamble-wrapped JSON object failed to parse. It silently burned all three retries and returned `:held` with no signal. | `open_router.ex:73` | `extract_json_object/1` pulls the first `{...}` before decoding. Tests: `open_router_extract_json_test.exs` |

## What is already correct (preserve, do not relitigate)

- FK and SMOG formulas and constants verified against the published definitions. FK self-checks to -1.84. The formulas were never the problem, only the tokenization feeding them (now fixed).
- Quadratically-weighted Cohen's kappa is textbook-correct (disagreement weights normalized to [0,1], expected counts from marginals). Percentile bootstrap CI is sound and guards empty input.
- SARI single-reference scoring, with the documented vacuous-satisfaction convention, follows the standard treatment.
- OTP and Iron Laws are clean: TLS is hardened with `verify_peer` and pinned CA certs, the cross-vendor judge split is real (gpt-4o-mini rewriter, claude-haiku judge), the retry loop is bounded and off-by-one-free, and `{:error, %Ecto.Changeset{}}` is matched explicitly. The codebase avoids atom-exhaustion, float-money columns, and `raw/1`.
- LiveView mount does no DB work and gates PubSub behind `connected?/1`. The runs table uses streams. There's no XSS surface, since the untrusted `text_out` is never rendered in this view.
- The test suite uses hand-computed golden values for the statistical code, not type assertions. Schemas match their migrations field-for-field with no drift.

## Tier B: measurement validity (open)

These affect whether gate outputs can be reported as a health-literacy validation. Some are code changes. Others need real data or models to close. The prior review found the first tier of these. This pass confirms they remain open and adds new ones.

| # | Severity | Finding | File:line | Fix |
|---|---|---|---|---|
| B1 | High (safety) | `bounded_omission_gate` measures the wrong direction. `entail(source, candidate)` detects unsupported additions (hallucination), not omissions. A rewrite that drops a contraindication stays entailed and scores faithful. | `evaluation.ex:87`, `eval_runner.ex:187` | Score the reverse direction (`entail(candidate, source)`) for omission. Report addition and omission as separate axes. |
| B2 | High | Grade-band floor is backwards and FK/SMOG are not jointly satisfiable. `{6.0, 8.0}` fails an ideal grade-5.5 rewrite, but guidance targets 6th grade and below. SMOG reads 1 to 3 grades above FK, so a 2-grade joint window is near-unsatisfiable. | `eval_runner.ex:19`, `metrics.ex:52` | Use a ceiling, not a band. Pick one primary scale, or calibrate the FK/SMOG offset on Med-EASi first. |
| B3 | High | `faithfulness_score` averages two non-commensurate constructs (NLI probability and QA token-overlap F1) into one 0.7 gate, and both halves penalize legitimate jargon-defining elaboration. Rows are also inconsistent units when one component is nil, then pooled. | `evaluation.ex:99` | Store SummaC and QAFactEval in separate columns. Never collapse them to one thresholded scalar. |
| B4 | Medium | ASSET (general) and PLABA (biomedical) are pooled into one kappa, which can mask a per-domain judge failure. | `judge_validation.ex:107` | Compute and gate kappa per `source_dataset`. Report both, plus the pooled figure. |
| B5 | Medium | Landis-Koch 0.41 "moderate" threshold, calibrated for nominal kappa, is applied to a quadratically-weighted ordinal kappa, where it is a weaker bar than it reads. | `eval_runner.ex:177` | Anchor the threshold to the human-vs-human ceiling the repo already computes, or cite a weighted-kappa benchmark. |
| B6 | Medium | `judge_vs_human_kappa/0` silently drops judge-error items and counts only survivors, biasing the retained sample if errors are not random. | `judge_validation.ex:36` | Return attempted/scored/dropped counts and log the dropout rate. |
| B7 | Medium | Position-swap test counts fidelity flips as position bias, though fidelity is legitimately directional. This inflates the flip rate. | `judge_validation.ex:128` | Exclude fidelity from the swap-flip criterion, or test only order-invariant axes. |
| B8 | Low/Medium | `human_vs_human` pairs on bare `external_item_id`, so an ASSET/PLABA id-namespace collision can pair the wrong item. | `judge_validation.ex:55` | Key on `{source_dataset, external_item_id}`. |
| B9 | Low/Medium | SMOG sqrt-rescaling is unstable for short rewrites: one sentence with three polysyllables reads near grade 13, adding noise exactly where the grade-band gate runs. | `readability.ex:143` | Gate SMOG on a minimum sentence count, or drop it from the compliance gate for short texts. |
| B10 | Low | Bootstrap percentile indices via `trunc` bias the interval slightly inward. Percentile bootstrap of a mean also undercovers at small n. | `stats.ex:88` | Use rounded/interpolated indices, and document the small-n undercoverage, or use BCa if it matters. |
| B11 | Low | NLI-label to scalar mapping (neutral to 0.5, contradiction to `1.0 - score`) is an undocumented calibration that feeds the 0.7 gate. | `evaluation.ex:89` | State and justify the mapping, or gate on the label directly. |

## Tier C: performance and schema hygiene (open)

| # | Severity | Finding | File:line | Fix |
|---|---|---|---|---|
| C1 | Medium/High | `/runs` runs two full-table `Repo.all(RewriteEvaluation)` scans into memory on every render, on an append-only table that grows with every eval run. | `runs_live.ex:149,168` | Push both into SQL: `DISTINCT ON (corpus_item_id) ... ORDER BY inserted_at DESC` for latest-per-item, `group_by: run_mode` for the summary. |
| C2 | Medium | `rewrite_evaluations.corpus_item_id` has no index and no `on_delete`, unlike the sibling `run_results` FK. | `migration 20260705003056:6` | Add the index and pick `on_delete` deliberately. |
| C3 | Medium | No index on `corpus_items(source, split)`, the actual frozen-test-split query. | `eval_runner.ex:88` | `create index(:corpus_items, [:source, :split])`. |
| C4 | Low/Medium | CSV importers `File.read!` raise on a missing path despite an `{:ok, _} | {:error, _}` spec. | `corpus/import.ex:41`, `human_labels/import.ex:35` | Use `File.read/1` and wrap the error. |
| C5 | Low/Medium | Oban retry can double-write an eval row for the same item and batch (documented, not enforced). | `rewrite_worker.ex:78` | Add an idempotency key on `[corpus_item_id, batch_id, run_mode]`. |
| C6 | Info | The frozen-test-split guard is app-layer only. `update_all` or raw SQL bypasses it. | `corpus_item.ex:49` | Acceptable for portfolio scope. A DB check constraint would make it hard to bypass. |

## Tier D: test coverage (open)

- Both production adapters run Stub-only in CI. `LLM.OpenRouter` (whole file `@moduletag :live`) and `MetricProvider.Bumblebee` (`:bumblebee_models`) have no default-run coverage, so "all tests pass" verifies the stubs, not the real adapters. The pure parse helpers need no network: `parse_verdict/1` and `extract_content/1` in OpenRouter, `normalize_label/1` and `split_questions/1` in Bumblebee. Worth a README line so a reviewer does not misread green CI.
- Importer malformed-row and rollback paths are untested despite being a documented promise, in both `corpus/import.ex` and `human_labels/import.ex`.
- No failing stub exists, so every `{:error, _}` branch in `Plainish` and `RewriteWorker` is unverified. Add a configurable failing adapter and assert propagation and Oban retry.
- `JudgeValidation.verbosity_bias_test/1` only proves the negative case; add a padded-rewards stub asserting `bias_rate: 1.0`, mirroring the existing `OrderBiasedStub`. The judge-error skip branch is also untested.
- `Plainish.judge_clears?/1` boundary is never driven to fail because the stub always returns 4/5/4. Add a stub with one axis at 2.
- A few shallow spots: `MetricProviderTest` asserts `is_float` against known constants (assert the exact value), `LLM.Stub` transforms have only indirect coverage, `HumanLabel.changeset/2` has no dedicated out-of-range test.

## Sequencing

Tier A is done and green. Tier B, C, and D are disclosed follow-up. B1 (omission direction) and B2 (grade-band floor) are the highest-value next steps because they are safety-relevant and change what the harness claims to measure. Both are code changes that do not need new data. The rest of Tier B needs real metric providers or a small in-domain Med-EASi labeling pass to close properly, which matches the repo's existing posture of naming proxies as proxies.
