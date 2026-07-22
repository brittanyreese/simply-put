<!-- vale ai-tells.RestatementMarkers = NO -->
# Simply Put
<!-- vale ai-tells.RestatementMarkers = YES -->

[![CI](https://github.com/brittanyreese/simply-put/actions/workflows/ci.yml/badge.svg)](https://github.com/brittanyreese/simply-put/actions/workflows/ci.yml)

A plain-language readability rig. A rewrite loop lowers a text
to a target reading grade, and a pure function decides whether the result
passes. The design question it addresses is narrow: when an LLM rewrites a
passage to be simpler, what evidence should a reviewer accept that the
rewrite is both easier to read and still faithful to the source? The rig's
answer is to trust a deterministic check for the part that can be computed,
and to calibrate a model-based judge, against a human agreement ceiling, for
the part that cannot.

## Example

Real output from one pass through the pipeline, using the default
credential-free stub adapter (`mix.lock`-pinned deps only, no
`OPENROUTER_API_KEY`, no network call). It is the same rewrite loop and
Flesch-Kincaid gate a real LLM adapter runs through, with a crude
fixed-vocabulary stand-in doing the "rewriting":

<!-- vale ai-tells.FormalRegister = NO -->
<!-- vale ai-tells.OverusedVocabulary = NO -->
<!-- vale ai-tells.FillerPhrases = NO -->

**Before** (FK grade 18.53):
> The organization will commence its endeavor to facilitate additional support for numerous individuals.

**After** (FK grade 6.01, target 6.0, passed on attempt 1):
> The organization will start its try to help. additional support for lots folks.

<!-- vale ai-tells.FormalRegister = YES -->
<!-- vale ai-tells.OverusedVocabulary = YES -->
<!-- vale ai-tells.FillerPhrases = YES -->

Reproduce it:

```
mix run -e 'IO.inspect(SimplyPut.Plainish.run("The organization will commence its endeavor to facilitate additional support for numerous individuals."))'
```

The stub is deliberately crude (see `lib/simply_put/llm/stub.ex`). It exists
to exercise the real gate and retry loop without a network call, not to
produce fluent prose. Swap in the OpenRouter adapter (`OPENROUTER_API_KEY`,
see [the real adapter and judge](#the-real-adapter-and-judge)) for an actual
model rewrite. The gate and grades work the same way either side.

## Problem

Two failure modes make an LLM rewriter hard to evaluate on its own word.

First, a surface readability formula is easy to game. Flesch-Kincaid grade
level (Kincaid et al., 1975) is a function of sentence and word length, so a
model can lower it by splitting sentences even when comprehension does not
improve. Tanprasert and Kauchak (2021) demonstrate exactly this: on its own,
Flesch-Kincaid is not a valid text-simplification evaluation metric.
Optimizing against it is a Goodhart trap, where the number moves while the
target construct, comprehension, does not.

Second, a model asked to check its own output is unreliable. A rewriter that
critiques and revises its own text with no external signal, the self-refine
pattern (Madaan et al., 2023, and Shinn et al., 2023), does not reliably
improve on general tasks and can degrade quality (Huang et al., 2023, and
Kamoi et al., 2024). Measurable gains appear when an external verifier enters the loop
(Zhang et al., 2024). The dominant real-world failure in text simplification
is silent content loss, not surface disfluency (Devaraj et al., 2022), which
is exactly what a self-report cannot be trusted to flag.

The rig separates the two concerns. A deterministic gate owns the
readability decision. A separate, calibrated model judge owns the
meaning-preservation check, and its agreement with humans is measured rather
than assumed.

## Reproducing the result

Clone the repository and run two commands. The suite goes green with no
credentials and no database setup.

```
git clone <this-repo> simply_put && cd simply_put
mix deps.get && mix test
```

That runs the rewrite pipeline against the deterministic Flesch-Kincaid gate
below, using a stub adapter with no network calls, and returns green: 148
tests, 0 failures (7 excluded). Live-API tests carry the `:live` tag and are
excluded by default; run them with `mix test --only live` (see [the real
adapter and judge](#the-real-adapter-and-judge)). Tests that load a real
embedding model carry the `:bumblebee_models` tag and are excluded the same
way.

## Method

The pipeline is a firewall chain. One drafter call feeds a deterministic
gate, and the gate does not take the drafter's word for its result. A failed
gate check is fed back as feedback for the next attempt, phrased from the
gate's own numbers.

```
text
  │
  ├─ Readability.flesch_kincaid/1     score before        (pure, public)
  ├─ LLM.rewrite/2                    ONE model call       (adapter seam: Stub | OpenRouter)
  ├─ Readability.flesch_kincaid/1     score after           (pure, public)
  │
  ├─ score <= target? ──yes──> :passed
  │        │no
  │        └─ attempts < max? ──yes──> Readability.critique/2 feeds the miss
  │        │                           back into the next rewrite call
  │        └─ no ──> :held (never a silent skip)
  │
  └─ LLM.score/2                      3-axis judge on a passing rewrite
       rates simplicity, fidelity, fluency (1-5); meaning-preservation is
       the fidelity axis. A different model vendor from the rewriter on
       purpose, so a judge never grades its own rewriter's homework
```

Every stage returns an explicit result. A rewrite that never reaches the
target grade comes back `:held`, with the before and after numbers attached,
rather than swallowed into a generic error.

### The deterministic gate

The gate is the part a reviewer should not have to take on faith. It is plain
Elixir, no dependency, short enough to read in one sitting
(`lib/simply_put/readability.ex`):

```elixir
@spec flesch_kincaid(String.t()) :: float()
def flesch_kincaid(text) when is_binary(text) do
  words = words(text)
  word_count = length(words)

  if word_count == 0 do
    0.0
  else
    sentence_count = text |> sentences() |> length() |> max(1)
    syllable_count = Enum.reduce(words, 0, fn word, acc -> acc + syllables(word) end)

    0.39 * (word_count / sentence_count) + 11.8 * (syllable_count / word_count) - 15.59
  end
end
```

`Readability.demo/0` is a self-check with a hand-traceable example: 10
monosyllabic words across 2 sentences must score `-1.84`. Run it in
`iex -S mix` and verify it by hand. The gate is a verifiable proxy for
reading grade, not a comprehension test, and the rest of the design treats it
that way (ADR-0002).

Keeping Flesch-Kincaid here is a deliberate tradeoff. A learned readability
model would likely correlate with comprehension better. The gate's value,
though, is that a reviewer can compute a pure function by hand and cannot argue
with the answer, and a learned model would trade that away for one more opaque
score. Flesch-Kincaid's known weakness as a standalone quality measure
(Tanprasert and Kauchak, 2021) never bites here, because the formula only ever
decides surface grade, and the learned simplicity estimate and the calibrated
judge cover what it misses. That division of labor, a deterministic check with
a judge for the rest, is where the simplification-evaluation literature has
converged (Zhang et al., 2024).

## Evaluation harness

The harness benchmarks the gated loop against negative controls and scores
each output on several axes at once, held apart rather than blended into one
number.

Run modes. `iterative` is the gated loop. `single_shot` (one pass, no loop)
and `self_refine` (the model critiques itself, no external gate) are the
controls, chosen because they isolate the two things the gate adds: a retry
and an external verifier.

Metric axes. Grade compliance is the share of outputs at or under the
Flesch-Kincaid ceiling. Faithfulness is a source-to-candidate natural
language inference score that catches added claims; omission is the
candidate-to-source direction that catches dropped content, in the style of
NLI-based inconsistency detection (Laban et al., 2022). The harness also
reports SARI (Xu et al., 2016), SLE, a learned reference-less simplicity
estimate (Cripwell et al., 2023), and BERTScore (Zhang et al., 2020) where
available. Model-based axes run through a `MetricProvider` adapter whose
default is a no-network stub, with real inference opt-in via
`METRIC_PROVIDER=bumblebee`.

Comparison. `EvalRunner.dominance/1` states a Pareto relation over the grade
and faithfulness axes kept apart (dominates, dominated, tradeoff, tie)
instead of a single pass or fail, because collapsing a two-axis tradeoff into
one score hides which axis moved (ADR-0005). Differences are tested with a
paired bootstrap and reported against their 95% confidence intervals.

## Results

### Rewrite loop on the CommonLit CLEAR corpus

The first table runs the full pipeline against 200 excerpts from the
[CommonLit CLEAR
Corpus](https://huggingface.co/datasets/casey-martin/CommonLit-Ease-of-Readability)
(licensed passages, grade range -1.0 to 25.6, seeded via
`priv/repo/seeds.exs`), processed through `Oban` and shown live on the
`/runs` dashboard as each job completes.

| | |
|---|---|
| Total | 200 |
| Passed (FK gate) | 187 (93.5%) |
| Held (max attempts hit) | 13 (6.5%) |
| Average grade, before | 9.53 |
| Average grade, after | 3.77 |
| Average attempts | 1.24 |

This run used the stub adapter (synonym swap plus sentence splitting, no
network calls), which is the default and the green-clone path above. The held bucket is more informative than the pass
rate: all 13 hit the 3-attempt cap, and all 13 began as the hardest source
texts in the sample (grade 12.5 to 19.0). They land close to the target but
not under it. A synonym swap can shorten a sentence; it cannot restructure an
idea the way a real model can. Raising that ceiling is the purpose of the
OpenRouter adapter described below.

### Med-EASi test split

The second table runs the full canonical Med-EASi test split (Basu et al.,
2023), 300 items per mode, under all three modes in one batch. Metrics came
from real Bumblebee inference with an OpenRouter judge. Method and full
numbers are in
[`docs/results/2026-07-22-med-easi-full-split-sle-significance.md`](docs/results/2026-07-22-med-easi-full-split-sle-significance.md).
The prior card without SLE or the bootstrap test is
[`docs/results/2026-07-15-med-easi-full-split.md`](docs/results/2026-07-15-med-easi-full-split.md);
the earlier 30-item bounded card is
[`docs/results/2026-07-08-med-easi-bounded-card.md`](docs/results/2026-07-08-med-easi-bounded-card.md).

| metric | iterative | single_shot | self_refine |
|--------|-----------|-------------|-------------|
| FK grade | 7.12 | 8.43 | 7.17 |
| grade <= 8 compliance | 69.0% | 47.7% | 70.7% |
| faithfulness (source to candidate) | 0.889 | 0.930 | 0.889 |
| omission (candidate to source) | 0.901 | 0.931 | 0.898 |
| SLE (simplicity) | 2.17 | 1.79 | 2.12 |
| SARI | 0.400 | 0.403 | 0.398 |

The two gated modes sit at 7th grade and clear the 8th-grade ceiling 69.0%
and 70.7% of the time, against 47.7% for ungated single_shot. SLE, a
model-based simplicity score, agrees: the gated modes read simpler (2.17,
2.12) than single_shot (1.79). Iterative against single_shot is a two-axis
tradeoff, reported as a dominance relation rather than one blended score
(ADR-0005). The gate buys 21.3 points of grade compliance for 0.040 of
faithfulness, and a paired bootstrap puts both differences outside their 95%
confidence intervals, so the tradeoff is not sampling noise.

Against self_refine the bootstrap settles what n=30 and point estimates left
open, and the answer cuts against the pipeline's own preferred mode. Neither
the grade difference (-1.7 points) nor the faithfulness difference (+0.001)
clears its confidence interval, so external tool feedback shows no measurable
advantage over model self-critique on this corpus with this model pairing.
The honest reading is parity. Keeping the axes apart and testing the
difference is what makes that visible; a blended verdict would have buried
it. The parity result is tied to this exact generator and judge pairing and
to the current feedback prompt, and it is not a general claim about
self-refinement.

One metric ran and earned its way out of the table. BERTScore F1 reads 0.998
for all three modes, a flat null. Cosine similarity between sentence
embeddings saturates when candidate and reference share most of their
content, which every readable rewrite of a short sentence does, so the axis
cannot separate the modes. It stays wired in the harness
(`SimplyPut.MetricProvider.BertScore`), but a number that never moves is
reported as a null, not shown next to the axes that discriminate.

### Judge calibration

The meaning-preservation judge is calibrated against human ratings rather
than taken on faith. Calibration uses 100 pairs from the ASSET corpus
(Alva-Manchego et al., 2020), each carrying 15 worker ratings per aspect.
Agreement between the judge and the human mean is quadratically-weighted
Cohen's kappa (Cohen, 1968), read against the bands of Landis and Koch
(1977). The judge reaches 0.77 on fidelity and 0.70 on fluency (substantial
agreement) but 0.24 on simplicity, which fails the calibration gate.

That miss sits on the one axis the judge is never asked to decide: the
deterministic Flesch-Kincaid gate owns simplicity (ADR-0002). The low number
is also read against a ceiling, not against a perfect 1.0. On ASSET's raw
15-worker ratings, human-human agreement (Krippendorff's alpha; Krippendorff,
2004) is only 0.43 on simplicity, against about 0.56 for fidelity and
fluency, so simplicity is the hardest axis for humans too. The judge's
shortfall is a gap below 0.43, not below 1.0. On the two
well-defined axes the judge scores above the human-human alpha, expected
because it is compared against a denoised 15-worker mean; on simplicity it
falls below even the human floor. Adding the judge as a 16th rater moves
fidelity up by 0.003 and simplicity down by 0.046, a built-in control that
reproduces the finding under one estimator throughout. This posture, measure
the judge against a chance-corrected human ceiling rather than trust its
self-consistency, follows the calibrated-judge protocols argued for by Norman
et al. (2026). Details are in
[`docs/results/2026-07-15-asset-judge-kappa.md`](docs/results/2026-07-15-asset-judge-kappa.md)
and
[`docs/results/2026-07-22-asset-human-human-agreement.md`](docs/results/2026-07-22-asset-human-human-agreement.md).

## The real adapter and judge

`SimplyPut.LLM.OpenRouter` follows the same adapter behaviour as the stub but
calls OpenRouter's chat completions API for real. It is selected only when
`OPENROUTER_API_KEY` is set (`config/runtime.exs`); without a key the stub
stays the default, so the green-clone path is unaffected.

The judge is a separate model call (`LLM.score/2`) that rates each
gate-passing rewrite on three axes, simplicity, fidelity, and fluency, from
1 to 5. The gated loop requires all three to clear a threshold, and the
dashboard's meaning-preserved verdict is derived from the fidelity axis, a
content check the deterministic gate cannot make because sentence and word
length say nothing about meaning. The judge defaults to a different model
vendor from the rewriter (`openai/gpt-4o-mini` rewrites,
`anthropic/claude-haiku-4.5` judges, both configurable). An LLM judge scores
output from its own model family more favorably (Panickssery et al., 2024;
Wataoka et al., 2024), so the two are kept cross-vendor on purpose (ADR-0003).

### Live sample

A 20-item run against the real OpenRouter adapter, rewriter
`openai/gpt-4o-mini` and judge `anthropic/claude-haiku-4.5`:

| | |
|---|---|
| Total | 20 |
| Passed (FK gate) | 20 (100%) |
| Held | 0 |
| Average grade, before | 2.64 |
| Average grade, after | 2.19 |
| Average attempts | 1.0 |
| Judge: meaning preserved | 8 (40%) |
| Judge: meaning lost | 12 (60%) |

This sample is the first 20 corpus rows by id, not a random draw. It lands
far easier (average grade 2.64) than the full 200-item corpus (average 9.53),
so its FK numbers are not comparable to the stub table above. Read it for the
one thing it shows. The gate and the judge disagree here, because all 20
cleared the FK gate on the first attempt while the judge marked 60% as
meaning-lost. A passing gate certifies only that a rewrite is short, so a
separate judge is needed to check whether its facts survived.

```
OPENROUTER_API_KEY=sk-... mix test --only live
```

## Running locally

```
mix ecto.setup                 # creates the SQLite db, seeds the corpus
mix phx.server                 # http://localhost:4000/runs
```

In another shell, enqueue the batch and watch the dashboard fill in as each
job completes:

```
mix run -e "SimplyPut.Batch.enqueue_all()"
```

The `/runs` view streams the result table (SQLite via `Oban.Engines.Lite`, no
Postgres needed to try this locally) and subscribes to PubSub only after the
socket connects, so nothing queries the database during disconnected mount.

## Design decisions

The full rationale for each is in `docs/adr/`.

- [ADR-0001](docs/adr/0001-sqlite-over-postgres.md): SQLite, not Postgres. The
  one value this repository protects is a stranger cloning it and reaching
  green without installing anything first. `ecto_sqlite3` plus
  `Oban.Engines.Lite` keeps a real database and a real background-job story
  without asking a reviewer to stand up a server. Swapping to Postgres later
  is one dependency and one config block.
- [ADR-0002](docs/adr/0002-deterministic-gate-not-llm-self-report.md): the
  gate is a pure function, never the model's own claim.
- [ADR-0003](docs/adr/0003-judge-cross-vendor.md): the judge and the rewriter
  use different model vendors.
- [ADR-0004](docs/adr/0004-stub-default-adapter.md): the default adapter is
  the stub, and OpenRouter is opt-in.
- [ADR-0005](docs/adr/0005-separate-axes-not-blended-verdict.md): score the
  eval axes apart, and report iterative against the controls as a dominance
  relation, not a blended gate.

## Scope and limitations

This repository is a capability demo for LLM evaluation, built at
demo scale. `/runs` is the only page and it is read-only, a single view over
a seeded corpus and its batch results. The pass and held numbers are specific to the runs described here,
on these corpora, with these model pairings. They are not a claim about any
other dataset. The Med-EASi parity result is conditional on the current
generator, judge, and feedback prompt. Judge calibration was measured on
general-domain ASSET pairs; domain-matched calibration on medical text is
still open, as are the position-swap and verbosity-bias checks that
`SimplyPut.JudgeValidation` provides but that have not yet run on this subset.

## References

<!-- vale ai-tells.ColonUsage = NO -->

- Alva-Manchego, F., et al. (2020). ASSET: A Dataset for Tuning and
  Evaluation of Sentence Simplification Models with Multiple Rewriting
  Transformations. ACL 2020.
- Basu, C., Vasu, R., Yasunaga, M., & Yang, Q. (2023). Med-EASi: Finely
  Annotated Dataset and Models for Controllable Simplification of Medical
  Texts. AAAI 2023. arXiv:2302.09155.
- Cohen, J. (1968). Weighted kappa: Nominal scale agreement with provision for
  scaled disagreement or partial credit. Psychological Bulletin, 70(4),
  213-220.
- Cripwell, L., et al. (2023). Simplicity Level Estimate (SLE): A Learned
  Reference-Less Metric for Sentence Simplification. EMNLP 2023, ACL Anthology
  2023.emnlp-main.739.
- Devaraj, A., et al. (2022). Evaluating Factuality in Text Simplification.
  ACL 2022. arXiv:2204.07562.
- Huang, J., et al. (2023). Large Language Models Cannot Self-Correct
  Reasoning Yet. ICLR.
- Kamoi, R., et al. (2024). When Can LLMs Actually Correct Their Own Mistakes?
  A Critical Survey of Self-Correction of LLMs. TACL. DOI
  10.1162/tacl_a_00713.
- Kincaid, J. P., Fishburne, R. P., Rogers, R. L., & Chissom, B. S. (1975).
  Derivation of New Readability Formulas for Navy Enlisted Personnel. Research
  Branch Report 8-75, Naval Air Station Memphis.
- Krippendorff, K. (2004). Content Analysis: An Introduction to Its
  Methodology (2nd ed.). Sage.
- Laban, P., et al. (2022). SummaC: Re-Visiting NLI-based Models for
  Inconsistency Detection in Summarization. TACL. arXiv:2111.09525.
- Landis, J. R., & Koch, G. G. (1977). The Measurement of Observer Agreement
  for Categorical Data. Biometrics, 33(1), 159-174.
- Madaan, A., et al. (2023). Self-Refine: Iterative Refinement with
  Self-Feedback. NeurIPS. arXiv:2303.17651.
- Norman, J. D., et al. (2026). Reliability without Validity: A Systematic,
  Large-Scale Evaluation of LLM-as-a-Judge Models Across Agreement,
  Consistency, and Bias. arXiv:2606.19544.
- Panickssery, A., et al. (2024). LLM Evaluators Recognize and Favor Their Own
  Generations. arXiv:2404.13076.
- Shinn, N., et al. (2023). Reflexion: Language Agents with Verbal
  Reinforcement Learning. NeurIPS. arXiv:2303.11366.
- Tanprasert, T., & Kauchak, D. (2021). Flesch-Kincaid is Not a Text
  Simplification Evaluation Metric. GEM Workshop, ACL 2021. DOI
  10.18653/v1/2021.gem-1.1.
- Wataoka, K., et al. (2024). Self-Preference Bias in LLM-as-a-Judge.
  arXiv:2410.21819.
- Xu, W., et al. (2016). Optimizing Statistical Machine Translation for Text
  Simplification. TACL. DOI 10.1162/tacl_a_00107. (SARI)
- Zhang, T., et al. (2020). BERTScore: Evaluating Text Generation with BERT.
  ICLR. arXiv:1904.09675.
- Zhang, Y., et al. (2024). Small Language Models Need Strong Verifiers to
  Self-Correct Reasoning. ACL Findings 2024. arXiv:2404.17140.

<!-- vale ai-tells.ColonUsage = YES -->

## License

MIT. See `LICENSE`. Citation metadata in `CITATION.cff`.
