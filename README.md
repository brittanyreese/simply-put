<!-- vale ai-tells.RestatementMarkers = NO -->
# Simply Put
<!-- vale ai-tells.RestatementMarkers = YES -->

A plain-language readability rig. Text goes in, a rewrite comes out at or
below a target reading grade, and the claim is checked by a pure function
you can read yourself, not by trusting a model's word for it.

## The claim, and how to check it

Clone it, run two commands, and the suite goes green without any
credentials or database setup.

```
git clone <this-repo> simply_put && cd simply_put
mix deps.get && mix test
```

That runs a real rewrite pipeline against the deterministic Flesch-Kincaid
gate below, using a stub adapter (no network calls), and comes back green:
1 doctest, 149 tests, 0 failures (8 excluded). Live-API tests are tagged
`:live` and excluded by default; run them with `mix test --only live` (see
[Judge and the real adapter](#judge-and-the-real-adapter)). Tests that load a
real embedding model are tagged `:bumblebee_models` and excluded the same way.

## Architecture

The shape is a firewall chain, not a prompt. One drafter call feeds a
deterministic gate, and the gate doesn't take the drafter's word for it.
A failed gate check gets fed back as the next prompt's feedback, using the
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
  └─ (optional) LLM.judge/2           meaning-preserved check
       enabled only via deps[:judge]; two different model vendors on
       purpose, so a judge never grades its own rewriter's homework
```

Every stage returns an explicit result. Nothing gets dropped quietly: a
rewrite that never gets under the target grade comes back `:held`, with the
before/after numbers attached, not swallowed into a generic error.

## The trust anchor

The gate is the part a reviewer shouldn't have to take on faith, so it's
plain Elixir, no dependency, and short enough to read in one sitting
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
monosyllabic words across 2 sentences must score `-1.84`. Run it yourself
in `iex -S mix`.

## Honest metrics

The numbers below come from running the full pipeline against 200 real
excerpts from the [CommonLit CLEAR
Corpus](https://huggingface.co/datasets/casey-martin/CommonLit-Ease-of-Readability)
(licensed passages, grade range -1.0 to 25.6, seeded via `priv/repo/seeds.exs`),
processed through `Oban` and shown live on the `/runs` dashboard as each
one completes.

| | |
|---|---|
| Total | 200 |
| Passed (FK gate) | 187 (93.5%) |
| Held (max attempts hit) | 13 (6.5%) |
| Average grade, before | 9.53 |
| Average grade, after | 3.77 |
| Average attempts | 1.24 |

This run used the stub adapter (synonym swap + sentence splitting, no
network calls) with the judge seam off, which is the default and the
green-clone path above. Look at the held bucket before the pass rate: all
13 hit the 3-attempt cap, and all 13 started as the hardest source texts in
the sample (grade 12.5-19.0). They land close to the target but not under
it. A synonym swap can shorten a sentence; it can't restructure an idea the
way a real model can. Raising that ceiling is what the OpenRouter adapter
below is for.

The Flesch-Kincaid gate checks sentence and word length, not whether a
rewrite is actually easier to understand. It's a verifiable proxy, not a
comprehension test.

## Results so far

The full canonical Med-EASi test split, 300 items per mode, ran under all
three modes in one batch. Metrics came from real Bumblebee inference with
an OpenRouter judge. Method and full numbers live in
[`docs/results/2026-07-22-med-easi-full-split-sle-significance.md`](docs/results/2026-07-22-med-easi-full-split-sle-significance.md).
The prior card without SLE or significance is
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
| BERTScore F1 | 0.998 | 0.998 | 0.998 |
| SARI | 0.400 | 0.403 | 0.398 |

The two gated modes sit at 7th grade and clear the 8th-grade ceiling
69.0% and 70.7% of the time, against 47.7% for ungated single_shot. SLE, a
model-based simplicity score, agrees: the gated modes read simpler (2.17,
2.12) than single_shot (1.79). Iterative against single_shot is a two-axis
tradeoff, reported as a dominance relation rather than one blended score
(see [ADR-0005](docs/adr/0005-separate-axes-not-blended-verdict.md)). The
gate buys 21.3 points of grade compliance for 0.040 of faithfulness, and a
paired bootstrap significance test puts both differences outside their 95%
CIs, so the tradeoff is real, not sampling noise.

Against self_refine the significance test settles what n=30 and point
estimates left open, and the answer cuts against the pipeline's own
favorite mode. Neither the grade difference (-1.7 points) nor the
faithfulness difference (+0.001) clears its CI, so external tool feedback
shows no measurable advantage over model self-critique on this corpus with
this model pairing. The honest reading is parity. Keeping the axes separate
and testing the difference is what makes that visible; a blended verdict
would have buried it.

Caveats: BERTScore sits near 0.998 for every mode and barely discriminates.
The parity result is tied to this exact generator and judge pairing and to
the current feedback prompt.

The judge is calibrated against human ratings, not taken on faith. On 100
ASSET pairs, quadratically-weighted kappa reaches 0.77 for fidelity and
0.72 for fluency (substantial agreement) but only 0.22 for simplicity,
a failed gate. The miss sits on the one axis the judge was never given:
the deterministic FK gate owns simplicity (ADR-0002). That fair number is
also a low ceiling. On ASSET's raw 15-worker ratings, human-human agreement
on simplicity is only 0.43 (Krippendorff alpha), against about 0.56 for the
other two axes, so simplicity is the hardest axis for humans too and the
judge's shortfall is a gap below 0.43, not below a perfect 1.0. Details in
[`docs/results/2026-07-15-asset-judge-kappa.md`](docs/results/2026-07-15-asset-judge-kappa.md)
and
[`docs/results/2026-07-22-asset-human-human-agreement.md`](docs/results/2026-07-22-asset-human-human-agreement.md).

## Judge and the real adapter

`SimplyPut.LLM.OpenRouter` follows the same adapter behaviour as the
stub, but calls OpenRouter's chat completions API for real. It's selected only when
`OPENROUTER_API_KEY` is set (`config/runtime.exs`); without a key the
Stub stays the default, so the green-clone path is unaffected.

The judge step is a second, separate model call that checks whether a
rewrite dropped a fact the original had. It's opt-in (`deps[:judge]`,
default off) and, when enabled, deliberately uses a different model
vendor than the rewriter (`openai/gpt-4o-mini` rewrites,
`anthropic/claude-haiku-4.5` judges by default, both configurable via env
var). A judge from the same vendor family as the rewriter rates its own
output more favorably, so the two are kept apart on purpose.

### Live sample

A 20-item run against the real OpenRouter adapter, judge on, rewriter
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
far easier (average grade 2.64) than the full 200-item corpus (average
9.53), so the FK numbers aren't comparable to the stub table above.

Read it for what it shows: the gate and the judge disagree.
Every one of these 20 passed the FK gate on the first attempt, and the
judge still called 60% of them meaning-lost. Passing the gate means a
rewrite is short enough. It says nothing about whether the rewrite kept
the original's facts. That gap is why the judge step exists as a second,
independent check on the gate.

```
OPENROUTER_API_KEY=sk-... mix test --only live
```

## Running it live

```
mix ecto.setup                 # creates the SQLite db, seeds the corpus
mix phx.server                 # http://localhost:4000/runs
```

In another shell, enqueue the batch and watch the dashboard fill in as
each job completes:

```
mix run -e "SimplyPut.Batch.enqueue_all()"
```

The `/runs` view streams the result table (SQLite via `Oban.Engines.Lite`,
no Postgres needed to try this locally) and subscribes to PubSub only after
the socket connects, so nothing queries the database during disconnected
mount.

## Why SQLite

The one value this repo cares about is a stranger cloning it and getting
to green without installing anything first. Postgres would break
that. `ecto_sqlite3` plus `Oban.Engines.Lite` keeps a real database and a
real background-job story without asking a reviewer to stand up a server.
Swapping to Postgres later is one dependency and one config block, not a
rewrite.

## What this repo is not

It's a capability demo, not a production deployment. `/runs` is the only
page, and it's read-only: a single view over a seeded corpus and its batch
results. The pass/held numbers above are specific to this stub run on this
corpus sample. They aren't a claim about any other engagement or dataset.

## License

MIT. See `LICENSE`. Citation metadata in `CITATION.cff`.
