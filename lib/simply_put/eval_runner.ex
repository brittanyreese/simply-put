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

  @grade_band {6.0, 8.0}
  @default_run_modes [:iterative, :single_shot, :self_refine]

  @doc """
  Runs the harness over the frozen Med-EASi test split. `:run_modes`
  defaults to all three (needed for the negative-control comparison);
  pass a single-element list to run just one. Returns the shared
  `batch_id` (all rows from one `run/1` call share it, however many
  run_modes were requested).
  """
  @spec run(keyword()) :: String.t()
  def run(opts \\ []) do
    run_modes = Keyword.get(opts, :run_modes, @default_run_modes)
    batch_id = Keyword.get_lazy(opts, :batch_id, fn -> Ecto.UUID.generate() end)
    items = test_split_items()

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
  against `report/1`'s output (needs all three run_modes in one report)
  and a `SimplyPut.JudgeValidation.judge_vs_human_kappa/0` result.

  Two of these are direct: grade-band compliance and iterative beating
  both negative controls. The other two use documented proxies given
  what this schema actually tracks: "moderate+ kappa" uses the
  Landis-Koch (1977) 0.41-0.60 "moderate" threshold per axis; "bounded
  omission" uses `faithfulness_score` as a proxy (no dedicated per-row
  omission flag on system outputs, only on human-labeled comparisons --
  faithfulness_score already blends SummaC + QAFactEval, and QAFactEval
  is specifically the metric chosen for its sensitivity to entity/number
  omissions, see the plan's KEY DECISION).
  """
  @spec success_gates(map(), map()) :: [%{gate: atom(), passed: boolean(), detail: String.t()}]
  def success_gates(report, judge_vs_human_kappa) do
    [
      grade_band_gate(report),
      iterative_beats_controls_gate(report),
      moderate_kappa_gate(judge_vs_human_kappa),
      bounded_omission_gate(report)
    ]
  end

  defp record_one(item, run_mode, batch_id) do
    case Plainish.run(item.source_text, run_mode: run_mode) do
      {status, result} when status in [:ok, :hold] -> Evaluation.record(item, result, batch_id)
      {:error, _reason} -> :skip
    end
  end

  defp test_split_items do
    Repo.all(from(c in CorpusItem, where: c.source == :med_easi and c.split == :test))
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

  defp grade_band_compliance_rate(rows) do
    {min_grade, max_grade} = @grade_band

    compliant =
      Enum.count(rows, fn row ->
        fk = row.fk_after_bp / 100
        smog = row.smog_bp / 100
        fk >= min_grade and fk <= max_grade and smog >= min_grade and smog <= max_grade
      end)

    compliant / length(rows)
  end

  defp grade_band_gate(report) do
    rate = get_in(report, [:iterative, :grade_band_compliance_rate]) || 0.0

    %{
      gate: :grade_band_compliance,
      passed: rate >= 0.5,
      detail: "iterative 6th-8th band compliance: #{Float.round(rate * 100, 1)}% (target >= 50%)"
    }
  end

  defp iterative_beats_controls_gate(report) do
    # Gate on iterative's 95% CI lower bound clearing each control's mean, not
    # bare point estimates: a negative-control comparison that ignores the CI
    # can call a within-noise difference a win.
    iterative_lower = ci_lower_or_nil(report, :iterative, :faithfulness_score)
    single_shot = mean_or_nil(report, :single_shot, :faithfulness_score)
    self_refine = mean_or_nil(report, :self_refine, :faithfulness_score)

    passed =
      not is_nil(iterative_lower) and
        at_least(iterative_lower, single_shot) and
        at_least(iterative_lower, self_refine)

    %{
      gate: :iterative_beats_controls,
      passed: passed,
      detail:
        "iterative faithfulness 95% CI lower #{inspect(iterative_lower)} vs single_shot mean #{inspect(single_shot)}, self_refine mean #{inspect(self_refine)}"
    }
  end

  defp moderate_kappa_gate(judge_vs_human_kappa) do
    axes = [:simplicity, :fidelity, :fluency]
    values = Enum.map(axes, &Map.get(judge_vs_human_kappa, &1, 0.0))
    passed = Enum.all?(values, &(&1 >= 0.41))

    %{
      gate: :moderate_judge_human_kappa,
      passed: passed,
      detail:
        "judge-vs-human kappa per axis: #{inspect(Enum.zip(axes, values))} (target >= 0.41, Landis-Koch \"moderate\")"
    }
  end

  defp bounded_omission_gate(report) do
    # CI lower bound, not the mean: a wide interval whose mean clears 0.7 but
    # whose lower bound sits well below it is not evidence of bounded omission.
    iterative_lower = ci_lower_or_nil(report, :iterative, :faithfulness_score)
    passed = not is_nil(iterative_lower) and iterative_lower >= 0.7

    %{
      gate: :bounded_omission,
      passed: passed,
      detail:
        "iterative faithfulness_score 95% CI lower (SummaC+QAFactEval proxy for omission) #{inspect(iterative_lower)} (target >= 0.7)"
    }
  end

  defp mean_or_nil(report, run_mode, metric), do: get_in(report, [run_mode, metric, :mean])

  defp ci_lower_or_nil(report, run_mode, metric) do
    case get_in(report, [run_mode, metric, :ci_95]) do
      {lower, _upper} -> lower
      nil -> nil
    end
  end

  # Fail-closed: a missing negative control (nil) is NOT a pass. Fail-open here
  # would score iterative as "beat" a control that never ran, inverting the
  # point of the control.
  defp at_least(_value, nil), do: false
  defp at_least(value, other), do: value >= other
end
