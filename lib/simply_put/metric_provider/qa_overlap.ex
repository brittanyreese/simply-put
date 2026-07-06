defmodule SimplyPut.MetricProvider.QAOverlap do
  @moduledoc """
  Token-overlap F1 between two extracted answers to the same question.
  Pure string logic, fully testable without a model checkpoint.

  note: this is a simplified stand-in for QAFactEval's learned
  LERC-QUIP answerability classifier (a BERT `[CLS]` embedding plus one
  linear layer, trained on human judgments -- see the MOCHA repo). The
  real head needs a one-time PyTorch-to-Axon weight conversion this
  environment can't perform (no network egress to fetch or inspect the
  checkpoint here). Upgrade path: port LERC-QUIP's weights once
  that conversion has been done and verified against reference scores;
  until then, token-overlap F1 between the source-answer and
  candidate-answer to the same generated question is the QA-based
  factuality signal.
  """

  @doc "Token-overlap F1 between two answer strings (case-insensitive)."
  @spec f1(String.t(), String.t()) :: float()
  def f1(answer_a, answer_b) do
    tokens_a = tokenize(answer_a)
    tokens_b = tokenize(answer_b)

    cond do
      tokens_a == [] and tokens_b == [] ->
        1.0

      tokens_a == [] or tokens_b == [] ->
        0.0

      true ->
        common = count_common(tokens_a, tokens_b)
        precision = common / length(tokens_a)
        recall = common / length(tokens_b)

        if precision + recall == 0.0,
          do: 0.0,
          else: 2 * precision * recall / (precision + recall)
    end
  end

  defp tokenize(text) do
    text |> String.downcase() |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)
  end

  defp count_common(tokens_a, tokens_b) do
    freq_b = Enum.frequencies(tokens_b)

    {common, _remaining} =
      Enum.reduce(tokens_a, {0, freq_b}, fn token, {count, freq} ->
        case Map.get(freq, token, 0) do
          n when n > 0 -> {count + 1, Map.update!(freq, token, &(&1 - 1))}
          _ -> {count, freq}
        end
      end)

    common
  end
end
