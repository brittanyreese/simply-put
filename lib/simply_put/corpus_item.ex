defmodule SimplyPut.CorpusItem do
  @moduledoc "A Clear Corpus excerpt: source text, human-rated grade, license."

  use Ecto.Schema
  import Ecto.Changeset

  schema "corpus_items" do
    field(:title, :string)
    field(:author, :string)
    field(:source_text, :string)
    field(:source_grade, :float)
    field(:license, :string)
    field(:url, :string)

    timestamps()
  end

  @spec changeset(t :: Ecto.Schema.t(), attrs :: map()) :: Ecto.Changeset.t()
  def changeset(corpus_item, attrs) do
    corpus_item
    |> cast(attrs, [:title, :author, :source_text, :source_grade, :license, :url])
    |> validate_required([:title, :source_text, :source_grade])
  end
end
