# ADR-0003: Judge and rewriter use different model vendors

## Status

Accepted

## Context

The judge step (`LLM.judge/2`) checks whether a rewrite dropped a fact the
original had, a meaning-preservation check the deterministic FK gate can't
do, since sentence/word length says nothing about content. But an
LLM judge evaluating output from a model in its own vendor family rates it
more favorably (self-preference bias, documented in Wataoka et al. 2024).
That bias would make the judge's "preserved" verdict less trustworthy
exactly where it matters most.

## Decision

`SimplyPut.LLM.OpenRouter` defaults the rewrite and judge calls to
different model vendors: `openai/gpt-4o-mini` rewrites,
`anthropic/claude-haiku-4.5` judges. Both are configurable independently
via `OPENROUTER_REWRITE_MODEL` / `OPENROUTER_JUDGE_MODEL`, but the default
pairing is deliberately cross-vendor, not same-vendor-different-size.

## Consequences

- A caller who overrides both env vars to the same vendor loses this
  guarantee silently: there's no runtime check enforcing cross-vendor,
  only the default. Acceptable for a demo repo; would need an explicit
  guard if this pattern were used in a context where the override is a
  realistic misconfiguration risk.
- The judge is opt-in (`deps[:judge]`, default off) and orthogonal to this
  decision. This ADR only covers which vendors are used once it's on.
