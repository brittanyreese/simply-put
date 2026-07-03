defmodule SimplyPut.Repo.Migrations.CreateRunResults do
  use Ecto.Migration

  def change do
    create table(:run_results) do
      add(:corpus_item_id, references(:corpus_items, on_delete: :delete_all), null: false)
      add(:status, :string, null: false)
      add(:fk_before, :float, null: false)
      add(:fk_after, :float, null: false)
      add(:target, :float, null: false)
      add(:attempts, :integer, null: false)
      add(:text_out, :text, null: false)
      add(:verdict, :map)

      timestamps()
    end

    create(index(:run_results, [:corpus_item_id]))
  end
end
