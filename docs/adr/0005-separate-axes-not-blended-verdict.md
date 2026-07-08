# ADR-0005: Score readability and faithfulness on separate axes, never a blended verdict

## Status

Accepted

## Context

The eval harness scores each rewrite on several axes: grade compliance (the
FK ceiling), faithfulness (source-to-candidate NLI entailment), omission
(the reverse direction), and reference metrics (SARI, BERTScore). An early
success gate, `iterative_beats_controls`, compared the iterative loop against
its negative controls on faithfulness alone and returned one pass or fail.

That gate was wrong in two ways. The demonstration plan asks iterative to
beat the controls on readability and faithfulness together, not on
faithfulness by itself. And the literature the harness rests on is blunter
still: score simplicity and meaning-preservation separately, and never trust
one blended number (Cripwell et al. 2024, arXiv:2404.03278, and the
multicriteria evaluation of generation at arXiv:2506.18082). A single scalar
hides which axis moved. The dominant real-world failure in plain-language rewriting is silent
omission, and a faithfulness-weighted average is exactly the kind of number
that can mask it.

## Decision

Report the axes apart.

`success_gates/2` keeps only the checks that read one axis each: grade
compliance, bounded omission, and judge-versus-human kappa. The comparison of
iterative against its negative controls (`single_shot`, `self_refine`) is no
longer a gate. `dominance/1` reports it as a Pareto relation over two separate
numbers, grade compliance and mean faithfulness:

- `iterative_dominates`: no worse on either axis, better on one
- `iterative_dominated`: the reverse
- `tradeoff`: each side wins one axis
- `tie`: equal on both

There is no blended scalar and no tunable weight.

## Consequences

- A reader sees the tradeoff rather than a verdict that buries it. When
  iterative reads easier but gives up a little faithfulness, the relation says
  `tradeoff` and shows both numbers.
- The negative-control claim stays honest about its strength. On the first
  bounded run iterative dominated `single_shot` but only traded with
  `self_refine`, so the "external feedback beats self-critique" claim reads as
  unproven at that sample size instead of being forced green.
- No margin knob means there is nothing to tune toward a passing result, which
  matches the repo's refusal to let the model, or the metric, grade its own
  homework (ADR-0002).
- Faithfulness still has a hard floor through the separate `bounded_omission`
  gate. Taking it out of the control comparison drops a misframed test, not the
  guardrail.
