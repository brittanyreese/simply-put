defmodule SimplyPut.RunResult do
  @moduledoc "One `Plainish.run/2` outcome against a corpus item. Append-only."

  use Ecto.Schema
  import Ecto.Changeset

  schema "run_results" do
    field(:status, Ecto.Enum, values: [:passed, :held])
    field(:fk_before, :float)
    field(:fk_after, :float)
    field(:target, :float)
    field(:attempts, :integer)
    field(:text_out, :string)
    field(:verdict, :map)

    belongs_to(:corpus_item, SimplyPut.CorpusItem)

    timestamps()
  end

  @spec changeset(t :: Ecto.Schema.t(), attrs :: map()) :: Ecto.Changeset.t()
  def changeset(run_result, attrs) do
    run_result
    |> cast(attrs, [
      :status,
      :fk_before,
      :fk_after,
      :target,
      :attempts,
      :text_out,
      :verdict,
      :corpus_item_id
    ])
    |> validate_required([
      :status,
      :fk_before,
      :fk_after,
      :target,
      :attempts,
      :text_out,
      :corpus_item_id
    ])
  end
end
