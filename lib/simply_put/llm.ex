defmodule SimplyPut.LLM do
  @moduledoc """
  Adapter seam: one behaviour, selected by config, so `mix test` is green on
  a fresh clone with no API key. Default impl is `SimplyPut.LLM.Stub`.
  """

  @callback rewrite(text :: String.t(), opts :: keyword()) ::
              {:ok, String.t()} | {:error, term()}
  @callback judge(original :: String.t(), rewrite :: String.t()) ::
              {:ok, %{verdict: :preserved | :lost, rationale: String.t()}} | {:error, term()}

  @spec rewrite(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def rewrite(text, opts \\ []), do: impl().rewrite(text, opts)

  @spec judge(String.t(), String.t()) ::
          {:ok, %{verdict: :preserved | :lost, rationale: String.t()}} | {:error, term()}
  def judge(original, rewrite), do: impl().judge(original, rewrite)

  defp impl, do: Application.get_env(:simply_put, :llm, SimplyPut.LLM.Stub)
end
