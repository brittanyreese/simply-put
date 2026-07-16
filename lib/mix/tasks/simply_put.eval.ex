defmodule Mix.Tasks.SimplyPut.Eval do
  @shortdoc "Runs the eval harness over the frozen Med-EASi test split and prints a report card"
  @moduledoc """
  Usage: mix simply_put.eval [--run-mode iterative|single_shot|self_refine]
  Usage: mix simply_put.eval --report BATCH_ID

  Without `--run-mode`, runs all three (iterative, single_shot,
  self_refine) under one shared batch_id, producing the negative-control
  comparison table. `--report BATCH_ID` skips the run and reprints the
  report, success gates, and dominance table for an already-recorded
  batch. Starts only `Ecto.Repo`, not the full application (Iron Law #12:
  never `app.start` from a mix task); `:inets`/`:ssl` are started
  explicitly, only when the judge-vs-human kappa gate has labels to score.
  """

  use Mix.Task

  import Ecto.Query

  alias SimplyPut.EvalRunner
  alias SimplyPut.HumanLabel
  alias SimplyPut.JudgeValidation
  alias SimplyPut.Repo

  @no_human_labels_kappa %{simplicity: 0.0, fidelity: 0.0, fluency: 0.0, items: 0}

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.config")
    Application.ensure_all_started(:ecto_sql)
    SimplyPut.Repo.start_link()

    {opts, _rest, _invalid} =
      OptionParser.parse(args, strict: [run_mode: :string, report: :string])

    batch_id =
      case opts[:report] do
        nil -> run_batch(opts)
        batch_id -> batch_id
      end

    report = EvalRunner.report(batch_id)

    Mix.shell().info("Batch: #{batch_id}")
    # The banner keys off the CURRENT adapter config, which only describes
    # rows written by this invocation -- meaningless for --report of a
    # batch recorded earlier (each row carries faithfulness_provider).
    if is_nil(opts[:report]), do: maybe_simulated_banner()
    print_report(report)
    print_gates(report)
    print_dominance(report)
  end

  defp run_batch(opts) do
    run_opts =
      case opts[:run_mode] do
        nil -> []
        mode -> [run_modes: [String.to_existing_atom(mode)]]
      end

    EvalRunner.run(run_opts)
  end

  defp maybe_simulated_banner do
    if SimplyPut.MetricProvider.simulated?() do
      Mix.shell().info(
        "\n*** SIMULATED: metric_provider is Stub (deterministic fixtures, no model " <>
          "inference). BERTScore, SLE, and faithfulness (SummaC+QAFactEval) are constants, " <>
          "not measurements. Wire a real :metric_provider before reporting these as results. ***"
      )
    end
  end

  defp print_report(report) do
    Enum.each(report, fn {run_mode, summary} ->
      Mix.shell().info("\n== #{run_mode} (#{summary.items} items) ==")
      Mix.shell().info("  FK after: #{format_summary(summary.fk_after)}")
      Mix.shell().info("  SARI: #{format_summary(summary.sari)}")
      Mix.shell().info("  BERTScore F1: #{format_summary(summary.bertscore_f1)}")
      Mix.shell().info("  SLE: #{format_summary(summary.sle)}")
      Mix.shell().info("  Faithfulness: #{format_summary(summary.faithfulness_score)}")

      Mix.shell().info(
        "  Grade-band (6-8) compliance: #{Float.round(summary.grade_band_compliance_rate * 100, 1)}%"
      )
    end)
  end

  defp format_summary(nil), do: "n/a"

  defp format_summary(%{mean: mean, ci_95: {lower, upper}}) do
    "#{Float.round(mean, 3)} (95% CI #{Float.round(lower, 3)}-#{Float.round(upper, 3)})"
  end

  defp print_gates(report) do
    gates = EvalRunner.success_gates(report, judge_vs_human_kappa())

    Mix.shell().info("\n== Success gates ==")

    Enum.each(gates, fn gate ->
      Mix.shell().info("  [#{status_label(gate.status)}] #{gate.gate}: #{gate.detail}")
    end)
  end

  defp status_label(:pass), do: "PASS"
  defp status_label(:fail), do: "FAIL"
  defp status_label(:not_evaluated), do: "N/E "

  # judge_vs_human_kappa/0 makes a paid LLM judge call per labeled row --
  # skip it (and the :inets/:ssl app starts it needs) when there is
  # nothing to score against.
  defp judge_vs_human_kappa do
    if Repo.exists?(from(l in HumanLabel, where: l.source_dataset in [:asset, :plaba_trec])) do
      Application.ensure_all_started(:inets)
      Application.ensure_all_started(:ssl)
      JudgeValidation.judge_vs_human_kappa()
    else
      @no_human_labels_kappa
    end
  end

  defp print_dominance(report) do
    Mix.shell().info("\n== Dominance: iterative vs. negative controls ==")

    report
    |> EvalRunner.dominance()
    |> Enum.each(fn {control, %{iterative: iterative, control: control_axes, relation: relation}} ->
      Mix.shell().info("  vs #{control}: #{relation}")

      Mix.shell().info(
        "    iterative:   grade #{fmt_pct(iterative.grade_compliance)}, " <>
          "faithfulness #{fmt(iterative.faithfulness)}"
      )

      Mix.shell().info(
        "    #{control}: grade #{fmt_pct(control_axes.grade_compliance)}, " <>
          "faithfulness #{fmt(control_axes.faithfulness)}"
      )
    end)
  end

  defp fmt_pct(nil), do: "n/a"
  defp fmt_pct(value), do: "#{Float.round(value * 100, 1)}%"

  defp fmt(nil), do: "n/a"
  defp fmt(value), do: Float.round(value, 3)
end
