defmodule SimplyPut.Repo.Migrations.CreateHumanLabels do
  use Ecto.Migration

  def change do
    create table(:human_labels) do
      add(:rewrite_evaluation_id, references(:rewrite_evaluations))
      add(:external_item_id, :string)
      add(:source_dataset, :string, null: false)

      add(:original_text, :text)
      add(:candidate_text, :text)

      add(:simplicity, :integer, null: false)
      add(:fidelity, :integer, null: false)
      add(:fluency, :integer, null: false)
      add(:omission_of_safety_content, :boolean)
      add(:annotator, :string, null: false)

      timestamps()
    end

    create(index(:human_labels, [:external_item_id]))
  end
end
