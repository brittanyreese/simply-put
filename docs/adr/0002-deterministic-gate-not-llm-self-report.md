# ADR-0002: The gate is a pure function, never the model's own claim

## Status

Accepted

## Context

An LLM asked to rewrite text "at grade level X" can also be asked whether
it succeeded, but that self-report isn't verifiable: the same call that
produced the rewrite would be grading its own homework. A reviewer of this
repo shouldn't have to trust a model's word that a rewrite hit its target.

## Decision

`SimplyPut.Readability.flesch_kincaid/1` is the sole authority on whether a
rewrite passes. It is:

- pure (`String.t() -> float()`), depending only on the standard library,
- public and short enough to read in one sitting,
- backed by `Readability.demo/0`, a hand-traceable self-check anyone can
  run in `iex -S mix` and verify against a known example by hand.

`Plainish.run/2` calls the gate before and after every rewrite attempt.
The LLM never decides pass/fail. The gate does.

## Consequences

- The gate is a proxy (sentence and word length), not a comprehension
  test, and the README states this plainly instead of overselling the gate.
- Every `:passed` result in this repo is independently checkable by anyone
  reading `readability.ex`, without needing to trust the LLM call that
  produced the rewrite.
- Feedback into retries (`Readability.critique/2`) is also derived from the
  gate's own numbers, not from asking the model to self-assess.
