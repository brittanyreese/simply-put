defmodule SimplyPut.Corpus.Import do
  @moduledoc """
  CSV importer for eval corpora. Only Med-EASi is implemented for Phase 1
  (see the plan's KEY DECISION: a single open corpus for the main harness,
  no licensing friction).

  Split assignment is a deterministic hash of each row's id into
  train/dev/test, computed once at import time: re-importing the same file
  reproduces the same split, and `CorpusItem.changeset/2` refuses to move an
  item out of the `:test` split once it's been assigned (oracle-leakage
  guard).

  Expected Med-EASi CSV columns: `id`, `complex`, `simple` (the elaborated
  source sentence and its plain-language reference). Adjust the column
  mapping here once the real dataset file (`cbasu/Med-EASi` on Hugging Face,
  or `github.com/Chandrayee/CTRL-SIMP`) is acquired, if its actual column
  names differ.
  """

  alias SimplyPut.CorpusItem
  alias SimplyPut.Readability
  alias SimplyPut.Repo

  NimbleCSV.define(SimplyPut.Corpus.MedEasiCSV, separator: ",", escape: "\"")

  alias SimplyPut.Corpus.MedEasiCSV

  @doc """
  Imports a Med-EASi CSV. `source_grade` is the Flesch-Kincaid grade of the
  source sentence (Med-EASi ships no human-rated grade the way Clear Corpus
  does, so this is a computed stand-in, not a human rating).

  Transactional: a malformed row or a failed insert rolls back the whole
  import rather than leaving a partial one that would duplicate rows on
  retry. A malformed row (wrong column count) returns `{:malformed_row,
  row}` instead of crashing.
  """
  @spec import_med_easi(Path.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def import_med_easi(path) do
    Repo.transaction(fn ->
      path
      |> File.read!()
      |> MedEasiCSV.parse_string()
      |> Enum.reduce_while(0, fn row, count ->
        case insert_row(row) do
          {:ok, _item} -> {:cont, count + 1}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
      |> case do
        {:error, reason} -> Repo.rollback(reason)
        count -> count
      end
    end)
  end

  defp insert_row([id, complex, simple]) do
    attrs = %{
      title: "med_easi-#{id}",
      source_text: complex,
      source_grade: Readability.flesch_kincaid(complex),
      reference_text: simple,
      source: :med_easi,
      split: split_for(id)
    }

    %CorpusItem{} |> CorpusItem.changeset(attrs) |> Repo.insert()
  end

  defp insert_row(row), do: {:error, {:malformed_row, row}}

  @doc """
  Deterministic train (70%) / dev (15%) / test (15%) assignment for a stable
  row id. Same id always resolves to the same split.
  """
  @spec split_for(String.t()) :: :train | :dev | :test
  def split_for(id) when is_binary(id) do
    hash = :erlang.phash2(id, 100)

    cond do
      hash < 70 -> :train
      hash < 85 -> :dev
      true -> :test
    end
  end
end
