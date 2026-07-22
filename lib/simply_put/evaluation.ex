defmodule SimplyPut.Evaluation do
  @moduledoc """
  Given a `Plainish.Result` and the `CorpusItem` it came from, builds and
  persists one `rewrite_evaluations` row with every axis: native metrics
  (FK, SMOG, SARI, grade-band), judge scores (simplicity/fidelity/fluency),
  and faithfulness (SummaC + QAFactEval via `SimplyPut.MetricProvider`).
  Called from `RewriteWorker` after `Plainish.run/2`.

  Reference-dependent metrics (SARI, BERTScore) are omitted when
  `corpus_item.reference_text` is `nil` (Clear Corpus items have none, only
  Med-EASi does).

  `faithfulness_score` combines SummaC's entailment probability and
  QAFactEval's answer-overlap score (simple mean of the two, each already
  0..1) since the schema has a single faithfulness column -- the
  literature (see `docs/research/2026-07-04-bumblebee-vs-python-sidecar-metrics.md`)
  treats these as complementary rather than redundant, so combining them is
  more informative than picking one. Both run the entailment source ->
  candidate, so this axis catches unsupported *additions* (hallucination),
  not omissions: a rewrite that drops a fact stays entailed by its source.

  `omission_score` is the reverse direction (candidate -> source): high
  means the rewrite still supports the source, low means it dropped
  content. A dropped contraindication leaves candidate -> source
  unentailed, so this is the axis that surfaces omission -- a separate and
  non-symmetric failure mode from addition.
  """

  alias SimplyPut.MetricProvider
  alias SimplyPut.MetricProvider.Bumblebee.Servings
  alias SimplyPut.Metrics
  alias SimplyPut.Readability
  alias SimplyPut.Repo
  alias SimplyPut.RewriteEvaluation

  @spec record(SimplyPut.CorpusItem.t(), SimplyPut.Plainish.Result.t(), String.t()) ::
          {:ok, RewriteEvaluation.t()} | {:error, Ecto.Changeset.t()}
  def record(item, result, batch_id) do
    attrs =
      %{
        corpus_item_id: item.id,
        batch_id: batch_id,
        run_mode: result.run_mode,
        fk_before_bp: to_bp(result.fk_before),
        fk_after_bp: to_bp(result.fk_after),
        smog_bp: to_bp(Readability.smog(result.text_out)),
        target_bp: to_bp(result.target),
        structural_gate_passed: result.gate_passed || false,
        attempts: result.attempts,
        text_out: result.text_out,
        generator_model: generator_model(),
        judge_model: judge_model()
      }
      |> Map.merge(reference_metrics(item, result))
      |> Map.merge(judge_metrics(result))
      |> Map.merge(faithfulness_metrics(item, result))
      |> reject_nils()

    %RewriteEvaluation{}
    |> RewriteEvaluation.changeset(attrs)
    |> Repo.insert()
  end

  defp reference_metrics(%{reference_text: nil}, _result), do: %{}

  defp reference_metrics(%{reference_text: reference, source_text: source}, result) do
    sari = Metrics.sari(result.text_out, source, reference)

    bertscore =
      case MetricProvider.bertscore(result.text_out, reference) do
        {:ok, %{f1: f1}} -> f1
        {:error, _reason} -> nil
      end

    %{sari_bp: to_bp(sari), bertscore_f1_bp: to_bp(bertscore)}
  end

  defp judge_metrics(%{judge_score: nil}), do: %{}

  defp judge_metrics(%{judge_score: %{simplicity: s, fidelity: f, fluency: fl}}) do
    %{simplicity: s, fidelity: f, fluency: fl}
  end

  defp faithfulness_metrics(item, result) do
    sle = fetch(MetricProvider.sle(result.text_out))
    addition_entail = entail_scalar(item.source_text, result.text_out)
    qafacteval_score = fetch(MetricProvider.qafacteval(item.source_text, result.text_out))
    omission_entail = entail_scalar(result.text_out, item.source_text)

    %{
      sle_bp: to_bp(sle),
      faithfulness_score: combined_faithfulness(addition_entail, qafacteval_score),
      faithfulness_provider: faithfulness_provider(),
      omission_score: omission_entail
    }
  end

  # Recorded per row so a batch's provenance survives config changes: a
  # Stub-scored row must never claim it was measured by the real models.
  # The non-stub value carries the pinned checkpoint ids, not just the
  # metric names, so a row is a real reproducibility record.
  defp faithfulness_provider do
    if MetricProvider.simulated?() do
      "stub"
    else
      "summac:#{Servings.checkpoint_id(:summac)}+qafacteval:#{Servings.checkpoint_id(:qa_extraction)}"
    end
  end

  # NLI entailment probability that `hypothesis` follows from `premise`, folded
  # to a 0..1 scalar. Direction is the whole point:
  #   entail_scalar(source, candidate) -> did the rewrite ADD unsupported claims?
  #   entail_scalar(candidate, source) -> did the rewrite OMIT source content?
  defp entail_scalar(premise, hypothesis) do
    case MetricProvider.entail(premise, hypothesis) do
      {:ok, %{label: :entailment, score: score}} -> score
      {:ok, %{label: :contradiction, score: score}} -> 1.0 - score
      {:ok, %{label: :neutral}} -> 0.5
      {:error, _reason} -> nil
    end
  end

  defp fetch({:ok, value}), do: value
  defp fetch({:error, _reason}), do: nil

  defp combined_faithfulness(nil, nil), do: nil
  defp combined_faithfulness(a, nil), do: a
  defp combined_faithfulness(nil, b), do: b
  defp combined_faithfulness(a, b), do: (a + b) / 2

  defp generator_model do
    case SimplyPut.LLM.current_adapter() do
      SimplyPut.LLM.OpenRouter -> config_value(SimplyPut.LLM.OpenRouter, :rewrite_model)
      _ -> "stub"
    end
  end

  defp judge_model do
    case SimplyPut.LLM.current_adapter() do
      SimplyPut.LLM.OpenRouter -> config_value(SimplyPut.LLM.OpenRouter, :judge_model)
      _ -> "stub"
    end
  end

  defp config_value(module, key),
    do: :simply_put |> Application.fetch_env!(module) |> Keyword.fetch!(key)

  defp to_bp(nil), do: nil
  defp to_bp(number), do: round(number * 100)

  defp reject_nils(map), do: Map.reject(map, fn {_k, v} -> is_nil(v) end)
end
