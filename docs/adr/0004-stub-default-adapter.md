# ADR-0004: Stub is the default adapter, OpenRouter is opt-in

## Status

Accepted

## Context

`mix test` on a fresh clone needs to go green with no API key, no
network access, and no cost to the person running it. But the repo also
needs a real adapter to demonstrate the pipeline against an actual model,
since the deterministic gate alone can't show what a real rewrite (versus
a synonym swap) looks like.

## Decision

`SimplyPut.LLM` is a behaviour with two implementations:

- `SimplyPut.LLM.Stub`: deterministic synonym swap plus sentence
  splitting, runs entirely offline and needs no key. Default in
  `config/config.exs` (implicit:
  `Application.get_env(:simply_put, :llm, SimplyPut.LLM.Stub)`).
- `SimplyPut.LLM.OpenRouter`: real API adapter, selected only when
  `OPENROUTER_API_KEY` is present (`config/runtime.exs`). Tests that hit it
  are tagged `:live` and excluded by default (`test/test_helper.exs`),
  run explicitly with `mix test --only live`.

## Consequences

- The green-clone path (`git clone && mix deps.get && mix test`) never
  makes a network call and never costs money, regardless of what's in a
  developer's environment. The key's mere presence in `.env` doesn't
  change CI or default test behavior, since CI never sets it.
- The Stub's honest-metrics run (93.5% pass) is not directly comparable to
  a live OpenRouter run; a synonym swap can shorten a sentence but can't
  restructure an idea, which is exactly the gap a real model closes on the
  hardest (grade 12.5+) source texts.
- Swapping which adapter is live is one env var, not a code change.
