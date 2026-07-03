defmodule SimplyPut.RewriteWorkerTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: SimplyPut.Repo, notifier: Oban.Notifiers.PG

  alias Ecto.Adapters.SQL.Sandbox
  alias SimplyPut.CorpusItem
  alias SimplyPut.Repo
  alias SimplyPut.RewriteWorker
  alias SimplyPut.RunResult

  setup do
    :ok = Sandbox.checkout(Repo)
  end

  defp insert_corpus_item! do
    %CorpusItem{}
    |> CorpusItem.changeset(%{
      title: "Complex fixture",
      source_text:
        "Individuals utilize numerous significant facilitate additionally " <>
          "demonstrate subsequently commence endeavor terminate comprehend " <>
          "approximately sufficient methods.",
      source_grade: 20.0
    })
    |> Repo.insert!()
  end

  test "runs the pipeline and writes a run_results row" do
    item = insert_corpus_item!()

    assert :ok = perform_job(RewriteWorker, %{"corpus_item_id" => item.id, "batch_id" => "b1"})

    assert %RunResult{corpus_item_id: id, status: :passed} =
             Repo.get_by!(RunResult, corpus_item_id: item.id)

    assert id == item.id
  end

  test "retrying the same job replaces rather than duplicates the row" do
    item = insert_corpus_item!()
    args = %{"corpus_item_id" => item.id, "batch_id" => "b1"}

    assert :ok = perform_job(RewriteWorker, args)
    assert :ok = perform_job(RewriteWorker, args)

    assert Repo.aggregate(RunResult, :count) == 1
  end
end
