defmodule SimplyPut.Repo.Migrations.CreateCorpusItems do
  use Ecto.Migration

  def change do
    create table(:corpus_items) do
      add(:title, :string, null: false)
      add(:author, :string)
      add(:source_text, :text, null: false)
      add(:source_grade, :float, null: false)
      add(:license, :string)
      add(:url, :string)

      timestamps()
    end
  end
end
