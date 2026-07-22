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
  never `app.start` from a mix task). A real (non-Stub) metric run also
  starts `:inets`/`:ssl`/`:exla`/`:bumblebee` up front (Bumblebee needs its
  own `:httpc_bumblebee` profile to download checkpoints); a Stub run starts
  nothing extra. The kappa gate additionally ensures `:inets`/`:ssl` when it
  has labels to score.
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
    print_dominance(report, batch_id)
  end

  defp run_batch(opts) do
    ensure_metric_provider_started()

    run_opts =
      case opts[:run_mode] do
        nil -> []
        mode -> [run_modes: [String.to_existing_atom(mode)]]
      end

    EvalRunner.run(run_opts)
  end

  # A real (non-Stub) metric provider loads checkpoints over HTTP, which needs
  # the :bumblebee application running: it owns the :httpc_bumblebee profile
  # Bumblebee downloads through. Without this the first download crashes the
  # Servings GenServer ("no process :httpc_bumblebee"). The task boots only
  # :ecto_sql by default (Iron Law #12), so start the rest here, and only for
  # a real run. Stub runs need nothing extra. `--report` never reaches here.
  defp ensure_metric_provider_started do
    if SimplyPut.MetricProvider.simulated?() do
      :ok
    else
      {:ok, _} = Application.ensure_all_started(:inets)
      {:ok, _} = Application.ensure_all_started(:ssl)
      {:ok, _} = Application.ensure_all_started(:exla)
      {:ok, _} = Application.ensure_all_started(:bumblebee)
      :ok
    end
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

  defp print_dominance(report, batch_id) do
    Mix.shell().info("\n== Dominance: iterative vs. negative controls ==")

    significance = EvalRunner.significance(batch_id)

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

      axes = Map.get(significance, control, %{})
      Mix.shell().info("    grade diff:        #{fmt_sig(axes[:grade_compliance])}")
      Mix.shell().info("    faithfulness diff: #{fmt_sig(axes[:faithfulness])}")
    end)
  end

  defp fmt_pct(nil), do: "n/a"
  defp fmt_pct(value), do: "#{Float.round(value * 100, 1)}%"

  defp fmt(nil), do: "n/a"
  defp fmt(value), do: Float.round(value, 3)

  # The line that keeps dominance honest: the paired iterative-minus-control
  # difference, its 95% CI, and whether that CI clears zero. "not sig" means
  # the point-estimate edge is inside noise.
  defp fmt_sig(nil), do: "n/a (no paired data)"

  defp fmt_sig(%{diff: diff, ci_95: {lower, upper}, significant: significant}) do
    verdict = if significant, do: "significant", else: "not sig (CI spans 0)"

    "#{Float.round(diff, 3)} (95% CI #{Float.round(lower, 3)} to #{Float.round(upper, 3)}) -- #{verdict}"
  end
end
