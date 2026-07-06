defmodule SimplyPut.JudgeScoreTest do
  use ExUnit.Case, async: true

  alias SimplyPut.JudgeScore

  test "parses a valid judge response" do
    attrs = %{"simplicity" => 4, "fidelity" => 5, "fluency" => 3, "notes" => "fine"}

    assert {:ok, %JudgeScore{simplicity: 4, fidelity: 5, fluency: 3, notes: "fine"}} =
             JudgeScore.parse(attrs)
  end

  test "notes is optional" do
    attrs = %{"simplicity" => 4, "fidelity" => 5, "fluency" => 3}

    assert {:ok, %JudgeScore{notes: nil}} = JudgeScore.parse(attrs)
  end

  test "rejects a missing axis" do
    attrs = %{"simplicity" => 4, "fidelity" => 5}

    assert {:error, %Ecto.Changeset{}} = JudgeScore.parse(attrs)
  end

  test "rejects an out-of-range score" do
    attrs = %{"simplicity" => 7, "fidelity" => 5, "fluency" => 3}

    assert {:error, changeset} = JudgeScore.parse(attrs)
    assert changeset.errors[:simplicity]
  end

  test "rejects a wrong-type score" do
    attrs = %{"simplicity" => "high", "fidelity" => 5, "fluency" => 3}

    assert {:error, %Ecto.Changeset{}} = JudgeScore.parse(attrs)
  end
end
