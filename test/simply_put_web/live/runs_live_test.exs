defmodule SimplyPutWeb.RunsLiveTest do
  use ExUnit.Case, async: false

  import Ecto.Query
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Ecto.Adapters.SQL.Sandbox
  alias SimplyPut.CorpusItem
  alias SimplyPut.Repo
  alias SimplyPut.RewriteEvaluation
  alias SimplyPut.RunResult

  @endpoint SimplyPutWeb.Endpoint

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})
    :ok
  end

  defp insert_run_result!(title, status, verdict \\ nil) do
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
      text_out: "Text.",
      verdict: verdict
    })
    |> Repo.insert!()

    item
  end

  defp insert_evaluation!(item, attrs) do
    {custom_inserted_at, attrs} = Map.pop(attrs, :inserted_at)

    default = %{
      corpus_item_id: item.id,
      batch_id: "batch-1",
      run_mode: :iterative,
      fk_before_bp: 1000,
      fk_after_bp: 500,
      smog_bp: 600,
      target_bp: 600,
      structural_gate_passed: true,
      attempts: 1,
      text_out: "Text."
    }

    evaluation =
      %RewriteEvaluation{}
      |> RewriteEvaluation.changeset(Map.merge(default, attrs))
      |> Repo.insert!()

    if custom_inserted_at do
      Repo.update_all(from(e in RewriteEvaluation, where: e.id == ^evaluation.id),
        set: [inserted_at: custom_inserted_at]
      )
    end

    evaluation
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

  test "shows the judge verdict when present, and \"-\" when the judge is off" do
    insert_run_result!("No Judge", :passed)
    insert_run_result!("Preserved", :passed, %{fk_pass: true, meaning_preserved: true})
    insert_run_result!("Lost Meaning", :held, %{fk_pass: false, meaning_preserved: false})

    {:ok, _view, html} = live(build_conn(), "/runs")

    assert html =~ "preserved"
    assert html =~ "lost"
    assert html =~ "-</td>"
  end

  test "shows the judge axes and run_mode when an evaluation exists" do
    item = insert_run_result!("Evaluated", :passed)

    insert_evaluation!(item, %{
      run_mode: :iterative,
      simplicity: 4,
      fidelity: 5,
      fluency: 4
    })

    {:ok, _view, html} = live(build_conn(), "/runs")

    assert html =~ ">4<"
    assert html =~ ">5<"
    assert html =~ "iterative"
  end

  test "shows \"-\" for the judge axes when no evaluation exists for that item" do
    insert_run_result!("Never evaluated", :passed)

    {:ok, _view, html} = live(build_conn(), "/runs")

    assert html =~ "-</td>"
  end

  test "picks the most recent evaluation when an item has more than one" do
    item = insert_run_result!("Multi-run", :passed)

    insert_evaluation!(item, %{
      run_mode: :single_shot,
      simplicity: 2,
      fidelity: 2,
      fluency: 2,
      inserted_at: ~N[2020-01-01 00:00:00]
    })

    insert_evaluation!(item, %{
      run_mode: :iterative,
      simplicity: 5,
      fidelity: 5,
      fluency: 5,
      inserted_at: ~N[2026-01-01 00:00:00]
    })

    {:ok, _view, html} = live(build_conn(), "/runs")

    # The run-mode SUMMARY table legitimately shows both modes (it
    # aggregates across all evaluations); only the per-item ROW should
    # show the most recent one, so scope the assertion to that row.
    [_before, row_and_rest] = String.split(html, "Multi-run", parts: 2)
    [row, _rest] = String.split(row_and_rest, "</tr>", parts: 2)

    assert row =~ "iterative"
    refute row =~ "single_shot"
  end

  test "run-mode summary table reports item count per run_mode" do
    item_a = insert_run_result!("Item A", :passed)
    item_b = insert_run_result!("Item B", :passed)

    insert_evaluation!(item_a, %{run_mode: :iterative, fk_after_bp: 500})
    insert_evaluation!(item_b, %{run_mode: :iterative, fk_after_bp: 700})
    insert_evaluation!(item_a, %{run_mode: :single_shot, batch_id: "batch-2", fk_after_bp: 900})

    {:ok, _view, html} = live(build_conn(), "/runs")

    assert html =~ "run-mode-summary"
    assert html =~ "iterative"
    assert html =~ "single_shot"
    assert html =~ "6.0"
  end
end
