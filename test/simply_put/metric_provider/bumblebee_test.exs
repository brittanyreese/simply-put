defmodule SimplyPut.MetricProvider.BumblebeeTest do
  @moduledoc """
  Exercises real Bumblebee checkpoints. Excluded by default (see
  `test/test_helper.exs`) -- run with `mix test --include bumblebee_models`
  once network access to Hugging Face Hub is available. The `sle/1` test
  has been run live (2026-07-21): `liamcripwell/sle-base` loads with the
  `roberta-base` tokenizer and returns a numeric score, confirming the
  tokenizer-source fix. The other checkpoints in this file are not yet
  verified in a network-capable run.
  """

  use ExUnit.Case, async: false

  @moduletag :bumblebee_models

  alias SimplyPut.MetricProvider.Bumblebee, as: MetricBumblebee

  test "entail/2 detects entailment for a clear paraphrase" do
    assert {:ok, %{label: :entailment, score: score}} =
             MetricBumblebee.entail("The cat sat on the mat.", "A cat was sitting on a mat.")

    assert score > 0.5
  end

  test "entail/2 detects contradiction" do
    assert {:ok, %{label: :contradiction}} =
             MetricBumblebee.entail(
               "The patient should take the medicine.",
               "The patient should not take the medicine."
             )
  end

  test "bertscore/2 scores identical sentences near 1.0" do
    assert {:ok, %{f1: f1}} =
             MetricBumblebee.bertscore("The cat sat on the mat.", "The cat sat on the mat.")

    assert f1 > 0.95
  end

  test "sle/1 returns a numeric score" do
    assert {:ok, score} = MetricBumblebee.sle("The cat sat on the mat.")
    assert is_number(score)
  end

  test "qafacteval/2 scores identical source and candidate highly" do
    text = "Take 500 milligrams of aspirin twice daily with food."

    assert {:ok, score} = MetricBumblebee.qafacteval(text, text)
    assert score > 0.5
  end
end
