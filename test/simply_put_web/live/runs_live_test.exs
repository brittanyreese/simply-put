defmodule SimplyPutWeb.RunsLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Ecto.Adapters.SQL.Sandbox
  alias SimplyPut.CorpusItem
  alias SimplyPut.Repo
  alias SimplyPut.RunResult

  @endpoint SimplyPutWeb.Endpoint

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})
    :ok
  end

  defp insert_run_result!(title, status) do
    item =
      %CorpusItem{}
      |> CorpusItem.changeset(%{title: title, source_text: "Text.", source_grade: 10.0})
      |> Repo.insert!()

    %RunResult{}
    |> RunResult.changeset(%{
      corpus_item_id: item.id,
      status: status,
      fk_before: 10.0,
      fk_after: 5.0,
      target: 6.0,
      attempts: 1,
      text_out: "Text."
    })
    |> Repo.insert!()

    item
  end

  test "streams existing runs on mount and fills a new row live via PubSub broadcast" do
    item = insert_run_result!("Seeded Story", :passed)

    {:ok, view, html} = live(build_conn(), "/runs")

    assert html =~ "Seeded Story"
    assert html =~ "passed"
    assert html =~ "1</strong> total" or html =~ ">1</strong>"

    new_row = %{
      id: item.id + 1_000_000,
      title: "Live-Filled Story",
      fk_before: 12.0,
      fk_after: 4.5,
      status: :held
    }

    Phoenix.PubSub.broadcast(SimplyPut.PubSub, "runs", {:run_completed, new_row})

    assert render(view) =~ "Live-Filled Story"
    assert render(view) =~ "held"
  end
end
