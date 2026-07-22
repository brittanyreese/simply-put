defmodule SimplyPut.MetricProvider.BertScore do
  @moduledoc """
  Cosine-similarity scoring given sentence embeddings. Pure Nx math, fully
  testable without a model checkpoint -- construct tensors by hand in
  tests; `SimplyPut.MetricProvider.Bumblebee` supplies real embeddings.

  Scope: this scores whole-sentence pooled embeddings (a single vector
  per text), not true token-level BERTScore (per-token greedy matching).
  Bumblebee's `text_embedding` task only exposes a pooled `:embedding`
  output, not per-token hidden states, without dropping to the raw Axon
  model call. Because precision and recall collapse to the same cosine
  similarity at sentence granularity, `f1` here always equals `precision`
  and `recall`. Upgrade path: call the base model directly (bypass the
  task serving) to get per-token hidden states for true greedy matching,
  if that granularity turns out to matter.
  """

  @doc """
  `candidate_embedding` and `reference_embedding` are `{dim}` tensors (one
  pooled vector each). Returns cosine similarity as precision, recall, and
  f1 -- identical values at this granularity (see moduledoc).
  """
  @spec score(Nx.Tensor.t(), Nx.Tensor.t()) :: %{
          precision: float(),
          recall: float(),
          f1: float()
        }
  def score(candidate_embedding, reference_embedding) do
    similarity = cosine_similarity(candidate_embedding, reference_embedding)

    %{precision: similarity, recall: similarity, f1: similarity}
  end

  defp cosine_similarity(a, b) do
    dot = a |> Nx.multiply(b) |> Nx.sum() |> Nx.to_number()
    norm_a = a |> Nx.pow(2) |> Nx.sum() |> Nx.sqrt() |> Nx.to_number()
    norm_b = b |> Nx.pow(2) |> Nx.sum() |> Nx.sqrt() |> Nx.to_number()

    if norm_a == 0.0 or norm_b == 0.0, do: 0.0, else: dot / (norm_a * norm_b)
  end
end
