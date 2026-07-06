defmodule SimplyPut.JudgeScore do
  @moduledoc """
  Embedded (no-table) schema that validates and shapes an LLM judge's raw
  JSON response into three separate axes. Malformed judge output (missing
  field, out-of-range score, wrong type) surfaces as `{:error, %Ecto.Changeset{}}`
  for callers to match explicitly (Iron Law #4) rather than crashing.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field(:simplicity, :integer)
    field(:fidelity, :integer)
    field(:fluency, :integer)
    field(:notes, :string)
  end

  @type t :: %__MODULE__{
          simplicity: 1..5,
          fidelity: 1..5,
          fluency: 1..5,
          notes: String.t() | nil
        }

  @doc "Parses a raw judge response map into a validated `t:t/0`."
  @spec parse(map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def parse(attrs) when is_map(attrs) do
    changeset =
      %__MODULE__{}
      |> cast(attrs, [:simplicity, :fidelity, :fluency, :notes])
      |> validate_required([:simplicity, :fidelity, :fluency])
      |> validate_inclusion(:simplicity, 1..5)
      |> validate_inclusion(:fidelity, 1..5)
      |> validate_inclusion(:fluency, 1..5)

    if changeset.valid? do
      {:ok, apply_changes(changeset)}
    else
      {:error, changeset}
    end
  end
end
