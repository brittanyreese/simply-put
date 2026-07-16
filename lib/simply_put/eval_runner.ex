defmodule SimplyPut.EvalRunner do
  @moduledoc """
  Runs the eval harness over the frozen Med-EASi test split and reports a
  card: per-metric mean + 95% bootstrap CI, grade-band compliance rate,
  and (since all run_modes share one `batch_id` by default) a
  negative-control comparison table. Called from `mix simply_put.eval`;
  also directly callable from IEx.
  """

  import Ecto.Query

  alias SimplyPut.CorpusItem
  alias SimplyPut.Evaluation
  alias SimplyPut.Plainish
  alias SimplyPut.Repo
  alias SimplyPut.RewriteEvaluation
  alias SimplyPut.Stats

  @grade_ceiling 8.0
  @default_run_modes [:iterative, :single_shot, :self_refine]

  @doc """
  Runs the harness over the frozen Med-EASi test split. `:run_modes`
  defaults to all three (needed for the negative-control comparison);
  pass a single-element list to run just one. `:limit` caps how many test
  items run (for a quick bounded card before the full split); omit for all.
  Returns the shared `batch_id` (all rows from one `run/1` call share it,
  however many run_modes were requested).
  """
  @spec run(keyword()) :: String.t()
  def run(opts \\ []) do
    run_modes = Keyword.get(opts, :run_modes, @default_run_modes)
    batch_id = Keyword.get_lazy(opts, :batch_id, fn -> Ecto.UUID.generate() end)
    items = test_split_items(Keyword.get(opts, :limit))

    for run_mode <- run_modes, item <- items do
      record_one(item, run_mode, batch_id)
    end

    batch_id
  end

  @doc """
  Per-run-mode report card for `batch_id`: item count, mean + 95%
  bootstrap CI for each populated metric, and grade-band (6th-8th, per
  the demonstration plan) compliance rate.
  """
  @spec report(String.t()) :: %{SimplyPut.Plainish.run_mode() => map()}
  def report(batch_id) do
    batch_id
    |> rows()
    |> Enum.group_by(& &1.run_mode)
    |> Map.new(fn {run_mode, rows} -> {run_mode, run_mode_report(rows)} end)
  end

  @doc """
  Phase 1 success gates from the plan's demonstration doc, evaluated
  against `report/1`'s output and a
  `SimplyPut.JudgeValidation.judge_vs_human_kappa/0` result.

  Each gate reports a `status` of `:pass`, `:fail`, or `:not_evaluated` --
  the last is not a failure, it means there was no data to judge against.
  `moderate_kappa_gate/1` is `:not_evaluated` when no `human_labels` rows
  are loaded (nothing to compare the judge to), so an empty labels table
  reads as "not measured", not "failed".

  Grade compliance gates on the FK ceiling. "moderate+ kappa" uses the
  Landis-Koch (1977) 0.41-0.60 "moderate" threshold per axis. "bounded
  omission" gates on `omission_score`, the reverse-direction NLI entailment
  (candidate -> source): high means the rewrite still supports the source,
  low means it dropped content, a distinct axis from `faithfulness_score`
  (source -> candidate), which catches unsupported *additions*.

  How iterative compares to the negative controls is deliberately not a gate
  here. It is a two-axis tradeoff (grade against faithfulness), and the
  literature this repo rests on scores those axes apart and warns against a
  blended verdict (Cripwell et al. 2024; ADR-0005). See `dominance/1` for
  that comparison, reported as a Pareto relation over separate axes.
  """
  @spec success_gates(map(), map()) :: [
          %{gate: atom(), status: :pass | :fail | :not_evaluated, detail: String.t()}
        ]
  def success_gates(report, judge_vs_human_kappa) do
    [
      grade_band_gate(report),
      moderate_kappa_gate(judge_vs_human_kappa),
      bounded_omission_gate(report)
    ]
  end

  @doc """
  Iterative against each negative control on the two axes the plan cares
  about, grade compliance and mean faithfulness, kept as separate numbers
  with no blended score. `relation` is the Pareto relation on those means:

    * `:iterative_dominates` -- at least as good on both axes, better on one
    * `:iterative_dominated` -- the reverse
    * `:tradeoff` -- each side wins one axis
    * `:tie` -- equal on both
    * `:incomparable` -- an axis is missing (a control did not run)

  Descriptive, not pass/fail. The axes stay apart on purpose (Cripwell et
  al. 2024; ADR-0005) so no single verdict hides which axis moved.
  """
  @spec dominance(map()) :: %{(:single_shot | :self_refine) => map()}
  def dominance(report) do
    iterative = axes(report, :iterative)

    for control <- [:single_shot, :self_refine], into: %{} do
      control_axes = axes(report, control)

      {control,
       %{iterative: iterative, control: control_axes, relation: relation(iterative, control_axes)}}
    end
  end

  defp record_one(item, run_mode, batch_id) do
    case Plainish.run(item.source_text, run_mode: run_mode) do
      {status, result} when status in [:ok, :hold] -> Evaluation.record(item, result, batch_id)
      {:error, _reason} -> :skip
    end
  end

  defp test_split_items(nil) do
    Repo.all(from(c in CorpusItem, where: c.source == :med_easi and c.split == :test))
  end

  defp test_split_items(limit) when is_integer(limit) do
    Repo.all(
      from(c in CorpusItem,
        where: c.source == :med_easi and c.split == :test,
        order_by: c.id,
        limit: ^limit
      )
    )
  end

  defp rows(batch_id) do
    Repo.all(from(e in RewriteEvaluation, where: e.batch_id == ^batch_id))
  end

  defp run_mode_report(rows) do
    %{
      items: length(rows),
      fk_after: bp_summary(rows, :fk_after_bp),
      sari: bp_summary(rows, :sari_bp),
      bertscore_f1: bp_summary(rows, :bertscore_f1_bp),
      sle: bp_summary(rows, :sle_bp),
      faithfulness_score: decimal_summary(rows, :faithfulness_score),
      omission_score: decimal_summary(rows, :omission_score),
      grade_band_compliance_rate: grade_band_compliance_rate(rows)
    }
  end

  defp bp_summary(rows, field) do
    rows
    |> Enum.map(&Map.get(&1, field))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&(&1 / 100))
    |> summary()
  end

  defp decimal_summary(rows, field) do
    rows
    |> Enum.map(&Map.get(&1, field))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&Decimal.to_float/1)
    |> summary()
  end

  defp summary([]), do: nil

  defp summary(values) do
    mean = Enum.sum(values) / length(values)
    {lower, upper} = Stats.bootstrap_ci(values, 1000, 0.95)
    %{mean: mean, ci_95: {lower, upper}}
  end

  defp grade_band_compliance_rate([]), do: 0.0

  # Ceiling, not a band: a rewrite that reads *easier* than the target is a
  # success, not a failure, so there is no floor. FK is the primary scale;
  # SMOG runs 1-3 grades higher and is noisy on short texts, so requiring both
  # jointly is near-unsatisfiable -- SMOG is reported separately, not gated here.
  defp grade_band_compliance_rate(rows) do
    compliant = Enum.count(rows, fn row -> row.fk_after_bp / 100 <= @grade_ceiling end)
    compliant / length(rows)
  end

  defp grade_band_gate(report) do
    rate = get_in(report, [:iterative, :grade_band_compliance_rate]) || 0.0

    %{
      gate: :grade_band_compliance,
      status: gate_status(rate >= 0.5),
      detail:
        "iterative FK grade <= #{@grade_ceiling} compliance: #{Float.round(rate * 100, 1)}% (target >= 50%)"
    }
  end

  defp moderate_kappa_gate(%{items: 0}) do
    %{
      gate: :moderate_judge_human_kappa,
      status: :not_evaluated,
      detail:
        "no human_labels loaded; import ASSET/PLABA labels to evaluate " <>
          "(mix simply_put.import_human_labels)"
    }
  end

  defp moderate_kappa_gate(judge_vs_human_kappa) do
    axes = [:simplicity, :fidelity, :fluency]
    values = Enum.map(axes, &Map.get(judge_vs_human_kappa, &1, 0.0))

    %{
      gate: :moderate_judge_human_kappa,
      status: gate_status(Enum.all?(values, &(&1 >= 0.41))),
      detail:
        "judge-vs-human kappa per axis: #{inspect(Enum.zip(axes, values))} (target >= 0.41, Landis-Koch \"moderate\")"
    }
  end

  defp bounded_omission_gate(report) do
    # CI lower bound, not the mean: a wide interval whose mean clears 0.7 but
    # whose lower bound sits well below it is not evidence of bounded omission.
    # omission_score is the reverse-direction entailment (candidate -> source):
    # high means the rewrite still supports the source, low means it dropped
    # content -- the direction that actually detects omission.
    iterative_lower = ci_lower_or_nil(report, :iterative, :omission_score)

    %{
      gate: :bounded_omission,
      status: gate_status(not is_nil(iterative_lower) and iterative_lower >= 0.7),
      detail:
        "iterative omission_score 95% CI lower (reverse-entailment candidate -> source) #{inspect(iterative_lower)} (target >= 0.7)"
    }
  end

  defp gate_status(true), do: :pass
  defp gate_status(false), do: :fail

  defp axes(report, mode) do
    %{
      grade_compliance: get_in(report, [mode, :grade_band_compliance_rate]),
      faithfulness: get_in(report, [mode, :faithfulness_score, :mean])
    }
  end

  defp relation(%{grade_compliance: ig, faithfulness: iff}, %{
         grade_compliance: cg,
         faithfulness: cf
       })
       when is_nil(ig) or is_nil(iff) or is_nil(cg) or is_nil(cf),
       do: :incomparable

  defp relation(iterative, control) do
    grade = cmp(iterative.grade_compliance, control.grade_compliance)
    faithfulness = cmp(iterative.faithfulness, control.faithfulness)

    cond do
      grade == :eq and faithfulness == :eq -> :tie
      grade != :lt and faithfulness != :lt -> :iterative_dominates
      grade != :gt and faithfulness != :gt -> :iterative_dominated
      true -> :tradeoff
    end
  end

  defp cmp(a, b) when a > b, do: :gt
  defp cmp(a, b) when a < b, do: :lt
  defp cmp(_a, _b), do: :eq

  defp ci_lower_or_nil(report, run_mode, metric) do
    case get_in(report, [run_mode, metric, :ci_95]) do
      {lower, _upper} -> lower
      nil -> nil
    end
  end
end
