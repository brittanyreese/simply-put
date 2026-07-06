defmodule SimplyPut.Repo.Migrations.AddSourceSplitReferenceToCorpusItems do
  use Ecto.Migration

  def change do
    alter table(:corpus_items) do
      add(:source, :string, null: false, default: "clear_corpus")
      add(:split, :string)
      add(:reference_text, :text)
    end
  end
end
