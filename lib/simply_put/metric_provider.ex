defmodule SimplyPut.MetricProvider do
  @moduledoc """
  Adapter seam for model-based metrics: faithfulness (SummaC-style NLI
  entailment, QAFactEval-style QA-based factuality), semantic similarity
  (BERTScore), and reference-less simplicity (SLE). All four run natively
  via `SimplyPut.MetricProvider.Bumblebee` (Phase M), not a remote service.

  Default (no config set) resolves to `SimplyPut.MetricProvider.Stub`, so
  `mix test` never needs to load a real model checkpoint. Phase M wires
  `SimplyPut.MetricProvider.Bumblebee` in as the runtime default.
  """

  @callback entail(premise :: String.t(), hypothesis :: String.t()) ::
              {:ok, %{label: :entailment | :neutral | :contradiction, score: float()}}
              | {:error, term()}
  @callback bertscore(candidate :: String.t(), reference :: String.t()) ::
              {:ok, %{precision: float(), recall: float(), f1: float()}} | {:error, term()}
  @callback sle(candidate :: String.t()) :: {:ok, float()} | {:error, term()}
  @callback qafacteval(source :: String.t(), candidate :: String.t()) ::
              {:ok, float()} | {:error, term()}

  @spec entail(String.t(), String.t()) ::
          {:ok, %{label: :entailment | :neutral | :contradiction, score: float()}}
          | {:error, term()}
  def entail(premise, hypothesis), do: impl().entail(premise, hypothesis)

  @spec bertscore(String.t(), String.t()) ::
          {:ok, %{precision: float(), recall: float(), f1: float()}} | {:error, term()}
  def bertscore(candidate, reference), do: impl().bertscore(candidate, reference)

  @spec sle(String.t()) :: {:ok, float()} | {:error, term()}
  def sle(candidate), do: impl().sle(candidate)

  @spec qafacteval(String.t(), String.t()) :: {:ok, float()} | {:error, term()}
  def qafacteval(source, candidate), do: impl().qafacteval(source, candidate)

  @doc """
  Whether the active provider is the deterministic `Stub` (fixture scores, no
  model inference). Reports built while this is true must be labeled SIMULATED:
  every model-based metric is a constant, not a measurement.
  """
  @spec simulated?() :: boolean()
  def simulated?, do: impl() == SimplyPut.MetricProvider.Stub

  defp impl, do: Application.get_env(:simply_put, :metric_provider, SimplyPut.MetricProvider.Stub)
end
