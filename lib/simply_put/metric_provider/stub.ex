defmodule SimplyPut.MetricProvider.Stub do
  @moduledoc """
  Deterministic fixture scores, no model inference. Default for `mix test`
  so the suite never needs to load a real Bumblebee checkpoint.
  """

  @behaviour SimplyPut.MetricProvider

  @impl true
  def entail(_premise, _hypothesis), do: {:ok, %{label: :entailment, score: 0.9}}

  @impl true
  def bertscore(_candidate, _reference), do: {:ok, %{precision: 0.9, recall: 0.9, f1: 0.9}}

  @impl true
  def sle(_candidate), do: {:ok, 0.5}

  @impl true
  def qafacteval(_source, _candidate), do: {:ok, 0.85}
end
