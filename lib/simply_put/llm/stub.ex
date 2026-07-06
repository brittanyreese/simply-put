defmodule SimplyPut.LLM.Stub do
  @moduledoc """
  Deterministic rewrite, no network. Swaps common long words for short
  synonyms and splits sentences into shorter clauses, tightening the clause
  cap on each retry -- a real (if crude) transform, so it exercises the
  actual FK gate and retry loop rather than a canned fixture match.
  """

  @behaviour SimplyPut.LLM

  @synonyms %{
    "individuals" => "folks",
    "utilize" => "use",
    "utilizes" => "uses",
    "numerous" => "lots",
    "significant" => "big",
    "facilitate" => "help",
    "additionally" => "plus",
    "demonstrate" => "show",
    "demonstrates" => "shows",
    "subsequently" => "then",
    "commence" => "start",
    "endeavor" => "try",
    "terminate" => "end",
    "comprehend" => "grasp",
    "approximately" => "near",
    "sufficient" => "fine"
  }

  @impl true
  def rewrite(text, opts) do
    attempt = Keyword.get(opts, :attempt, 1)
    max_words = max(10 - 2 * attempt, 3)

    rewritten =
      text
      |> swap_words()
      |> shorten_sentences(max_words)

    {:ok, rewritten}
  end

  # ponytail: fixed verdict, no semantic comparison -- real judge lands in
  # OpenRouter adapter (3.1); the stub just exercises the deps[:judge] seam.
  @impl true
  def judge(_original, _rewrite) do
    {:ok, %{verdict: :preserved, rationale: "stub: no semantic check performed"}}
  end

  @impl true
  def score(_original, _rewrite) do
    SimplyPut.JudgeScore.parse(%{
      simplicity: 4,
      fidelity: 5,
      fluency: 4,
      notes: "stub: no semantic check performed"
    })
  end

  defp swap_words(text) do
    Regex.replace(~r/\b\p{L}+\b/u, text, fn word ->
      Map.get(@synonyms, String.downcase(word), word)
    end)
  end

  defp shorten_sentences(text, max_words) do
    text
    |> String.split(~r/(?<=[.!?])\s+/, trim: true)
    |> Enum.flat_map(&split_long_sentence(&1, max_words))
    |> Enum.join(" ")
  end

  defp split_long_sentence(sentence, max_words) do
    clean = Regex.replace(~r/[.!?]+\s*$/, sentence, "")

    clean
    |> String.split(~r/\s+/, trim: true)
    |> Enum.chunk_every(max_words)
    |> Enum.map(fn chunk -> Enum.join(chunk, " ") <> "." end)
  end
end
