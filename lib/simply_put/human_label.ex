defmodule SimplyPut.HumanLabel do
  @moduledoc """
  One human rating (simplicity/fidelity/fluency, 1..5) against either an
  imported external item (ASSET, PLABA TREC -- `external_item_id` set,
  `rewrite_evaluation_id` nil) or one of this project's own rewrite
  evaluations (`rewrite_evaluation_id` set, `external_item_id` nil).

  `original_text`/`candidate_text` are stored alongside imported external
  ratings so `SimplyPut.JudgeValidation` can re-score the same pair with
  the configured judge for judge-vs-human kappa -- the raw ASSET/PLABA
  releases carry these, so this is denormalization, not new data.

  Multiple rows may share the same `external_item_id` (a second human
  rater on a subset, `source_dataset: :self_labeled`, distinct
  `annotator`) -- this is how the human-vs-human kappa comparison works,
  no separate mechanism needed.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "human_labels" do
    belongs_to(:rewrite_evaluation, SimplyPut.RewriteEvaluation)
    field(:external_item_id, :string)
    field(:source_dataset, Ecto.Enum, values: [:asset, :plaba_trec, :self_labeled])

    field(:original_text, :string)
    field(:candidate_text, :string)

    field(:simplicity, :integer)
    field(:fidelity, :integer)
    field(:fluency, :integer)
    field(:omission_of_safety_content, :boolean)
    field(:annotator, :string)

    timestamps()
  end

  @required [:source_dataset, :simplicity, :fidelity, :fluency, :annotator]
  @optional [
    :rewrite_evaluation_id,
    :external_item_id,
    :original_text,
    :candidate_text,
    :omission_of_safety_content
  ]

  @spec changeset(t :: Ecto.Schema.t(), attrs :: map()) :: Ecto.Changeset.t()
  def changeset(human_label, attrs) do
    human_label
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:simplicity, 1..5)
    |> validate_inclusion(:fidelity, 1..5)
    |> validate_inclusion(:fluency, 1..5)
  end
end
