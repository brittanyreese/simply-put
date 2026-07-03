defmodule SimplyPut.RunResultTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.SQL.Sandbox
  alias SimplyPut.CorpusItem
  alias SimplyPut.Repo
  alias SimplyPut.RunResult

  setup do
    :ok = Sandbox.checkout(Repo)
  end

  test "belongs to a corpus item and stores a passed/held status" do
    {:ok, item} =
      %CorpusItem{}
      |> CorpusItem.changeset(%{title: "T", source_text: "Text.", source_grade: 5.0})
      |> Repo.insert()

    attrs = %{
      status: :passed,
      fk_before: 10.0,
      fk_after: 5.0,
      target: 6.0,
      attempts: 1,
      text_out: "Text.",
      corpus_item_id: item.id
    }

    assert {:ok, %RunResult{status: :passed} = run_result} =
             %RunResult{} |> RunResult.changeset(attrs) |> Repo.insert()

    assert Repo.get!(RunResult, run_result.id).corpus_item_id == item.id
  end

  test "changeset rejects an invalid status value" do
    changeset = RunResult.changeset(%RunResult{}, %{status: :bogus})
    refute changeset.valid?
  end

  test "changeset requires fk scores, attempts, text_out, and a corpus item" do
    changeset = RunResult.changeset(%RunResult{}, %{})
    refute changeset.valid?

    for field <- [:status, :fk_before, :fk_after, :target, :attempts, :text_out, :corpus_item_id] do
      assert {"can't be blank", _} = changeset.errors[field]
    end
  end
end
