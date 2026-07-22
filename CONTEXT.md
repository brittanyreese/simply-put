# Context

Single-context repo. Domain vocabulary and decisions live here and in
`docs/adr/`.

## Glossary

- **FK gate**: the deterministic Flesch-Kincaid check
  (`SimplyPut.Readability.flesch_kincaid/1`) that decides whether a rewrite
  passes. It's the repo's trust anchor, a pure function that reads only
  the input text and never asks the model to grade itself. Always call it
  "the gate," not "the score" or "the check." It gates the result. It
  doesn't just measure it.
- **Rewrite loop**: `SimplyPut.Plainish.run/2`. One `LLM.rewrite/2` call,
  scored by the gate, retried with a critique on miss, bounded by
  `max_attempts`.
- **Critique**: the natural-language feedback `Readability.critique/2`
  produces from a failed gate check (e.g. "still too long, cut clause
  count"), fed into the next rewrite attempt's prompt.
- **Passed**: gate score at or under `target_grade` on some attempt within
  `max_attempts`.
- **Held**: attempts ran out while the text was still over target. The
  result keeps the before/after numbers, so a caller can see how close it
  got instead of hitting a silent drop. Never call this "failed."
- **Judge**: a model call (`LLM.score/2`) that rates a rewrite on three 1-5
  axes (simplicity, fidelity, fluency). The gated loop scores each passing
  attempt on all three; it produces a `score`, not a pass/fail. A different
  model vendor from the rewriter on purpose (ADR-0003).
- **Verdict**: `%{fk_pass: boolean(), meaning_preserved: boolean()}`, derived
  from the judge score, not a second model call: `meaning_preserved` is the
  fidelity axis clearing the pass threshold. Attached to a `Plainish.Result`
  whenever a judge score is (the gated modes, once the structural gate
  passes). Two independent axes; the gate can pass while meaning is lost, or
  the reverse.
- **Adapter seam**: `SimplyPut.LLM` behaviour, with `Stub` (deterministic,
  no network, default) and `OpenRouter` (real API, selected only when
  `OPENROUTER_API_KEY` is set) as the two implementations. Call it
  "adapter," not "provider" or "backend": the word signals swappability.
- **Corpus item**: one seeded source text (`CorpusItem`), the input side of
  a run. Two corpora share the table, tagged by `source`: the CommonLit
  CLEAR Corpus feeds the core rewrite-loop demo. Med-EASi feeds the eval
  harness and carries its own `train`/`dev`/`test` split, imported one file
  per split so the harness uses the dataset's published test set.
- **Run result**: one `Plainish.run/2` outcome persisted against a corpus
  item (`RunResult`), upserted per `corpus_item_id` so a retry replaces
  rather than duplicates.
- **Batch**: one `Batch.enqueue_all/1` fan-out, one `RewriteWorker` job
  per corpus item, all tagged with a shared `batch_id`.

## Evaluation layer

The harness that benchmarks the rewrite loop, on top of the core glossary
above. It runs the loop over the Med-EASi test split and scores each output
on several axes at once.

- **Run mode**: how a rewrite is produced. `iterative` is the gated loop.
  `single_shot` (one pass, no loop) and `self_refine` (the model critiques
  itself, no external gate) are the negative controls it is measured against.
- **Metric axes**: separate scores, never blended. Grade compliance (share
  of outputs at or under the FK ceiling), faithfulness (source-to-candidate
  NLI, catches added claims), omission (candidate-to-source NLI, catches
  dropped content), plus SARI, BERTScore, and SLE where available.
- **Metric provider**: the `SimplyPut.MetricProvider` adapter behind the
  model-based axes. `Stub` (constant scores, no network) is the default so
  the suite never loads a checkpoint. `Bumblebee` runs the real models,
  opt-in through `METRIC_PROVIDER=bumblebee`.
- **Dominance**: `EvalRunner.dominance/1`, the honest comparison of iterative
  against each control. It states a Pareto relation over the grade and
  faithfulness axes kept apart (dominates, dominated, tradeoff, tie), not a
  single pass/fail. See ADR-0005.
- **Success gate**: a one-axis pass/fail from `success_gates/2` (grade
  compliance, bounded omission, judge-versus-human kappa). The
  iterative-versus-controls question is reported through `dominance/1`
  instead, because it is a two-axis tradeoff.

## Decisions

See `docs/adr/` for the full rationale behind each of these:

- [ADR-0001](docs/adr/0001-sqlite-over-postgres.md): SQLite, not Postgres
- [ADR-0002](docs/adr/0002-deterministic-gate-not-llm-self-report.md): the
  gate is a pure function, never the model's own claim
- [ADR-0003](docs/adr/0003-judge-cross-vendor.md): judge and rewriter use
  different model vendors
- [ADR-0004](docs/adr/0004-stub-default-adapter.md): the default adapter
  is Stub, OpenRouter is opt-in
- [ADR-0005](docs/adr/0005-separate-axes-not-blended-verdict.md): score the
  eval axes apart, report iterative-versus-controls as dominance, not a
  blended gate
