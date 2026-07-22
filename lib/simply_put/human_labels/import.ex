defmodule SimplyPut.HumanLabels.Import do
  @moduledoc """
  CSV importer for existing human-labeled judge-calibration datasets
  (ASSET, PLABA TREC), so Phase G's kappa validation doesn't require new
  manual annotation.

  Expected CSV columns (already pivoted to one row per rated item):
  `item_id,original,simplification,simplicity,fidelity,fluency,annotator`.
  ASSET's raw release ships one row per (item, aspect, worker) rather than
  this wide shape; pivoting the raw download into this format is an
  out-of-band acquisition step (same pattern as Phase C's corpus
  imports), not something this importer does.
  """

  alias SimplyPut.HumanLabel
  alias SimplyPut.Repo

  NimbleCSV.define(SimplyPut.HumanLabels.CSV, separator: ",", escape: "\"")

  alias SimplyPut.HumanLabels.CSV

  @doc """
  Imports a wide-format human-rating CSV as one `human_labels` row per
  line, tagged with `source_dataset` (`:asset` or `:plaba_trec`).

  Transactional: a malformed row or a failed insert rolls back the whole
  import rather than leaving a partial one that would duplicate rows on
  retry. A malformed row (wrong column count, non-integer score) returns
  an error tuple instead of crashing.
  """
  @spec import(Path.t(), :asset | :plaba_trec) :: {:ok, non_neg_integer()} | {:error, term()}
  def import(path, source_dataset) when source_dataset in [:asset, :plaba_trec] do
    Repo.transaction(fn ->
      rows = path |> File.read!() |> CSV.parse_string()

      case insert_all_rows(rows, source_dataset) do
        {:error, reason} -> Repo.rollback(reason)
        count -> count
      end
    end)
  end

  defp insert_all_rows(rows, source_dataset) do
    Enum.reduce_while(rows, 0, fn row, count ->
      case insert_row(row, source_dataset) do
        {:ok, _label} -> {:cont, count + 1}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp insert_row(
         [item_id, original, simplification, simplicity, fidelity, fluency, annotator],
         source_dataset
       ) do
    with {:ok, simplicity_int} <- parse_int(simplicity),
         {:ok, fidelity_int} <- parse_int(fidelity),
         {:ok, fluency_int} <- parse_int(fluency) do
      attrs = %{
        external_item_id: item_id,
        source_dataset: source_dataset,
        original_text: original,
        candidate_text: simplification,
        simplicity: simplicity_int,
        fidelity: fidelity_int,
        fluency: fluency_int,
        annotator: annotator
      }

      %HumanLabel{} |> HumanLabel.changeset(attrs) |> Repo.insert()
    end
  end

  defp insert_row(row, _source_dataset), do: {:error, {:malformed_row, row}}

  defp parse_int(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _ -> {:error, {:invalid_integer, value}}
    end
  end
end
