defmodule SimplyPut.EvaluationTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.SQL.Sandbox
  alias SimplyPut.CorpusItem
  alias SimplyPut.Evaluation
  alias SimplyPut.JudgeScore
  alias SimplyPut.Plainish.Result
  alias SimplyPut.Repo
  alias SimplyPut.RewriteEvaluation

  setup do
    :ok = Sandbox.checkout(Repo)
  end

  defp insert_corpus_item!(attrs \\ %{}) do
    default = %{
      title: "Fixture",
      source_text: "The multifaceted organization facilitated understanding.",
      source_grade: 10.0
    }

    %CorpusItem{}
    |> CorpusItem.changeset(Map.merge(default, attrs))
    |> Repo.insert!()
  end

  defp fake_result(overrides \\ %{}) do
    default = %Result{
      status: :passed,
      fk_before: 10.5,
      fk_after: 5.25,
      target: 6.0,
      attempts: 2,
      text_out: "The big group helped people understand.",
      run_mode: :iterative,
      gate_passed: true,
      judge_score: %JudgeScore{simplicity: 4, fidelity: 5, fluency: 4}
    }

    struct(default, overrides)
  end

  test "records a row with every axis populated (item with a reference_text)" do
    item =
      insert_corpus_item!(%{
        source: :med_easi,
        reference_text: "The big group helped people understand."
      })

    assert {:ok, evaluation} = Evaluation.record(item, fake_result(), "batch-1")

    assert evaluation.corpus_item_id == item.id
    assert evaluation.batch_id == "batch-1"
    assert evaluation.run_mode == :iterative
    assert evaluation.fk_before_bp == 1050
    assert evaluation.fk_after_bp == 525
    assert evaluation.target_bp == 600
    assert is_integer(evaluation.smog_bp)
    assert evaluation.structural_gate_passed == true
    assert evaluation.attempts == 2
    assert evaluation.text_out == "The big group helped people understand."
    assert evaluation.simplicity == 4
    assert evaluation.fidelity == 5
    assert evaluation.fluency == 4
    assert is_integer(evaluation.sari_bp)
    assert is_integer(evaluation.bertscore_f1_bp)
    assert is_integer(evaluation.sle_bp)
    assert evaluation.faithfulness_score != nil
    assert evaluation.faithfulness_provider == "summac+qafacteval"
    assert evaluation.generator_model == "stub"
    assert evaluation.judge_model == "stub"
  end

  test "omits sari and bertscore when the item has no reference_text" do
    item = insert_corpus_item!()

    assert {:ok, evaluation} = Evaluation.record(item, fake_result(), "batch-1")

    assert evaluation.sari_bp == nil
    assert evaluation.bertscore_f1_bp == nil
    assert evaluation.sle_bp != nil
    assert evaluation.faithfulness_score != nil
  end

  test "basis-point round-trip: dividing by 100 recovers the original grade" do
    item = insert_corpus_item!()
    result = fake_result(%{fk_before: 12.34, fk_after: 7.89, target: 6.0})

    assert {:ok, evaluation} = Evaluation.record(item, result, "batch-1")

    assert evaluation.fk_before_bp == 1234
    assert evaluation.fk_after_bp == 789
    assert_in_delta evaluation.fk_before_bp / 100, 12.34, 0.001
    assert_in_delta evaluation.fk_after_bp / 100, 7.89, 0.001
  end

  test "append-only: two runs of the same item produce two rows, not an upsert" do
    item = insert_corpus_item!()

    assert {:ok, _} = Evaluation.record(item, fake_result(), "batch-1")
    assert {:ok, _} = Evaluation.record(item, fake_result(), "batch-2")

    assert Repo.aggregate(RewriteEvaluation, :count) == 2
  end

  test "omits judge axes when judge_score is nil (e.g. self_refine run_mode)" do
    item = insert_corpus_item!()
    result = fake_result(%{run_mode: :self_refine, judge_score: nil})

    assert {:ok, evaluation} = Evaluation.record(item, result, "batch-1")

    assert evaluation.simplicity == nil
    assert evaluation.fidelity == nil
    assert evaluation.fluency == nil
    assert evaluation.run_mode == :self_refine
  end
end
