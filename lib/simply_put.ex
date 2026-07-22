defmodule SimplyPut do
  @moduledoc """
  Plain-language readability rig. A rewrite loop lowers text to a target
  reading grade, and a deterministic Flesch-Kincaid gate
  (`SimplyPut.Readability.flesch_kincaid/1`) decides whether it passes, so the
  claim is checked by a pure function rather than the model's own word.

  The pieces:

    * `SimplyPut.Readability` -- the gate and its critique feedback.
    * `SimplyPut.Plainish` -- the gated rewrite loop (`iterative`) and its
      `single_shot` / `self_refine` negative controls.
    * `SimplyPut.LLM` -- the adapter seam (`Stub` by default, `OpenRouter` when
      a key is set).
    * `SimplyPut.EvalRunner` -- the benchmark harness over the Med-EASi test
      split, with per-axis metrics, dominance, and paired significance.

  See `README.md` for the full architecture and results.
  """
end
