defmodule SimplyPut.Repo.Migrations.CreateRewriteEvaluations do
  use Ecto.Migration

  def change do
    create table(:rewrite_evaluations) do
      add(:corpus_item_id, references(:corpus_items), null: false)
      add(:batch_id, :string, null: false)
      add(:run_mode, :string, null: false)

      add(:fk_before_bp, :integer, null: false)
      add(:fk_after_bp, :integer, null: false)
      add(:smog_bp, :integer, null: false)
      add(:target_bp, :integer, null: false)
      add(:sari_bp, :integer)
      add(:bertscore_f1_bp, :integer)
      add(:sle_bp, :integer)

      add(:simplicity, :integer)
      add(:fidelity, :integer)
      add(:fluency, :integer)

      add(:faithfulness_score, :decimal)
      add(:structural_gate_passed, :boolean, null: false)
      add(:attempts, :integer, null: false)
      add(:text_out, :text, null: false)

      add(:generator_model, :string)
      add(:judge_model, :string)
      add(:faithfulness_provider, :string)

      timestamps()
    end

    create(index(:rewrite_evaluations, [:batch_id, :run_mode]))
  end
end
