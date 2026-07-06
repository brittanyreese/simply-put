# Context

Single-context repo. Domain vocabulary and decisions live here and in
`docs/adr/`; see `docs/agents/domain.md` for how skills should consume them.

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
- **Judge**: a second, separate model call (`LLM.judge/2`) that checks
  whether a rewrite dropped a fact the original had. Opt-in
  (`deps[:judge]`, default off). Produces a `verdict`, not a `score`: a
  preserved/lost call, not a number.
- **Verdict**: `%{fk_pass: boolean(), meaning_preserved: boolean()}`,
  attached to a `Plainish.Result` only when the judge is enabled. Two
  independent axes; the gate can pass while meaning is lost, or the reverse.
- **Adapter seam**: `SimplyPut.LLM` behaviour, with `Stub` (deterministic,
  no network, default) and `OpenRouter` (real API, selected only when
  `OPENROUTER_API_KEY` is set) as the two implementations. Call it
  "adapter," not "provider" or "backend": the word signals swappability.
- **Corpus item**: one seeded source text (`CorpusItem`) from the
  CommonLit CLEAR Corpus, the input side of a run.
- **Run result**: one `Plainish.run/2` outcome persisted against a corpus
  item (`RunResult`), upserted per `corpus_item_id` so a retry replaces
  rather than duplicates.
- **Batch**: one `Batch.enqueue_all/1` fan-out, one `RewriteWorker` job
  per corpus item, all tagged with a shared `batch_id`.

## Decisions

See `docs/adr/` for the full rationale behind each of these:

- [ADR-0001](docs/adr/0001-sqlite-over-postgres.md): SQLite, not Postgres
- [ADR-0002](docs/adr/0002-deterministic-gate-not-llm-self-report.md): the
  gate is a pure function, never the model's own claim
- [ADR-0003](docs/adr/0003-judge-cross-vendor.md): judge and rewriter use
  different model vendors
- [ADR-0004](docs/adr/0004-stub-default-adapter.md): the default adapter
  is Stub, OpenRouter is opt-in
