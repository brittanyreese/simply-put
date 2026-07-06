defmodule SimplyPut.MetricProviderTest do
  use ExUnit.Case, async: true

  alias SimplyPut.MetricProvider

  test "entail/2 returns a label and score via the default (stub) adapter" do
    assert {:ok, %{label: label, score: score}} = MetricProvider.entail("premise", "hypothesis")
    assert label in [:entailment, :neutral, :contradiction]
    assert is_float(score)
  end

  test "bertscore/2 returns precision/recall/f1 via the default (stub) adapter" do
    assert {:ok, %{precision: p, recall: r, f1: f}} =
             MetricProvider.bertscore("candidate", "reference")

    assert is_float(p)
    assert is_float(r)
    assert is_float(f)
  end

  test "sle/1 returns a float via the default (stub) adapter" do
    assert {:ok, score} = MetricProvider.sle("candidate")
    assert is_float(score)
  end

  test "qafacteval/2 returns a float via the default (stub) adapter" do
    assert {:ok, score} = MetricProvider.qafacteval("source", "candidate")
    assert is_float(score)
  end

  test "simulated?/0 is true when the default (stub) adapter is active" do
    assert MetricProvider.simulated?()
  end
end
