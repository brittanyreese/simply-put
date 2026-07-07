defmodule SimplyPut.RewriteEvaluation do
  @moduledoc """
  One `Plainish.run/2` outcome against a corpus item, with every evaluation
  axis. Append-only per batch (NOT upsert-per-item, unlike `RunResult`):
  re-running the same item under the same or a different `run_mode`
  produces a new row, so the harness can compare run-modes and track
  history rather than only ever seeing the latest run.

  Grades are stored as integer basis points (`grade * 100`), never floats
  (Iron Law: no `:float` on new schemas). `sari_bp` and `bertscore_f1_bp`
  are `nil` when the corpus item has no `reference_text` (only Med-EASi
  ships one; Clear Corpus items leave these two columns nil).
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "rewrite_evaluations" do
    belongs_to(:corpus_item, SimplyPut.CorpusItem)

    field(:batch_id, :string)
    field(:run_mode, Ecto.Enum, values: [:iterative, :single_shot, :self_refine])

    field(:fk_before_bp, :integer)
    field(:fk_after_bp, :integer)
    field(:smog_bp, :integer)
    field(:target_bp, :integer)
    field(:sari_bp, :integer)
    field(:bertscore_f1_bp, :integer)
    field(:sle_bp, :integer)

    field(:simplicity, :integer)
    field(:fidelity, :integer)
    field(:fluency, :integer)

    field(:faithfulness_score, :decimal)
    field(:omission_score, :decimal)
    field(:structural_gate_passed, :boolean)
    field(:attempts, :integer)
    field(:text_out, :string)

    field(:generator_model, :string)
    field(:judge_model, :string)
    field(:faithfulness_provider, :string)

    timestamps()
  end

  @required [
    :corpus_item_id,
    :batch_id,
    :run_mode,
    :fk_before_bp,
    :fk_after_bp,
    :smog_bp,
    :target_bp,
    :structural_gate_passed,
    :attempts,
    :text_out
  ]

  @optional [
    :sari_bp,
    :bertscore_f1_bp,
    :sle_bp,
    :simplicity,
    :fidelity,
    :fluency,
    :faithfulness_score,
    :omission_score,
    :generator_model,
    :judge_model,
    :faithfulness_provider
  ]

  @spec changeset(t :: Ecto.Schema.t(), attrs :: map()) :: Ecto.Changeset.t()
  def changeset(rewrite_evaluation, attrs) do
    rewrite_evaluation
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:simplicity, 1..5)
    |> validate_inclusion(:fidelity, 1..5)
    |> validate_inclusion(:fluency, 1..5)
  end
end
