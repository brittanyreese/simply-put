defmodule SimplyPutWeb.RunsLive do
  @moduledoc """
  Read-only `/runs` dashboard. Streams the batch table (>100 rows, Iron
  Law #2) and fills live as `RewriteWorker` broadcasts completions.
  """

  use Phoenix.LiveView

  import Ecto.Query, only: [from: 2]

  alias SimplyPut.CorpusItem
  alias SimplyPut.Repo
  alias SimplyPut.RunResult

  @topic "runs"
  @buckets [{0, 2}, {2, 4}, {4, 6}, {6, 8}, {8, 10}, {10, 999}]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(SimplyPut.PubSub, @topic)
    end

    {:ok, socket |> stream(:runs, []) |> assign_empty_summary()}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    rows = load_rows()

    socket =
      socket
      |> stream(:runs, rows, reset: true)
      |> assign_summary(rows)

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

    <table id="runs">
      <thead>
        <tr>
          <th>Title</th>
          <th>Grade before</th>
          <th>Grade after</th>
          <th>Status</th>
        </tr>
      </thead>
      <tbody id="runs-body" phx-update="stream">
        <tr :for={{dom_id, row} <- @streams.runs} id={dom_id}>
          <td>{row.title}</td>
          <td>{Float.round(row.fk_before, 1)}</td>
          <td>{Float.round(row.fk_after, 1)}</td>
          <td class={to_string(row.status)}>{row.status}</td>
        </tr>
      </tbody>
    </table>
    """
  end

  defp load_rows do
    from(r in RunResult,
      join: c in CorpusItem,
      on: c.id == r.corpus_item_id,
      order_by: [desc: r.inserted_at],
      select: %{
        id: r.id,
        title: c.title,
        fk_before: r.fk_before,
        fk_after: r.fk_after,
        status: r.status
      }
    )
    |> Repo.all()
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
