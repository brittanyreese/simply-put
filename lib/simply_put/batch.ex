defmodule SimplyPut.Batch do
  @moduledoc "Fans out one `RewriteWorker` job per corpus item."

  alias SimplyPut.CorpusItem
  alias SimplyPut.Repo
  alias SimplyPut.RewriteWorker

  @doc """
  Enqueues one job per `corpus_items` row under `batch_id` (defaults to a
  fresh UUID). Returns the inserted (or conflicting) `Oban.Job` structs.

  Uses `Oban.insert/1` per job, not `insert_all/1` -- `insert_all/1` only
  dedupes duplicates within the same call, not against jobs already
  persisted from a prior call, so it can't give the "re-running
  `enqueue_all/1` with the same `batch_id` doesn't duplicate" guarantee.
  `insert/1` does the real existence check. ~200 sequential local SQLite
  inserts is not a real cost.
  """
  @spec enqueue_all(String.t()) :: [Oban.Job.t()]
  def enqueue_all(batch_id \\ Ecto.UUID.generate()) do
    CorpusItem
    |> Repo.all()
    |> Enum.map(fn item ->
      {:ok, job} =
        %{"corpus_item_id" => item.id, "batch_id" => batch_id}
        |> RewriteWorker.new()
        |> Oban.insert()

      job
    end)
  end
end
