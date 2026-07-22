defmodule SimplyPut.Stats do
  @moduledoc """
  Judge-validation statistics: quadratically-weighted Cohen's kappa (for
  ordinal 1..5 ratings) and a percentile bootstrap confidence interval.

  Quadratic weighting, not plain kappa: a subjective 1..5 rubric needs an
  ordinal-aware agreement measure. A 1-vs-5 disagreement is worse than a
  3-vs-4 one, and plain kappa treats them identically. The human-label-
  variation literature motivates this.

  Gotcha (verified while writing this module's tests, not just a footnote):
  kappa needs variance in BOTH raters' marginals. If one rater's ratings
  are constant (e.g. a judge that always outputs the same score for an
  axis), kappa is mathematically 0 no matter how close the other rater's
  values are -- it isn't a bug, it's kappa correcting for chance agreement
  when one side never varies. If a judge-vs-human kappa comes back near 0,
  check the judge's score distribution for that axis before concluding the
  judge disagrees with humans.
  """

  @scale 1..5

  @doc """
  Self-check: two raters, 10 items, ratings on a 1..5 scale, close but not
  identical. Confirms the formula is wired correctly (positive kappa for
  clearly-agreeing raters).
  """
  @spec demo() :: :ok
  def demo do
    rater_a = [3, 3, 4, 4, 5, 5, 3, 4, 5, 3]
    rater_b = [3, 4, 4, 4, 5, 4, 3, 4, 5, 3]

    kappa = cohens_kappa(rater_a, rater_b)
    true = kappa > 0.5
    :ok
  end

  @doc """
  Quadratically-weighted Cohen's kappa between two equal-length rating
  vectors on the fixed 1..5 scale (Cohen, 1968).

      kappa_w = 1 - (sum of w_ij * observed_ij) / (sum of w_ij * expected_ij)
      w_ij = (i - j)^2 / (max_rank - min_rank)^2

  `expected_ij` is the count expected under independence given the
  marginal totals: `row_total_i * col_total_j / n`.
  """
  @spec cohens_kappa([1..5], [1..5]) :: float()
  def cohens_kappa(rater_a, rater_b) when length(rater_a) == length(rater_b) do
    n = length(rater_a)
    observed = rater_a |> Enum.zip(rater_b) |> Enum.frequencies()
    row_totals = Enum.frequencies(rater_a)
    col_totals = Enum.frequencies(rater_b)

    {weighted_observed, weighted_expected} =
      for i <- @scale, j <- @scale, reduce: {0.0, 0.0} do
        {obs_acc, exp_acc} ->
          w = weight(i, j)
          o = Map.get(observed, {i, j}, 0)
          e = Map.get(row_totals, i, 0) * Map.get(col_totals, j, 0) / n

          {obs_acc + w * o, exp_acc + w * e}
      end

    if weighted_expected == 0.0, do: 1.0, else: 1 - weighted_observed / weighted_expected
  end

  @doc """
  Percentile bootstrap confidence interval for the mean of `values`, via
  `resamples` resamplings with replacement, at `confidence` (e.g. `0.95`).
  Returns `{lower, upper}`.
  """
  @spec bootstrap_ci([number()], pos_integer(), float()) :: {float(), float()}
  def bootstrap_ci(values, resamples, confidence) when resamples > 0 do
    n = length(values)
    values_tuple = List.to_tuple(values)

    means =
      for _ <- 1..resamples do
        1..n
        |> Enum.map(fn _ -> elem(values_tuple, :rand.uniform(n) - 1) end)
        |> average()
      end
      |> Enum.sort()

    alpha = 1 - confidence
    lower_index = max(trunc(alpha / 2 * resamples), 0)
    upper_index = min(trunc((1 - alpha / 2) * resamples), resamples - 1)

    {Enum.at(means, lower_index), Enum.at(means, upper_index)}
  end

  defp weight(i, j) do
    span = Enum.max(@scale) - Enum.min(@scale)
    (i - j) * (i - j) / (span * span)
  end

  defp average(numbers), do: Enum.sum(numbers) / length(numbers)
end
