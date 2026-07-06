defmodule SimplyPut.RewriteWorker do
  @moduledoc """
  Runs `Plainish.run/2` for one corpus item, writes a `run_results` row
  (upsert-per-item, feeds the `/runs` dashboard), and, when a `batch_id` is
  present, an additional append-only `rewrite_evaluations` row via
  `SimplyPut.Evaluation` (feeds the eval harness; Phase F). The two are
  independent: an evaluation-record failure logs a warning but doesn't
  block the `run_results` write.

  Idempotent for `run_results` only: unique on `[corpus_item_id, batch_id]`
  at enqueue time (Oban rejects a duplicate enqueue of the same item+batch),
  and the `run_results` write upserts on `corpus_item_id` so a retry after a
  partial failure replaces rather than duplicates that row. Not idempotent
  for `rewrite_evaluations` counts: that table is append-only by design, so
  a retry after `record_evaluation/3` succeeded but the job later failed
  legitimately appends a second row for the same item+batch. No custom
  retry framework -- Oban's built-in retry handles job-level failure.
  """

  use Oban.Worker,
    queue: :rewrites,
    unique: [fields: [:worker, :args], keys: [:corpus_item_id, :batch_id], period: :infinity]

  require Logger

  alias SimplyPut.CorpusItem
  alias SimplyPut.Evaluation
  alias SimplyPut.Plainish
  alias SimplyPut.Repo
  alias SimplyPut.RunResult

  @topic "runs"

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"corpus_item_id" => corpus_item_id} = args}) do
    item = Repo.get!(CorpusItem, corpus_item_id)
    batch_id = Map.get(args, "batch_id")

    case Plainish.run(item.source_text) do
      {:ok, result} -> write_result(item, result, batch_id)
      {:hold, result} -> write_result(item, result, batch_id)
      {:error, reason} -> {:error, reason}
    end
  end

  defp write_result(item, result, batch_id) do
    evaluation = record_evaluation(item, result, batch_id)

    attrs = %{
      corpus_item_id: item.id,
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
      {:ok, run_result} ->
        broadcast(item, run_result, evaluation)
        :ok

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp record_evaluation(_item, _result, nil), do: nil

  defp record_evaluation(item, result, batch_id) do
    case Evaluation.record(item, result, batch_id) do
      {:ok, evaluation} ->
        evaluation

      {:error, changeset} ->
        Logger.warning(
          "evaluation record failed, RunResult still written: #{inspect(changeset.errors)}"
        )

        nil
    end
  end

  defp broadcast(item, run_result, evaluation) do
    row = %{
      id: run_result.id,
      title: item.title,
      fk_before: run_result.fk_before,
      fk_after: run_result.fk_after,
      status: run_result.status,
      verdict: run_result.verdict,
      simplicity: evaluation && evaluation.simplicity,
      fidelity: evaluation && evaluation.fidelity,
      fluency: evaluation && evaluation.fluency,
      run_mode: evaluation && evaluation.run_mode
    }

    Phoenix.PubSub.broadcast(SimplyPut.PubSub, @topic, {:run_completed, row})
  end
end
