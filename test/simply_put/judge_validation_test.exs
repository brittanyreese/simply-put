defmodule SimplyPut.LLM.VariableScoreStub do
  @moduledoc false
  @behaviour SimplyPut.LLM

  @impl true
  def rewrite(text, _opts), do: {:ok, text}

  @impl true
  def judge(_original, _rewrite), do: {:ok, %{verdict: :preserved, rationale: ""}}

  @impl true
  def score(_original, candidate) do
    scores = %{
      "cand-1" => %{simplicity: 4, fidelity: 5, fluency: 4},
      "cand-2" => %{simplicity: 5, fidelity: 4, fluency: 5},
      "cand-3" => %{simplicity: 3, fidelity: 5, fluency: 3},
      "cand-4" => %{simplicity: 2, fidelity: 3, fluency: 2}
    }

    SimplyPut.JudgeScore.parse(Map.fetch!(scores, candidate))
  end
end

defmodule SimplyPut.LLM.OrderBiasedStub do
  @moduledoc false
  @behaviour SimplyPut.LLM

  @impl true
  def rewrite(text, _opts), do: {:ok, text}

  @impl true
  def judge(_original, _rewrite), do: {:ok, %{verdict: :preserved, rationale: ""}}

  # Order-biased: scores higher whenever the SECOND argument is the
  # longer string, regardless of content -- simulates a judge that's
  # sensitive to position rather than substance.
  @impl true
  def score(original, candidate) do
    if String.length(candidate) >= String.length(original) do
      SimplyPut.JudgeScore.parse(%{simplicity: 5, fidelity: 5, fluency: 5})
    else
      SimplyPut.JudgeScore.parse(%{simplicity: 2, fidelity: 2, fluency: 2})
    end
  end
end

defmodule SimplyPut.JudgeValidationTest do
  # async: false -- mutates global :llm adapter config (VM-wide).
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias SimplyPut.HumanLabel
  alias SimplyPut.JudgeValidation
  alias SimplyPut.Repo

  setup do
    :ok = Sandbox.checkout(Repo)
  end

  defp insert_label!(attrs) do
    default = %{source_dataset: :asset, annotator: "worker-1"}

    %HumanLabel{}
    |> HumanLabel.changeset(Map.merge(default, attrs))
    |> Repo.insert!()
  end

  describe "judge_vs_human_kappa/0" do
    test "compares the configured judge's score against the stored human rating" do
      Application.put_env(:simply_put, :llm, SimplyPut.LLM.VariableScoreStub)
      on_exit(fn -> Application.delete_env(:simply_put, :llm) end)

      insert_label!(%{
        external_item_id: "item-1",
        original_text: "original 1",
        candidate_text: "cand-1",
        simplicity: 4,
        fidelity: 5,
        fluency: 4
      })

      insert_label!(%{
        external_item_id: "item-2",
        original_text: "original 2",
        candidate_text: "cand-2",
        simplicity: 5,
        fidelity: 4,
        fluency: 5
      })

      insert_label!(%{
        external_item_id: "item-3",
        original_text: "original 3",
        candidate_text: "cand-3",
        # human simplicity disagrees with the judge's (4 vs judge's 3)
        simplicity: 4,
        fidelity: 5,
        fluency: 3
      })

      insert_label!(%{
        external_item_id: "item-4",
        original_text: "original 4",
        candidate_text: "cand-4",
        simplicity: 2,
        fidelity: 3,
        fluency: 2
      })

      report = JudgeValidation.judge_vs_human_kappa()

      assert report.items == 4
      # fidelity and fluency agree exactly on every item; simplicity has
      # one disagreement (item-3), so it should score lower but still
      # reasonably high given the other 3 exact matches.
      assert report.fidelity > 0.9
      assert report.fluency > 0.9
      assert report.simplicity < report.fidelity
    end

    test "returns 0 items when there are no primary-labeled rows" do
      assert %{items: 0} = JudgeValidation.judge_vs_human_kappa()
    end
  end

  describe "human_vs_human_kappa/0" do
    test "pairs primary and second-rater labels sharing an external_item_id" do
      insert_label!(%{
        external_item_id: "item-1",
        source_dataset: :asset,
        simplicity: 4,
        fidelity: 5,
        fluency: 4
      })

      insert_label!(%{
        external_item_id: "item-1",
        source_dataset: :self_labeled,
        annotator: "worker-2",
        simplicity: 4,
        fidelity: 5,
        fluency: 4
      })

      insert_label!(%{
        external_item_id: "item-2",
        source_dataset: :asset,
        simplicity: 2,
        fidelity: 3,
        fluency: 2
      })

      insert_label!(%{
        external_item_id: "item-2",
        source_dataset: :self_labeled,
        annotator: "worker-2",
        simplicity: 2,
        fidelity: 3,
        fluency: 2
      })

      report = JudgeValidation.human_vs_human_kappa()

      assert report.items == 2
      assert_in_delta report.simplicity, 1.0, 0.0001
      assert_in_delta report.fidelity, 1.0, 0.0001
      assert_in_delta report.fluency, 1.0, 0.0001
    end

    test "skips a second-rater row with no matching primary item" do
      insert_label!(%{
        external_item_id: "orphan",
        source_dataset: :self_labeled,
        simplicity: 3,
        fidelity: 3,
        fluency: 3
      })

      assert %{items: 0} = JudgeValidation.human_vs_human_kappa()
    end
  end

  describe "position_swap_test/1" do
    test "detects a 100% flip rate for an intentionally order-biased judge" do
      Application.put_env(:simply_put, :llm, SimplyPut.LLM.OrderBiasedStub)
      on_exit(fn -> Application.delete_env(:simply_put, :llm) end)

      pairs = [
        {"short", "a much longer candidate text than the original"},
        {"tiny", "another noticeably longer piece of candidate text"}
      ]

      assert %{flip_rate: 1.0, pairs_tested: 2} = JudgeValidation.position_swap_test(pairs)
    end

    test "reports a 0% flip rate for an order-invariant judge (default Stub)" do
      pairs = [
        {"short", "a much longer candidate text than the original"},
        {"tiny", "another noticeably longer piece of candidate text"}
      ]

      assert %{flip_rate: flip_rate, pairs_tested: 2} = JudgeValidation.position_swap_test(pairs)
      assert_in_delta flip_rate, 0.0, 0.0001
    end
  end

  describe "verbosity_bias_test/1" do
    test "reports a 0% bias rate for a judge that ignores length (default Stub)" do
      triples = [
        {"original text", "a candidate", "a candidate with lots of extra padding words added"}
      ]

      assert %{bias_rate: bias_rate, triples_tested: 1} =
               JudgeValidation.verbosity_bias_test(triples)

      assert_in_delta bias_rate, 0.0, 0.0001
    end
  end
end
