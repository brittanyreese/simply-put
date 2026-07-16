defmodule SimplyPut.JudgeValidation do
  @moduledoc """
  Judge-vs-human and human-vs-human kappa, plus position-swap and
  verbosity-bias tests, over the ASSET/PLABA-labeled `human_labels`
  subset. See `docs/research/2026-07-04-judge-validation-datasets.md` for
  why these existing datasets instead of new manual annotation. The
  human-vs-human ceiling is reported alongside judge-vs-human agreement
  because human raters disagree with each other too: judge kappa is read
  against that ceiling, not against 1.0.
  """

  import Ecto.Query

  alias SimplyPut.HumanLabel
  alias SimplyPut.LLM
  alias SimplyPut.Repo
  alias SimplyPut.Stats

  @type kappa_report :: %{
          simplicity: float(),
          fidelity: float(),
          fluency: float(),
          items: non_neg_integer()
        }

  @doc """
  Judge-vs-human kappa per axis: scores every primary-labeled (ASSET or
  PLABA TREC) pair with the configured judge and compares to that item's
  human rating. Items where the judge call errors are skipped, not
  crashed on.
  """
  @spec judge_vs_human_kappa() :: kappa_report()
  def judge_vs_human_kappa do
    pairs =
      primary_labels()
      |> Enum.map(fn label ->
        case LLM.score(label.original_text, label.candidate_text) do
          {:ok, score} -> {label, score}
          {:error, _reason} -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    axis_kappas(pairs)
  end

  @doc """
  Human-vs-human kappa per axis: pairs each primary-labeled item with its
  second-rater (`source_dataset: :self_labeled`) row on the same
  `external_item_id`, if one exists. This is the agreement ceiling
  judge-vs-human kappa should be read against, not a standard of "perfect"
  agreement.
  """
  @spec human_vs_human_kappa() :: kappa_report()
  def human_vs_human_kappa do
    primary_by_item = primary_labels() |> Map.new(&{&1.external_item_id, &1})

    pairs =
      second_rater_labels()
      |> Enum.map(fn second -> {Map.get(primary_by_item, second.external_item_id), second} end)
      |> Enum.reject(fn {first, _second} -> is_nil(first) end)

    axis_kappas(pairs)
  end

  @doc """
  Position-swap bias test: scores the judge on `{original, candidate}` and
  again on `{candidate, original}` for each pair, and reports how often
  ANY axis flips when the two texts trade places. A judge robust to order
  (not content) should have a near-zero flip rate.
  """
  @spec position_swap_test([{String.t(), String.t()}]) :: %{
          flip_rate: float(),
          pairs_tested: non_neg_integer()
        }
  def position_swap_test(pairs) do
    flips =
      pairs
      |> Enum.map(&swap_flip?/1)
      |> Enum.reject(&is_nil/1)

    %{flip_rate: safe_div(Enum.count(flips, & &1), length(flips)), pairs_tested: length(flips)}
  end

  @doc """
  Verbosity-bias test: for each `{original, candidate, padded_candidate}`
  triple (`padded_candidate` is `candidate` plus filler, no new content),
  reports how often the judge scores the padded version strictly higher
  on any axis. A judge that rewards length over substance shows a high
  rate here.
  """
  @spec verbosity_bias_test([{String.t(), String.t(), String.t()}]) :: %{
          bias_rate: float(),
          triples_tested: non_neg_integer()
        }
  def verbosity_bias_test(triples) do
    biases =
      triples
      |> Enum.map(&verbosity_biased?/1)
      |> Enum.reject(&is_nil/1)

    %{
      bias_rate: safe_div(Enum.count(biases, & &1), length(biases)),
      triples_tested: length(biases)
    }
  end

  defp primary_labels do
    Repo.all(from(l in HumanLabel, where: l.source_dataset in [:asset, :plaba_trec]))
  end

  defp second_rater_labels do
    Repo.all(from(l in HumanLabel, where: l.source_dataset == :self_labeled))
  end

  defp axis_kappas([]), do: %{simplicity: 0.0, fidelity: 0.0, fluency: 0.0, items: 0}

  defp axis_kappas(pairs) do
    %{
      simplicity: Stats.cohens_kappa(axis(pairs, 0, :simplicity), axis(pairs, 1, :simplicity)),
      fidelity: Stats.cohens_kappa(axis(pairs, 0, :fidelity), axis(pairs, 1, :fidelity)),
      fluency: Stats.cohens_kappa(axis(pairs, 0, :fluency), axis(pairs, 1, :fluency)),
      items: length(pairs)
    }
  end

  defp axis(pairs, position, field), do: Enum.map(pairs, &Map.get(elem(&1, position), field))

  defp swap_flip?({original, candidate}) do
    with {:ok, forward} <- LLM.score(original, candidate),
         {:ok, swapped} <- LLM.score(candidate, original) do
      forward.simplicity != swapped.simplicity or forward.fidelity != swapped.fidelity or
        forward.fluency != swapped.fluency
    else
      {:error, _reason} -> nil
    end
  end

  defp verbosity_biased?({original, candidate, padded_candidate}) do
    with {:ok, plain} <- LLM.score(original, candidate),
         {:ok, padded} <- LLM.score(original, padded_candidate) do
      padded.simplicity > plain.simplicity or padded.fidelity > plain.fidelity or
        padded.fluency > plain.fluency
    else
      {:error, _reason} -> nil
    end
  end

  defp safe_div(_numerator, 0), do: 0.0
  defp safe_div(numerator, denominator), do: numerator / denominator
end
