defmodule SimplyPut.LLM.StubTest do
  use ExUnit.Case, async: true

  alias SimplyPut.LLM.Stub

  test "score/2 returns a validated multi-axis JudgeScore" do
    assert {:ok, %SimplyPut.JudgeScore{simplicity: s, fidelity: f, fluency: fl}} =
             Stub.score("original", "rewrite")

    assert s in 1..5
    assert f in 1..5
    assert fl in 1..5
  end
end
