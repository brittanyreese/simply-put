defmodule SimplyPut.Readability do
  @moduledoc """
  Flesch-Kincaid grade level, in-repo and pure so a reviewer can independently
  verify the gate instead of trusting a dependency.

      FK grade = 0.39 * (words / sentences) + 11.8 * (syllables / words) - 15.59
  """

  @doc """
  Returns the Flesch-Kincaid grade level for `text` as a float.

  Empty input returns `0.0`. Text with no terminal punctuation is treated as
  one sentence; a single word is treated as one sentence of one word.
  """
  @spec flesch_kincaid(String.t()) :: float()
  def flesch_kincaid(text) when is_binary(text) do
    words = words(text)
    word_count = length(words)

    if word_count == 0 do
      0.0
    else
      sentence_count = text |> sentences() |> length() |> max(1)
      syllable_count = Enum.reduce(words, 0, fn word, acc -> acc + syllables(word) end)

      0.39 * (word_count / sentence_count) + 11.8 * (syllable_count / word_count) - 15.59
    end
  end

  @doc """
  Self-check: hand-traceable example proving the formula above is wired
  correctly. "The cat sat on the mat. The dog ran fast." is 10 monosyllabic
  words across 2 sentences (5 words/sentence, 1.0 syllables/word), so
  `0.39 * 5 + 11.8 * 1.0 - 15.59` must equal `-1.84`.
  """
  @spec demo() :: :ok
  def demo do
    grade = flesch_kincaid("The cat sat on the mat. The dog ran fast.")
    true = abs(grade - -1.84) < 0.01
    :ok
  end

  @doc """
  Natural-language critique for the next rewrite attempt: concrete FK-derived
  problems plus a standing anti-gaming clause, not just the numeric grade.

  Grounding (docs/plans/public-demo-repo/research/methodology-grounding-brief.md):
  iterative-refinement literature (Reflexion, Self-Refine) finds actionable
  natural-language feedback outperforms a bare scalar for steering the next
  attempt. The anti-gaming clause guards against retrying purely against the
  FK score, a documented failure mode (Tanprasert & Kauchak, 2021) since FK
  rewards shortcuts (dropped content, undefined abbreviations) that lower the
  number without preserving meaning.
  """
  @spec critique(String.t(), float()) :: String.t()
  def critique(text, target_grade) do
    grade = flesch_kincaid(text)
    {longest, longest_count} = longest_sentence(text)
    hardest = hardest_words(text, 3)

    sentence_note =
      if longest_count > 20 do
        "Longest sentence has #{longest_count} words (\"#{truncate(longest)}\") -- split it."
      else
        "Sentence length looks fine."
      end

    word_note =
      if hardest == [] do
        "No standout hard words."
      else
        "Hardest words: #{Enum.join(hardest, ", ")} -- use shorter synonyms."
      end

    "Grade #{Float.round(grade, 1)}, target #{target_grade}. #{sentence_note} #{word_note} " <>
      "Preserve meaning: do not drop content, do not remove definitions of " <>
      "technical terms, do not replace words with undefined abbreviations " <>
      "just to shorten them."
  end

  defp longest_sentence(text) do
    text
    |> sentences()
    |> Enum.map(fn s -> {String.trim(s), length(words(s))} end)
    |> Enum.max_by(fn {_s, count} -> count end, fn -> {"", 0} end)
  end

  defp hardest_words(text, n) do
    text
    |> words()
    |> Enum.uniq_by(&String.downcase/1)
    |> Enum.map(fn w -> {w, syllables(w)} end)
    |> Enum.filter(fn {_w, syl} -> syl >= 3 end)
    |> Enum.sort_by(fn {_w, syl} -> -syl end)
    |> Enum.take(n)
    |> Enum.map(fn {w, _syl} -> w end)
  end

  defp truncate(s, max \\ 60) do
    if String.length(s) > max, do: String.slice(s, 0, max) <> "...", else: s
  end

  defp words(text) do
    String.split(text, ~r/[^\p{L}'-]+/u, trim: true)
  end

  defp sentences(text) do
    String.split(text, ~r/[.!?]+/, trim: true)
  end

  defp syllables(word) do
    downcased = String.downcase(word)
    groups = ~r/[aeiouy]+/ |> Regex.scan(downcased) |> length()

    groups = if String.ends_with?(downcased, "e") and groups > 1, do: groups - 1, else: groups

    max(groups, 1)
  end
end
