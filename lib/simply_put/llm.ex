defmodule SimplyPut.LLM do
  @moduledoc """
  Adapter seam: one behaviour, selected by config, so `mix test` is green on
  a fresh clone with no API key. Default impl is `SimplyPut.LLM.Stub`.
  """

  @doc """
  `opts` carries `:target_grade`, `:attempt`, and `:critique` -- a short
  natural-language critique of `text` against the target (see
  `SimplyPut.Readability.critique/2`). A real adapter should fold the
  critique into its prompt; the stub adapter may ignore it.
  """
  @callback rewrite(text :: String.t(), opts :: keyword()) ::
              {:ok, String.t()} | {:error, term()}
  @callback score(original :: String.t(), rewrite :: String.t()) ::
              {:ok, SimplyPut.JudgeScore.t()} | {:error, term()}

  @spec rewrite(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def rewrite(text, opts \\ []), do: impl().rewrite(text, opts)

  @doc """
  Multi-axis judge: simplicity, fidelity, and fluency on a 1-5 scale. The
  loop gates on all three; the dashboard's meaning-preserved verdict reads
  the fidelity axis.
  """
  @spec score(String.t(), String.t()) :: {:ok, SimplyPut.JudgeScore.t()} | {:error, term()}
  def score(original, rewrite), do: impl().score(original, rewrite)

  @doc "Which adapter module is currently configured, for reproducibility logging."
  @spec current_adapter() :: module()
  def current_adapter, do: impl()

  defp impl, do: Application.get_env(:simply_put, :llm, SimplyPut.LLM.Stub)
end
