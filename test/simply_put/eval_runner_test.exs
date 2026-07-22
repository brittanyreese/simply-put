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

    test "limit caps how many test items run" do
      insert_test_item!()
      insert_test_item!(%{title: "Second"})
      insert_test_item!(%{title: "Third"})

      EvalRunner.run(run_modes: [:single_shot], limit: 2)

      assert Repo.aggregate(RewriteEvaluation, :count) == 2
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
    test "returns 3 named gates with a status and a detail string" do
      insert_test_item!()
      batch_id = EvalRunner.run()
      report = EvalRunner.report(batch_id)

      kappa = %{simplicity: 0.5, fidelity: 0.5, fluency: 0.5, items: 10}
      gates = EvalRunner.success_gates(report, kappa)

      assert length(gates) == 3

      gate_names = gates |> Enum.map(& &1.gate) |> Enum.sort()

      assert gate_names == [
               :bounded_omission,
               :grade_band_compliance,
               :moderate_judge_human_kappa
             ]

      assert Enum.all?(gates, &is_binary(&1.detail))
      assert Enum.all?(gates, &(&1.status in [:pass, :fail, :not_evaluated]))
    end

    test "moderate_kappa gate fails when any axis is below the 0.41 threshold" do
      kappa = %{simplicity: 0.2, fidelity: 0.5, fluency: 0.5, items: 10}
      gates = EvalRunner.success_gates(%{}, kappa)
      gate = Enum.find(gates, &(&1.gate == :moderate_judge_human_kappa))
      assert gate.status == :fail
    end

    test "moderate_kappa gate passes when every axis clears the threshold" do
      kappa = %{simplicity: 0.5, fidelity: 0.5, fluency: 0.5, items: 10}
      gates = EvalRunner.success_gates(%{}, kappa)
      gate = Enum.find(gates, &(&1.gate == :moderate_judge_human_kappa))
      assert gate.status == :pass
    end

    test "moderate_kappa gate is not_evaluated when no human_labels are loaded" do
      kappa = %{simplicity: 0.0, fidelity: 0.0, fluency: 0.0, items: 0}
      gates = EvalRunner.success_gates(%{}, kappa)
      gate = Enum.find(gates, &(&1.gate == :moderate_judge_human_kappa))
      assert gate.status == :not_evaluated
      assert gate.detail =~ "no human_labels loaded"
    end

    test "grade_band gate passes when iterative compliance rate is at least 50%" do
      report = %{iterative: %{grade_band_compliance_rate: 0.5}}
      gates = EvalRunner.success_gates(report, %{})
      gate = Enum.find(gates, &(&1.gate == :grade_band_compliance))
      assert gate.status == :pass
    end

    test "grade_band gate fails when iterative compliance rate is below 50%" do
      report = %{iterative: %{grade_band_compliance_rate: 0.49}}
      gates = EvalRunner.success_gates(report, %{})
      gate = Enum.find(gates, &(&1.gate == :grade_band_compliance))
      assert gate.status == :fail
    end

    test "grade_band gate fails (not raises) when the iterative run_mode is missing" do
      gates = EvalRunner.success_gates(%{}, %{})
      gate = Enum.find(gates, &(&1.gate == :grade_band_compliance))
      assert gate.status == :fail
    end

    test "bounded_omission gate passes when iterative's CI lower bound is at least 0.7" do
      report = %{iterative: %{omission_score: %{mean: 0.8, ci_95: {0.72, 0.9}}}}
      gates = EvalRunner.success_gates(report, %{})
      gate = Enum.find(gates, &(&1.gate == :bounded_omission))
      assert gate.status == :pass
    end

    test "bounded_omission gate fails when iterative's CI lower bound is below 0.7" do
      # Mean (0.85) clears the threshold; the CI lower bound (0.68) does not.
      report = %{iterative: %{omission_score: %{mean: 0.85, ci_95: {0.68, 0.95}}}}
      gates = EvalRunner.success_gates(report, %{})
      gate = Enum.find(gates, &(&1.gate == :bounded_omission))
      assert gate.status == :fail
    end
  end

  defp insert_eval!(item, batch_id, run_mode, fk_after_bp, faithfulness) do
    %RewriteEvaluation{}
    |> RewriteEvaluation.changeset(%{
      corpus_item_id: item.id,
      batch_id: batch_id,
      run_mode: run_mode,
      fk_before_bp: 1200,
      fk_after_bp: fk_after_bp,
      smog_bp: 1000,
      target_bp: 800,
      structural_gate_passed: true,
      attempts: 1,
      text_out: "out",
      faithfulness_score: Decimal.from_float(faithfulness)
    })
    |> Repo.insert!()
  end

  describe "significance/1" do
    test "flags a difference as significant when every paired item moves the same way" do
      batch_id = "sig-batch"
      # Two items, iterative always compliant + more faithful, control never.
      for item <- [insert_test_item!(), insert_test_item!(%{title: "Second"})] do
        insert_eval!(item, batch_id, :iterative, 700, 0.9)
        insert_eval!(item, batch_id, :single_shot, 1000, 0.7)
      end

      %{single_shot: %{grade_compliance: grade, faithfulness: faith}} =
        EvalRunner.significance(batch_id)

      assert grade.diff == 1.0
      assert grade.significant
      assert faith.significant
      assert_in_delta faith.diff, 0.2, 0.0001
    end

    test "not significant when the paired difference is zero on every item" do
      batch_id = "null-batch"

      for item <- [insert_test_item!(), insert_test_item!(%{title: "Second"})] do
        insert_eval!(item, batch_id, :iterative, 800, 0.8)
        insert_eval!(item, batch_id, :self_refine, 800, 0.8)
      end

      %{self_refine: %{grade_compliance: grade, faithfulness: faith}} =
        EvalRunner.significance(batch_id)

      refute grade.significant
      refute faith.significant
    end

    test "nil axis when a control did not run" do
      batch_id = "solo-batch"
      item = insert_test_item!()
      insert_eval!(item, batch_id, :iterative, 700, 0.9)

      assert %{single_shot: %{grade_compliance: nil, faithfulness: nil}} =
               EvalRunner.significance(batch_id)
    end
  end

  describe "dominance/1" do
    test "iterative_dominates when it wins or ties both axes" do
      report = %{
        iterative: %{grade_band_compliance_rate: 0.7, faithfulness_score: %{mean: 0.85}},
        single_shot: %{grade_band_compliance_rate: 0.3, faithfulness_score: %{mean: 0.80}}
      }

      assert %{single_shot: %{relation: :iterative_dominates}} = EvalRunner.dominance(report)
    end

    test "tradeoff when each side wins one axis" do
      report = %{
        iterative: %{grade_band_compliance_rate: 0.7, faithfulness_score: %{mean: 0.80}},
        self_refine: %{grade_band_compliance_rate: 0.8, faithfulness_score: %{mean: 0.75}}
      }

      assert %{self_refine: %{relation: :tradeoff}} = EvalRunner.dominance(report)
    end

    test "iterative_dominated when a control wins or ties both axes" do
      report = %{
        iterative: %{grade_band_compliance_rate: 0.3, faithfulness_score: %{mean: 0.70}},
        single_shot: %{grade_band_compliance_rate: 0.5, faithfulness_score: %{mean: 0.80}}
      }

      assert %{single_shot: %{relation: :iterative_dominated}} = EvalRunner.dominance(report)
    end

    test "tie when both axes are equal" do
      report = %{
        iterative: %{grade_band_compliance_rate: 0.5, faithfulness_score: %{mean: 0.80}},
        single_shot: %{grade_band_compliance_rate: 0.5, faithfulness_score: %{mean: 0.80}}
      }

      assert %{single_shot: %{relation: :tie}} = EvalRunner.dominance(report)
    end

    test "incomparable when a control did not run" do
      report = %{iterative: %{grade_band_compliance_rate: 0.7, faithfulness_score: %{mean: 0.85}}}

      assert %{single_shot: %{relation: :incomparable}, self_refine: %{relation: :incomparable}} =
               EvalRunner.dominance(report)
    end
  end
end
