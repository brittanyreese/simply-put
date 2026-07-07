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

  Column mapping is by header name, not position, so the extra annotation
  columns Med-EASi ships (edit spans, similarity, per-scale grades) are
  ignored. Reads `Expert` (elaborated source), `Simple` (plain-language
  reference), and `idx` (stable row id) from `cbasu/Med-EASi` on Hugging
  Face. A file missing any of those three columns is rejected whole.
  """

  alias SimplyPut.CorpusItem
  alias SimplyPut.Readability
  alias SimplyPut.Repo

  NimbleCSV.define(SimplyPut.Corpus.MedEasiCSV, separator: ",", escape: "\"")

  alias SimplyPut.Corpus.MedEasiCSV

  @source_col "Expert"
  @reference_col "Simple"
  @id_col "idx"

  @doc """
  Imports a Med-EASi CSV. `source_grade` is the Flesch-Kincaid grade of the
  source sentence (Med-EASi ships no human-rated grade the way Clear Corpus
  does, so this is a computed stand-in, not a human rating).

  Transactional: a malformed row or a failed insert rolls back the whole
  import rather than leaving a partial one that would duplicate rows on
  retry. A row missing one of the mapped cells returns `{:malformed_row,
  row}` instead of crashing.
  """
  @spec import_med_easi(Path.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def import_med_easi(path) do
    Repo.transaction(fn ->
      case path |> File.read!() |> MedEasiCSV.parse_string(skip_headers: false) do
        [header | rows] -> import_rows(header, rows)
        [] -> Repo.rollback(:empty_file)
      end
    end)
  end

  defp import_rows(header, rows) do
    case column_indices(header) do
      {:ok, cols} ->
        rows
        |> Enum.reduce_while(0, fn row, count ->
          case insert_row(row, cols) do
            {:ok, _item} -> {:cont, count + 1}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)
        |> case do
          {:error, reason} -> Repo.rollback(reason)
          count -> count
        end

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp column_indices(header) do
    lookup = header |> Enum.with_index() |> Map.new()

    with {:ok, source} <- fetch_col(lookup, @source_col),
         {:ok, reference} <- fetch_col(lookup, @reference_col),
         {:ok, id} <- fetch_col(lookup, @id_col) do
      {:ok, %{source: source, reference: reference, id: id}}
    end
  end

  defp fetch_col(lookup, name) do
    case Map.fetch(lookup, name) do
      {:ok, index} -> {:ok, index}
      :error -> {:error, {:missing_column, name}}
    end
  end

  defp insert_row(row, cols) do
    id = Enum.at(row, cols.id)
    complex = Enum.at(row, cols.source)
    simple = Enum.at(row, cols.reference)

    if is_nil(id) or is_nil(complex) or is_nil(simple) do
      {:error, {:malformed_row, row}}
    else
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
  end

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
