defmodule SimplyPut.MetricProvider.BertScoreTest do
  use ExUnit.Case, async: true

  alias SimplyPut.MetricProvider.BertScore

  test "identical embeddings score 1.0 on every axis" do
    embedding = Nx.tensor([1.0, 2.0, 3.0])

    assert %{precision: p, recall: r, f1: f} = BertScore.score(embedding, embedding)
    assert_in_delta p, 1.0, 0.0001
    assert_in_delta r, 1.0, 0.0001
    assert_in_delta f, 1.0, 0.0001
  end

  test "orthogonal embeddings score 0.0" do
    a = Nx.tensor([1.0, 0.0])
    b = Nx.tensor([0.0, 1.0])

    assert %{precision: p, recall: r, f1: f} = BertScore.score(a, b)
    assert_in_delta p, 0.0, 0.0001
    assert_in_delta r, 0.0, 0.0001
    assert_in_delta f, 0.0, 0.0001
  end

  test "opposite embeddings score -1.0 (cosine similarity, not clamped)" do
    a = Nx.tensor([1.0, 0.0])
    b = Nx.tensor([-1.0, 0.0])

    assert %{precision: p} = BertScore.score(a, b)
    assert_in_delta p, -1.0, 0.0001
  end

  test "precision, recall, and f1 are always equal at sentence granularity" do
    a = Nx.tensor([1.0, 2.0, 0.5])
    b = Nx.tensor([0.5, 1.0, 2.0])

    assert %{precision: p, recall: r, f1: f} = BertScore.score(a, b)
    assert p == r
    assert r == f
  end

  test "a zero vector scores 0.0 rather than dividing by zero" do
    zero = Nx.tensor([0.0, 0.0])
    other = Nx.tensor([1.0, 1.0])

    assert %{precision: p} = BertScore.score(zero, other)
    assert_in_delta p, 0.0, 0.0001
  end
end
