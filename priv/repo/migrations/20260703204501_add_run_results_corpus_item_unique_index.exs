defmodule SimplyPut.Repo.Migrations.AddRunResultsCorpusItemUniqueIndex do
  use Ecto.Migration

  def change do
    drop(index(:run_results, [:corpus_item_id]))
    create(unique_index(:run_results, [:corpus_item_id]))
  end
end
