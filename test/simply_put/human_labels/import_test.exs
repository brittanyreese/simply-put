defmodule SimplyPut.HumanLabels.ImportTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.SQL.Sandbox
  alias SimplyPut.HumanLabel
  alias SimplyPut.HumanLabels.Import
  alias SimplyPut.Repo

  @fixture Path.join([__DIR__, "..", "..", "fixtures", "asset_sample.csv"])

  setup do
    :ok = Sandbox.checkout(Repo)
  end

  test "imports every row with the given source_dataset" do
    assert {:ok, 3} = Import.import(@fixture, :asset)

    labels = Repo.all(HumanLabel)
    assert length(labels) == 3
    assert Enum.all?(labels, &(&1.source_dataset == :asset))
    assert Enum.all?(labels, &(&1.original_text != nil and &1.original_text != ""))
    assert Enum.all?(labels, &(&1.candidate_text != nil and &1.candidate_text != ""))
    assert Enum.all?(labels, &(&1.simplicity in 1..5))
  end

  test "preserves the external_item_id and annotator" do
    {:ok, _count} = Import.import(@fixture, :plaba_trec)

    label = Repo.get_by!(HumanLabel, external_item_id: "asset-2")
    assert label.source_dataset == :plaba_trec
    assert label.annotator == "worker-1"
    assert label.simplicity == 5
    assert label.fidelity == 4
    assert label.fluency == 5
  end
end
