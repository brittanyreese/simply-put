defmodule SimplyPut.EvalRunnerTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.SQL.Sandbox
  alias SimplyPut.CorpusItem
  alias SimplyPut.EvalRunner
  alias SimplyPut.Repo
  alias SimplyPut.RewriteEvaluation

  setup do
    :ok = Sandbox.checkout(Repo)
  end

  defp insert_test_item!(attrs \\ %{}) do
    default = %{
      title: "Fixture",
      source: :med_easi,
      split: :test,
      source_text: "The multifaceted organization facilitated understanding.",
      reference_text: "The group helped people understand.",
      source_grade: 10.0
    }

    %CorpusItem{} |> CorpusItem.changeset(Map.merge(default, attrs)) |> Repo.insert!()
  end

  describe "run/1" do
    test "writes one rewrite_evaluations row per item per run_mode (default: all three)" do
      insert_test_item!()
      insert_test_item!(%{title: "Second"})

      batch_id = EvalRunner.run()

      rows = Repo.all(RewriteEvaluation)
      assert length(rows) == 6
      assert Enum.all?(rows, &(&1.batch_id == batch_id))

      run_modes = rows |> Enum.map(& &1.run_mode) |> Enum.uniq() |> Enum.sort()
      assert run_modes == [:iterative, :self_refine, :single_shot]
    end

    test "only runs the requested run_mode when given" do
      insert_test_item!()

      batch_id = EvalRunner.run(run_modes: [:single_shot])

      rows = Repo.all(RewriteEvaluation)
      assert length(rows) == 1
      assert hd(rows).run_mode == :single_shot
      assert hd(rows).batch_id == batch_id
    end

    test "ignores non-test-split and non-med_easi items" do
      insert_test_item!(%{split: :train})
      insert_test_item!(%{source: :clear_corpus, split: :test})

      EvalRunner.run(run_modes: [:single_shot])

      assert Repo.aggregate(RewriteEvaluation, :count) == 0
    end
  end

  describe "report/1" do
    test "aggregates mean, CI, and grade-band compliance per run_mode" do
      insert_test_item!()
      insert_test_item!(%{title: "Second"})

      batch_id = EvalRunner.run()
      report = EvalRunner.report(batch_id)

      assert report |> Map.keys() |> Enum.sort() == [:iterative, :self_refine, :single_shot]

      Enum.each(report, fn {_run_mode, summary} ->
        assert summary.items == 2
        assert %{mean: _mean, ci_95: {_lower, _upper}} = summary.fk_after
        assert is_float(summary.grade_band_compliance_rate)
      end)
    end
  end

  describe "success_gates/2" do
    test "returns 4 named gates with pass/fail and a detail string" do
      insert_test_item!()
      batch_id = EvalRunner.run()
      report = EvalRunner.report(batch_id)

      gates = EvalRunner.success_gates(report, %{simplicity: 0.5, fidelity: 0.5, fluency: 0.5})

      assert length(gates) == 4

      gate_names = gates |> Enum.map(& &1.gate) |> Enum.sort()

      assert gate_names == [
               :bounded_omission,
               :grade_band_compliance,
               :iterative_beats_controls,
               :moderate_judge_human_kappa
             ]

      assert Enum.all?(gates, &is_binary(&1.detail))
      assert Enum.all?(gates, &is_boolean(&1.passed))
    end

    test "moderate_kappa gate fails when any axis is below the 0.41 threshold" do
      gates = EvalRunner.success_gates(%{}, %{simplicity: 0.2, fidelity: 0.5, fluency: 0.5})
      gate = Enum.find(gates, &(&1.gate == :moderate_judge_human_kappa))
      refute gate.passed
    end

    test "moderate_kappa gate passes when every axis clears the threshold" do
      gates = EvalRunner.success_gates(%{}, %{simplicity: 0.5, fidelity: 0.5, fluency: 0.5})
      gate = Enum.find(gates, &(&1.gate == :moderate_judge_human_kappa))
      assert gate.passed
    end

    test "grade_band gate passes when iterative compliance rate is at least 50%" do
      report = %{iterative: %{grade_band_compliance_rate: 0.5}}
      gates = EvalRunner.success_gates(report, %{})
      gate = Enum.find(gates, &(&1.gate == :grade_band_compliance))
      assert gate.passed
    end

    test "grade_band gate fails when iterative compliance rate is below 50%" do
      report = %{iterative: %{grade_band_compliance_rate: 0.49}}
      gates = EvalRunner.success_gates(report, %{})
      gate = Enum.find(gates, &(&1.gate == :grade_band_compliance))
      refute gate.passed
    end

    test "grade_band gate fails (not raises) when the iterative run_mode is missing" do
      gates = EvalRunner.success_gates(%{}, %{})
      gate = Enum.find(gates, &(&1.gate == :grade_band_compliance))
      refute gate.passed
    end

    test "iterative_beats_controls gate passes when iterative's CI lower bound clears both control means" do
      report = %{
        iterative: %{faithfulness_score: %{mean: 0.85, ci_95: {0.8, 0.9}}},
        single_shot: %{faithfulness_score: %{mean: 0.7}},
        self_refine: %{faithfulness_score: %{mean: 0.75}}
      }

      gates = EvalRunner.success_gates(report, %{})
      gate = Enum.find(gates, &(&1.gate == :iterative_beats_controls))
      assert gate.passed
    end

    test "iterative_beats_controls gate fails when iterative's CI lower bound sits below a control mean" do
      # Mean (0.8) beats the control (0.7), but the wide CI lower bound (0.6)
      # does not: a within-noise difference is not a win.
      report = %{
        iterative: %{faithfulness_score: %{mean: 0.8, ci_95: {0.6, 0.95}}},
        single_shot: %{faithfulness_score: %{mean: 0.7}},
        self_refine: %{faithfulness_score: %{mean: 0.5}}
      }

      gates = EvalRunner.success_gates(report, %{})
      gate = Enum.find(gates, &(&1.gate == :iterative_beats_controls))
      refute gate.passed
    end

    test "iterative_beats_controls gate fails (fail-closed) when a control is missing" do
      report = %{iterative: %{faithfulness_score: %{mean: 0.9, ci_95: {0.85, 0.95}}}}

      gates = EvalRunner.success_gates(report, %{})
      gate = Enum.find(gates, &(&1.gate == :iterative_beats_controls))
      refute gate.passed
    end

    test "bounded_omission gate passes when iterative's CI lower bound is at least 0.7" do
      report = %{iterative: %{omission_score: %{mean: 0.8, ci_95: {0.72, 0.9}}}}
      gates = EvalRunner.success_gates(report, %{})
      gate = Enum.find(gates, &(&1.gate == :bounded_omission))
      assert gate.passed
    end

    test "bounded_omission gate fails when iterative's CI lower bound is below 0.7" do
      # Mean (0.85) clears the threshold; the CI lower bound (0.68) does not.
      report = %{iterative: %{omission_score: %{mean: 0.85, ci_95: {0.68, 0.95}}}}
      gates = EvalRunner.success_gates(report, %{})
      gate = Enum.find(gates, &(&1.gate == :bounded_omission))
      refute gate.passed
    end
  end
end
