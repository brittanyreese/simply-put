defmodule SimplyPut.MetricProvider.QAOverlapTest do
  use ExUnit.Case, async: true

  alias SimplyPut.MetricProvider.QAOverlap

  test "identical answers score 1.0" do
    assert QAOverlap.f1("500 milligrams", "500 milligrams") == 1.0
  end

  test "completely disjoint answers score 0.0" do
    assert QAOverlap.f1("500 milligrams", "twice daily") == 0.0
  end

  test "partial overlap scores between 0 and 1" do
    score = QAOverlap.f1("500 milligrams twice daily", "500 milligrams")
    assert score > 0.0
    assert score < 1.0
  end

  test "case-insensitive comparison" do
    assert QAOverlap.f1("Aspirin", "aspirin") == 1.0
  end

  test "both empty answers score 1.0 (nothing to disagree on)" do
    assert QAOverlap.f1("", "") == 1.0
  end

  test "one empty answer scores 0.0" do
    assert QAOverlap.f1("500 milligrams", "") == 0.0
    assert QAOverlap.f1("", "500 milligrams") == 0.0
  end
end
