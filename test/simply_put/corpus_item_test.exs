defmodule SimplyPut.CorpusItemTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.SQL.Sandbox
  alias SimplyPut.CorpusItem
  alias SimplyPut.Repo

  setup do
    :ok = Sandbox.checkout(Repo)
  end

  test "changeset requires title, source_text, source_grade" do
    changeset = CorpusItem.changeset(%CorpusItem{}, %{})

    refute changeset.valid?
    assert {"can't be blank", _} = changeset.errors[:title]
    assert {"can't be blank", _} = changeset.errors[:source_text]
    assert {"can't be blank", _} = changeset.errors[:source_grade]
  end

  test "valid attrs insert successfully" do
    attrs = %{
      title: "A Story",
      author: "Someone",
      source_text: "Some plain text.",
      source_grade: 5.0,
      license: "Public Domain",
      url: "http://example.com"
    }

    assert {:ok, %CorpusItem{title: "A Story"}} =
             %CorpusItem{} |> CorpusItem.changeset(attrs) |> Repo.insert()
  end
end
