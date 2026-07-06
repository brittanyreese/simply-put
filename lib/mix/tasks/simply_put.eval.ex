defmodule Mix.Tasks.SimplyPut.Eval do
  @shortdoc "Runs the eval harness over the frozen Med-EASi test split and prints a report card"
  @moduledoc """
  Usage: mix simply_put.eval [--run-mode iterative|single_shot|self_refine]

  Without `--run-mode`, runs all three (iterative, single_shot,
  self_refine) under one shared batch_id, producing the negative-control
  comparison table. Starts only `Ecto.Repo`, not the full application
  (Iron Law #12: never `app.start` from a mix task).
  """

  use Mix.Task

  alias SimplyPut.EvalRunner

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.config")
    Application.ensure_all_started(:ecto_sql)
    SimplyPut.Repo.start_link()

    {opts, _rest, _invalid} = OptionParser.parse(args, strict: [run_mode: :string])

    run_opts =
      case opts[:run_mode] do
        nil -> []
        mode -> [run_modes: [String.to_existing_atom(mode)]]
      end

    batch_id = EvalRunner.run(run_opts)
    report = EvalRunner.report(batch_id)

    Mix.shell().info("Batch: #{batch_id}")
    maybe_simulated_banner()
    print_report(report)
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
end
