defmodule SimplyPut.CorpusItem do
  @moduledoc """
  A corpus excerpt: source text, human-rated grade, license, and (for corpora
  that ship one) a gold plain-language `reference_text`.

  `source` distinguishes which corpus an item came from; `split` is the
  frozen train/dev/test assignment used by the eval harness (see
  `SimplyPut.Corpus.Import`). Only corpora used in the harness (Med-EASi)
  populate `split` and `reference_text`; Clear Corpus items leave both nil.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "corpus_items" do
    field(:title, :string)
    field(:author, :string)
    field(:source_text, :string)
    field(:source_grade, :float)
    field(:license, :string)
    field(:url, :string)
    field(:source, Ecto.Enum, values: [:clear_corpus, :med_easi], default: :clear_corpus)
    field(:split, Ecto.Enum, values: [:train, :dev, :test])
    field(:reference_text, :string)

    timestamps()
  end

  @spec changeset(t :: Ecto.Schema.t(), attrs :: map()) :: Ecto.Changeset.t()
  def changeset(corpus_item, attrs) do
    corpus_item
    |> cast(attrs, [
      :title,
      :author,
      :source_text,
      :source_grade,
      :license,
      :url,
      :source,
      :split,
      :reference_text
    ])
    |> validate_required([:title, :source_text, :source_grade])
    |> guard_frozen_test_split()
  end

  # Oracle-leakage guard: once an item is assigned to the frozen test split, no
  # changeset may move it out of (or otherwise reassign) that split. Keys on
  # change-map presence, not `get_change/2`: the latter returns nil for both
  # "unchanged" and "changed to nil", so a `%{split: nil}` update (the first
  # step of a nil-then-:train two-step leak) would otherwise slip through.
  defp guard_frozen_test_split(changeset) do
    reassigning_split? =
      Map.has_key?(changeset.changes, :split) and
        Map.get(changeset.changes, :split) != :test

    if changeset.data.split == :test and reassigning_split? do
      add_error(changeset, :split, "test split is frozen and cannot be reassigned")
    else
      changeset
    end
  end
end
