defmodule SimplyPut.Metrics do
  @moduledoc """
  Native evaluation metrics: SARI (n-gram add/keep/delete F1 against a
  source and reference) and grade-band compliance. Model-based metrics
  (SummaC, BERTScore, SLE, QAFactEval) come from `SimplyPut.MetricProvider`
  (the Phase M Bumblebee adapter), not computed here.
  """

  alias SimplyPut.Readability

  @ngram_orders 1..4

  @doc """
  SARI (Xu et al. 2016): n-gram (1-4) add/keep/delete F1 comparing
  `candidate` against `source` and a single `reference`, averaged across
  n-gram orders. Returns a 0..1 float.

  Single-reference, not the paper's typical multi-reference setup --
  Med-EASi ships one reference per item, not several.
  """
  @spec sari(String.t(), String.t(), String.t()) :: float()
  def sari(candidate, source, reference) do
    @ngram_orders
    |> Enum.map(&sari_at_order(candidate, source, reference, &1))
    |> average()
  end

  @doc """
  SARI at a single n-gram order (exposed for hand-verified unit tests --
  `sari/3` is the average across orders 1-4 and is harder to hand-compute
  directly).
  """
  @spec sari_at_order(String.t(), String.t(), String.t(), pos_integer()) :: float()
  def sari_at_order(candidate, source, reference, n) do
    cand = ngram_counts(candidate, n)
    src = ngram_counts(source, n)
    ref = ngram_counts(reference, n)

    add = add_f1(cand, src, ref)
    keep = keep_f1(cand, src, ref)
    del = delete_precision(cand, src, ref)

    (add + keep + del) / 3
  end

  @doc """
  Whether `text`'s FK and SMOG grades both fall within `{min_grade,
  max_grade}` (inclusive) -- e.g. `grade_band_compliance(text, {6.0, 8.0})`
  for a 6th-8th grade band.
  """
  @spec grade_band_compliance(String.t(), {number(), number()}) :: boolean()
  def grade_band_compliance(text, {min_grade, max_grade}) do
    fk = Readability.flesch_kincaid(text)
    smog = Readability.smog(text)

    fk >= min_grade and fk <= max_grade and smog >= min_grade and smog <= max_grade
  end

  defp add_f1(cand, src, ref) do
    added_by_candidate = subtract(cand, src)
    should_add = subtract(ref, src)

    correct = intersect_count(added_by_candidate, ref)
    precision = safe_div(correct, count_total(added_by_candidate))
    recall = safe_div(correct, count_total(should_add))
    f1(precision, recall)
  end

  defp keep_f1(cand, src, ref) do
    kept_by_candidate = intersect(cand, src)
    should_keep = intersect(src, ref)

    correct = intersect_count(kept_by_candidate, ref)
    precision = safe_div(correct, count_total(kept_by_candidate))
    recall = safe_div(correct, count_total(should_keep))
    f1(precision, recall)
  end

  defp delete_precision(cand, src, ref) do
    deleted_by_candidate = subtract(src, cand)
    should_delete = subtract(src, ref)

    correct = intersect_count(deleted_by_candidate, should_delete)
    safe_div(correct, count_total(deleted_by_candidate))
  end

  defp ngram_counts(text, n) do
    text
    |> tokenize()
    |> Enum.chunk_every(n, 1, :discard)
    |> Enum.frequencies()
  end

  defp tokenize(text) do
    text |> String.downcase() |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)
  end

  defp subtract(a, b) do
    a
    |> Enum.map(fn {gram, count} -> {gram, max(count - Map.get(b, gram, 0), 0)} end)
    |> Enum.reject(fn {_gram, count} -> count == 0 end)
    |> Map.new()
  end

  defp intersect(a, b) do
    a
    |> Enum.map(fn {gram, count} -> {gram, min(count, Map.get(b, gram, 0))} end)
    |> Enum.reject(fn {_gram, count} -> count == 0 end)
    |> Map.new()
  end

  defp intersect_count(a, b) do
    Enum.reduce(a, 0, fn {gram, count}, acc -> acc + min(count, Map.get(b, gram, 0)) end)
  end

  defp count_total(counts), do: Enum.reduce(counts, 0, fn {_gram, count}, acc -> acc + count end)

  # Standard SARI convention: when nothing was attempted (denominator 0),
  # treat the score as vacuously satisfied (1.0), not a failure. The other
  # side of a precision/recall pair still penalizes genuine mismatches --
  # e.g. if nothing was kept but the reference required keeping something,
  # recall (not this vacuous precision) drags F1 down correctly.
  defp safe_div(_numerator, 0), do: 1.0
  defp safe_div(numerator, denominator), do: numerator / denominator

  defp f1(precision, recall) do
    if precision + recall == 0.0, do: 0.0, else: 2 * precision * recall / (precision + recall)
  end

  defp average(numbers), do: Enum.sum(numbers) / length(numbers)
end
