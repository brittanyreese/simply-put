defmodule SimplyPut.MetricProvider.Bumblebee do
  @moduledoc """
  Native model-based metrics via Bumblebee/Nx/EXLA -- no external service.
  See `docs/research/2026-07-04-bumblebee-vs-python-sidecar-metrics.md` for
  the research behind this choice over a Python sidecar.

  Not the runtime default yet (`SimplyPut.MetricProvider` still defaults to
  `Stub`): this environment has no network egress to download and verify
  real checkpoints against this module, so its checkpoint-loading path is
  untested here. Wire it in via `config :simply_put, :metric_provider,
  SimplyPut.MetricProvider.Bumblebee` once verified against a live
  checkpoint download (see the scratchpad's "Checkpoints to pin" section).

  `entail/2` and `sle/1` map directly onto stock Bumblebee task servings.
  `bertscore/2` and `qafacteval/2` are documented simplifications of the
  full published metrics -- see `SimplyPut.MetricProvider.BertScore` and
  `SimplyPut.MetricProvider.QAOverlap` moduledocs for what's simplified and
  the upgrade path for each.
  """

  @behaviour SimplyPut.MetricProvider

  alias SimplyPut.MetricProvider.BertScore
  alias SimplyPut.MetricProvider.Bumblebee.Servings
  alias SimplyPut.MetricProvider.QAOverlap

  @impl true
  def entail(premise, hypothesis) do
    case Servings.run(:summac, {premise, hypothesis}) do
      {:ok, %{predictions: [_ | _] = predictions}} ->
        top = Enum.max_by(predictions, & &1.score)
        {:ok, %{label: normalize_label(top.label), score: top.score}}

      {:ok, other} ->
        {:error, {:unexpected_response, other}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def bertscore(candidate, reference) do
    with {:ok, cand_result} <- Servings.run(:bertscore, candidate),
         {:ok, ref_result} <- Servings.run(:bertscore, reference),
         %{embedding: cand_emb} <- cand_result,
         %{embedding: ref_emb} <- ref_result do
      {:ok, BertScore.score(cand_emb, ref_emb)}
    else
      {:error, reason} -> {:error, reason}
      other -> {:error, {:unexpected_response, other}}
    end
  end

  @impl true
  def sle(candidate) do
    case Servings.run(:sle, candidate) do
      {:ok, %{predictions: [%{score: score} | _]}} -> {:ok, score}
      {:ok, other} -> {:error, {:unexpected_response, other}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def qafacteval(source, candidate) do
    with {:ok, questions} <- generate_questions(source),
         {:ok, scores} <- score_questions(questions, source, candidate) do
      average = if scores == [], do: 0.0, else: Enum.sum(scores) / length(scores)
      {:ok, average}
    end
  end

  defp normalize_label(label) do
    case String.downcase(label) do
      "entailment" -> :entailment
      "contradiction" -> :contradiction
      _ -> :neutral
    end
  end

  defp generate_questions(source) do
    case Servings.run(:question_gen, "generate question: " <> source) do
      {:ok, %{results: [%{text: text} | _]}} -> {:ok, split_questions(text)}
      {:ok, other} -> {:error, {:unexpected_response, other}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp split_questions(text) do
    text
    |> String.split(~r/[?]+/, trim: true)
    |> Enum.map(&(String.trim(&1) <> "?"))
  end

  defp score_questions(questions, source, candidate) do
    Enum.reduce_while(questions, {:ok, []}, fn question, {:ok, acc} ->
      with {:ok, source_answer} <- extract_answer(question, source),
           {:ok, candidate_answer} <- extract_answer(question, candidate) do
        {:cont, {:ok, [QAOverlap.f1(source_answer, candidate_answer) | acc]}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp extract_answer(question, context) do
    case Servings.run(:qa_extraction, %{question: question, context: context}) do
      {:ok, %{predictions: [%{text: text} | _]}} -> {:ok, text}
      {:ok, %{predictions: []}} -> {:ok, ""}
      {:ok, other} -> {:error, {:unexpected_response, other}}
      {:error, reason} -> {:error, reason}
    end
  end
end
