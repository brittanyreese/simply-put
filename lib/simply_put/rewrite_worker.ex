defmodule SimplyPut.RewriteWorker do
  @moduledoc """
  Runs `Plainish.run/2` for one corpus item and writes a `run_results` row.

  Idempotent: unique on `[corpus_item_id, batch_id]` at enqueue time (Oban
  rejects a duplicate enqueue of the same item+batch), and the write upserts
  on `corpus_item_id` so a retry after a partial failure replaces rather than
  duplicates the row. No custom retry framework -- Oban's built-in retry
  handles job-level failure.
  """

  use Oban.Worker,
    queue: :rewrites,
    unique: [fields: [:worker, :args], keys: [:corpus_item_id, :batch_id], period: :infinity]

  alias SimplyPut.CorpusItem
  alias SimplyPut.Plainish
  alias SimplyPut.Repo
  alias SimplyPut.RunResult

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"corpus_item_id" => corpus_item_id}}) do
    item = Repo.get!(CorpusItem, corpus_item_id)

    case Plainish.run(item.source_text) do
      {:ok, result} -> write_result(item.id, result)
      {:hold, result} -> write_result(item.id, result)
      {:error, reason} -> {:error, reason}
    end
  end

  defp write_result(corpus_item_id, result) do
    attrs = %{
      corpus_item_id: corpus_item_id,
      status: result.status,
      fk_before: result.fk_before,
      fk_after: result.fk_after,
      target: result.target,
      attempts: result.attempts,
      text_out: result.text_out,
      verdict: result.verdict
    }

    %RunResult{}
    |> RunResult.changeset(attrs)
    |> Repo.insert(
      on_conflict:
        {:replace,
         [:status, :fk_before, :fk_after, :target, :attempts, :text_out, :verdict, :updated_at]},
      conflict_target: :corpus_item_id
    )
    |> case do
      {:ok, _run_result} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end
end
