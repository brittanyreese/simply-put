defmodule SimplyPut.Repo.Migrations.AddOmissionScoreToRewriteEvaluations do
  use Ecto.Migration

  def change do
    alter table(:rewrite_evaluations) do
      # Reverse-direction NLI entailment (candidate -> source): a distinct axis
      # from faithfulness_score (source -> candidate). Catches dropped source
      # content (omission), which the addition-direction score cannot see.
      add(:omission_score, :decimal)
    end
  end
end
