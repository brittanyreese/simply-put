defmodule SimplyPutWeb.RunsLive do
  @moduledoc """
  Read-only `/runs` dashboard. Streams the batch table (>100 rows, Iron
  Law #2) and fills live as `RewriteWorker` broadcasts completions.

  Each row also shows the most recent `rewrite_evaluations` axes
  (simplicity/fidelity/fluency/run_mode) for that corpus item, when one
  exists -- most historical runs predate the eval harness (Phase 1) and
  have none, same fallback pattern already used for the judge verdict.
  A run-mode comparison summary (count + mean FK-after per mode, across
  all evaluations, not just one batch) sits above the table.
  """

  use Phoenix.LiveView

  import Ecto.Query, only: [from: 2]

  alias SimplyPut.CorpusItem
  alias SimplyPut.Repo
  alias SimplyPut.RewriteEvaluation
  alias SimplyPut.RunResult

  @topic "runs"
  @buckets [{-999, 0}, {0, 2}, {2, 4}, {4, 6}, {6, 8}, {8, 10}, {10, 999}]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(SimplyPut.PubSub, @topic)
    end

    {:ok, socket |> stream(:runs, []) |> assign_empty_summary() |> assign(:run_mode_summary, %{})}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    rows = load_rows()

    socket =
      socket
      |> stream(:runs, rows, reset: true)
      |> assign_summary(rows)
      |> assign(:run_mode_summary, load_run_mode_summary())

    {:noreply, socket}
  end

  @impl true
  def handle_info({:run_completed, row}, socket) do
    socket =
      socket
      |> stream_insert(:runs, row, at: 0)
      |> apply_summary(row)

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h1>Simply Put -- live runs</h1>

    <div class="summary">
      <div><strong>{@total}</strong> total</div>
      <div><strong class="passed">{@passed}</strong> passed</div>
      <div><strong class="held">{@held}</strong> held</div>
    </div>

    <div class="histogram">
      <div :for={{label, {passed, held}} <- @histogram} class="bar">
        <span class="held-part" style={"height: #{bar_height(held, @histogram)}px"}></span>
        <span class="passed-part" style={"height: #{bar_height(passed, @histogram)}px"}></span>
        <div class="label">{label}</div>
      </div>
    </div>

    <table id="run-mode-summary">
      <caption>Run-mode comparison (all evaluations, not one batch)</caption>
      <thead>
        <tr>
          <th>Run mode</th>
          <th>Items</th>
          <th>Mean FK after</th>
        </tr>
      </thead>
      <tbody>
        <tr :for={{run_mode, summary} <- @run_mode_summary}>
          <td>{run_mode}</td>
          <td>{summary.count}</td>
          <td>{format_avg(summary.avg_fk_after)}</td>
        </tr>
      </tbody>
    </table>

    <table id="runs">
      <thead>
        <tr>
          <th>Title</th>
          <th>Grade before</th>
          <th>Grade after</th>
          <th>Status</th>
          <th>Meaning</th>
          <th>Simplicity</th>
          <th>Fidelity</th>
          <th>Fluency</th>
          <th>Run mode</th>
        </tr>
      </thead>
      <tbody id="runs-body" phx-update="stream">
        <tr :for={{dom_id, row} <- @streams.runs} id={dom_id}>
          <td>{row.title}</td>
          <td>{Float.round(row.fk_before, 1)}</td>
          <td>{Float.round(row.fk_after, 1)}</td>
          <td class={to_string(row.status)}>{row.status}</td>
          <td class={verdict_class(row)}>{verdict_label(row)}</td>
          <td>{axis_label(Map.get(row, :simplicity))}</td>
          <td>{axis_label(Map.get(row, :fidelity))}</td>
          <td>{axis_label(Map.get(row, :fluency))}</td>
          <td>{run_mode_label(Map.get(row, :run_mode))}</td>
        </tr>
      </tbody>
    </table>
    """
  end

  defp load_rows do
    evaluations_by_item = latest_evaluation_by_corpus_item()

    from(r in RunResult,
      join: c in CorpusItem,
      on: c.id == r.corpus_item_id,
      order_by: [desc: r.inserted_at],
      select: %{
        id: r.id,
        corpus_item_id: r.corpus_item_id,
        title: c.title,
        fk_before: r.fk_before,
        fk_after: r.fk_after,
        status: r.status,
        verdict: r.verdict
      }
    )
    |> Repo.all()
    |> Enum.map(fn row ->
      Map.merge(row, Map.get(evaluations_by_item, row.corpus_item_id, empty_evaluation_fields()))
    end)
  end

  defp latest_evaluation_by_corpus_item do
    RewriteEvaluation
    |> Repo.all()
    |> Enum.group_by(& &1.corpus_item_id)
    |> Map.new(fn {corpus_item_id, evaluations} ->
      latest = Enum.max_by(evaluations, & &1.inserted_at, NaiveDateTime)

      {corpus_item_id,
       %{
         simplicity: latest.simplicity,
         fidelity: latest.fidelity,
         fluency: latest.fluency,
         run_mode: latest.run_mode
       }}
    end)
  end

  defp empty_evaluation_fields, do: %{simplicity: nil, fidelity: nil, fluency: nil, run_mode: nil}

  defp load_run_mode_summary do
    RewriteEvaluation
    |> Repo.all()
    |> Enum.group_by(& &1.run_mode)
    |> Map.new(fn {run_mode, rows} ->
      # `&(&1.field / 100)` capture syntax mis-parses on this Elixir
      # version (the "/100" reads as a function-arity marker, not
      # division -- BadArityError, "arity 100"); use an explicit `fn`.
      avg_fk = rows |> Enum.map(fn row -> row.fk_after_bp / 100 end) |> average()
      {run_mode, %{count: length(rows), avg_fk_after: avg_fk}}
    end)
  end

  defp average([]), do: nil
  defp average(values), do: Enum.sum(values) / length(values)

  defp format_avg(nil), do: "-"
  defp format_avg(value), do: Float.round(value, 2)

  defp axis_label(nil), do: "-"
  defp axis_label(value), do: value

  defp run_mode_label(nil), do: "-"
  defp run_mode_label(run_mode), do: run_mode

  # Judge is opt-in (`deps[:judge]`, default off) -- most rows have no
  # verdict. `Map.get/2` (not dot-access) so rows from before this column
  # existed (e.g. broadcast payloads in tests) don't raise KeyError.
  defp verdict_label(row) do
    case meaning_preserved(Map.get(row, :verdict)) do
      true -> "preserved"
      false -> "lost"
      nil -> "-"
    end
  end

  defp verdict_class(row) do
    case meaning_preserved(Map.get(row, :verdict)) do
      true -> "preserved"
      false -> "lost"
      nil -> ""
    end
  end

  defp meaning_preserved(nil), do: nil

  defp meaning_preserved(verdict) do
    Map.get(verdict, :meaning_preserved, Map.get(verdict, "meaning_preserved"))
  end

  defp assign_empty_summary(socket) do
    assign(socket, total: 0, passed: 0, held: 0, histogram: empty_histogram())
  end

  defp assign_summary(socket, rows) do
    passed = Enum.count(rows, &(&1.status == :passed))
    held = Enum.count(rows, &(&1.status == :held))

    assign(socket,
      total: length(rows),
      passed: passed,
      held: held,
      histogram: build_histogram(rows)
    )
  end

  defp apply_summary(socket, row) do
    socket
    |> update(:total, &(&1 + 1))
    |> update(:passed, fn n -> if row.status == :passed, do: n + 1, else: n end)
    |> update(:held, fn n -> if row.status == :held, do: n + 1, else: n end)
    |> update(:histogram, &bump_histogram(&1, row))
  end

  defp empty_histogram do
    Map.new(@buckets, fn bucket -> {bucket_label(bucket), {0, 0}} end)
  end

  defp build_histogram(rows) do
    Enum.reduce(rows, empty_histogram(), &bump_histogram(&2, &1))
  end

  defp bump_histogram(histogram, row) do
    label = row.fk_after |> bucket_for() |> bucket_label()

    Map.update!(histogram, label, fn {passed, held} ->
      if row.status == :passed, do: {passed + 1, held}, else: {passed, held + 1}
    end)
  end

  defp bucket_for(grade) do
    Enum.find(@buckets, List.last(@buckets), fn {low, high} -> grade >= low and grade < high end)
  end

  defp bucket_label({-999, 0}), do: "<0"
  defp bucket_label({low, 999}), do: "#{low}+"
  defp bucket_label({low, high}), do: "#{low}-#{high}"

  @max_bar_px 100

  # Scales a bar segment to fit the fixed-height .histogram container
  # (see layouts.ex) -- raw counts * a fixed px multiplier overflowed the
  # container once any bucket held more than ~30 items.
  defp bar_height(count, histogram) do
    stack_max =
      histogram |> Map.values() |> Enum.map(fn {p, h} -> p + h end) |> Enum.max(fn -> 1 end)

    scale = if stack_max > 0, do: @max_bar_px / stack_max, else: 0
    Float.round(count * scale, 1)
  end
end
