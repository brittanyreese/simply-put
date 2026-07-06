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

  test "defaults source to :clear_corpus when not given" do
    {:ok, item} =
      %CorpusItem{}
      |> CorpusItem.changeset(%{title: "A Story", source_text: "Text.", source_grade: 5.0})
      |> Repo.insert()

    assert item.source == :clear_corpus
  end

  test "accepts source, split, and reference_text for imported corpora" do
    attrs = %{
      title: "med_easi-1",
      source_text: "Complex text.",
      source_grade: 8.0,
      source: :med_easi,
      split: :test,
      reference_text: "Simple text."
    }

    assert {:ok, item} = %CorpusItem{} |> CorpusItem.changeset(attrs) |> Repo.insert()
    assert item.source == :med_easi
    assert item.split == :test
    assert item.reference_text == "Simple text."
  end

  test "refuses to reassign an item once it is in the frozen test split" do
    {:ok, item} =
      %CorpusItem{}
      |> CorpusItem.changeset(%{
        title: "med_easi-2",
        source_text: "Text.",
        source_grade: 5.0,
        source: :med_easi,
        split: :test
      })
      |> Repo.insert()

    changeset = CorpusItem.changeset(item, %{split: :train})

    refute changeset.valid?
    assert {"test split is frozen and cannot be reassigned", _} = changeset.errors[:split]
  end

  test "refuses to null out a test-split item's split (nil-then-reassign leak)" do
    {:ok, item} =
      %CorpusItem{}
      |> CorpusItem.changeset(%{
        title: "med_easi-nil",
        source_text: "Text.",
        source_grade: 5.0,
        source: :med_easi,
        split: :test
      })
      |> Repo.insert()

    changeset = CorpusItem.changeset(item, %{split: nil})

    refute changeset.valid?
    assert {"test split is frozen and cannot be reassigned", _} = changeset.errors[:split]
  end

  test "allows re-saving a test-split item without changing its split" do
    {:ok, item} =
      %CorpusItem{}
      |> CorpusItem.changeset(%{
        title: "med_easi-3",
        source_text: "Text.",
        source_grade: 5.0,
        source: :med_easi,
        split: :test
      })
      |> Repo.insert()

    changeset = CorpusItem.changeset(item, %{title: "med_easi-3-renamed"})

    assert changeset.valid?
  end
end
