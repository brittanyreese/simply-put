defmodule SimplyPut.Corpus.ImportTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.SQL.Sandbox
  alias SimplyPut.Corpus.Import
  alias SimplyPut.CorpusItem
  alias SimplyPut.Repo

  @fixture Path.join([__DIR__, "..", "..", "fixtures", "med_easi_sample.csv"])

  setup do
    :ok = Sandbox.checkout(Repo)
  end

  test "imports every row and preserves reference_text" do
    assert {:ok, 5} = Import.import_med_easi(@fixture)

    items = Repo.all(CorpusItem)
    assert length(items) == 5
    assert Enum.all?(items, &(&1.source == :med_easi))
    assert Enum.all?(items, &(&1.reference_text != nil and &1.reference_text != ""))
    assert Enum.all?(items, &(&1.split in [:train, :dev, :test]))
  end

  test "maps by header name, ignoring extra annotation columns" do
    {:ok, 5} = Import.import_med_easi(@fixture)

    item = Repo.get_by!(CorpusItem, title: "med_easi-med-1")
    assert item.source_text =~ "contraindications"
    assert item.reference_text =~ "blood-thinning"
  end

  test "split: option assigns every row that split, overriding the hash" do
    assert {:ok, 5} = Import.import_med_easi(@fixture, split: :test)

    items = Repo.all(CorpusItem)
    assert length(items) == 5
    assert Enum.all?(items, &(&1.split == :test))
  end

  test "rejects a file missing a required column" do
    path = Path.join(System.tmp_dir!(), "med_easi_bad_#{System.unique_integer([:positive])}.csv")
    File.write!(path, "Expert,idx\n\"only source\",med-1\n")
    on_exit(fn -> File.rm(path) end)

    assert {:error, {:missing_column, "Simple"}} = Import.import_med_easi(path)
    assert Repo.aggregate(CorpusItem, :count) == 0
  end

  test "split assignment for a given id is deterministic" do
    assert Import.split_for("med-1") == Import.split_for("med-1")
    assert Import.split_for("stable-id-42") == Import.split_for("stable-id-42")
  end

  test "split_for/1 distributes across train/dev/test" do
    splits =
      1..200
      |> Enum.map(&Import.split_for("id-#{&1}"))
      |> Enum.uniq()
      |> Enum.sort()

    assert splits == [:dev, :test, :train]
  end
end
