defmodule SimplyPut.BatchTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: SimplyPut.Repo, notifier: Oban.Notifiers.PG

  alias Ecto.Adapters.SQL.Sandbox
  alias SimplyPut.Batch
  alias SimplyPut.CorpusItem
  alias SimplyPut.Repo
  alias SimplyPut.RewriteWorker
  alias SimplyPut.RunResult

  setup do
    :ok = Sandbox.checkout(Repo)
  end

  defp insert_corpus_items!(count) do
    for n <- 1..count do
      %CorpusItem{}
      |> CorpusItem.changeset(%{
        title: "Item #{n}",
        source_text: "The cat sat on the mat.",
        source_grade: 3.0
      })
      |> Repo.insert!()
    end
  end

  test "enqueues one job per corpus item" do
    insert_corpus_items!(3)

    jobs = Batch.enqueue_all("test-batch")

    assert length(jobs) == 3
    assert_enqueued(worker: RewriteWorker, args: %{"batch_id" => "test-batch"})
  end

  test "draining the batch writes one run_results row per item" do
    insert_corpus_items!(3)
    Batch.enqueue_all("drain-batch")

    assert %{success: 3, failure: 0} = Oban.drain_queue(queue: :rewrites)
    assert Repo.aggregate(RunResult, :count) == 3
  end

  test "calling enqueue_all twice with the same batch_id does not duplicate jobs" do
    insert_corpus_items!(1)

    Batch.enqueue_all("dup-batch")
    Batch.enqueue_all("dup-batch")

    assert Repo.aggregate(Oban.Job, :count) == 1
  end
end
