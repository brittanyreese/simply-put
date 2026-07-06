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
    # Keep digits in the word class: FK and SMOG count numbers as words, and
    # this corpus is number-heavy (doses, years). Drop tokens that are pure
    # punctuation (a lone "-" left between spaces is not a word).
    text
    |> String.split(~r/[^\p{L}\p{N}'-]+/u, trim: true)
    |> Enum.filter(&(&1 =~ ~r/[\p{L}\p{N}]/u))
  end

  defp sentences(text) do
    # Only break on a terminator followed by whitespace or end-of-string, so a
    # decimal ("3.5 mg") or "e.g." mid-token doesn't inflate the sentence count
    # and deflate the FK grade. Not a full abbreviation-aware splitter.
    String.split(text, ~r/[.!?]+(?=\s|$)/, trim: true)
  end

  @doc """
  Heuristic syllable count for a single word (vowel-group counting, no
  CMUdict). Exposed so SMOG and other callers can reuse the same heuristic
  `flesch_kincaid/1` uses internally.
  """
  @spec syllables(String.t()) :: pos_integer()
  def syllables(word) do
    downcased = String.downcase(word)
    groups = ~r/[aeiouy]+/ |> Regex.scan(downcased) |> length()

    groups = if String.ends_with?(downcased, "e") and groups > 1, do: groups - 1, else: groups

    max(groups, 1)
  end

  @doc """
  SMOG grade estimate.

      SMOG grade = 1.0430 * sqrt(polysyllable_count * (30 / sentence_count)) + 3.1291

  The published formula assumes a 30-sentence sample. Texts with fewer
  sentences use all available sentences instead; the result is a rougher
  estimate in that case, not a corrected small-sample formula.
  """
  @spec smog(String.t()) :: float()
  def smog(text) when is_binary(text) do
    sample = text |> sentences() |> Enum.take(30)
    sentence_count = length(sample)

    if sentence_count == 0 do
      0.0
    else
      polysyllable_count =
        sample
        |> Enum.flat_map(&words/1)
        |> Enum.count(&(syllables(&1) >= 3))

      1.0430 * :math.sqrt(polysyllable_count * (30 / sentence_count)) + 3.1291
    end
  end

  @doc """
  Word count per sentence, in order. Used by `structural_gate/2` to flag
  over-long sentences and available standalone for reporting.
  """
  @spec sentence_lengths(String.t()) :: [non_neg_integer()]
  def sentence_lengths(text) when is_binary(text) do
    text
    |> sentences()
    |> Enum.map(fn sentence -> sentence |> words() |> length() end)
  end

  @doc """
  Hard deterministic gate, run before any judge call. A pass here doesn't
  certify quality, it filters out candidates the judge should never have to
  spend a call on: rejects on grade-band miss (FK grade more than 2 above
  `target_grade`) or any sentence over 20 words.
  """
  @spec structural_gate(String.t(), number()) :: {:ok, []} | {:reject, [String.t()]}
  def structural_gate(text, target_grade) when is_binary(text) do
    reasons =
      []
      |> reject_grade_band(text, target_grade)
      |> reject_long_sentences(text)

    case reasons do
      [] -> {:ok, []}
      reasons -> {:reject, Enum.reverse(reasons)}
    end
  end

  defp reject_grade_band(reasons, text, target_grade) do
    grade = flesch_kincaid(text)
    max_grade = target_grade + 2.0

    if grade > max_grade do
      reason =
        "FK grade #{Float.round(grade, 1)} exceeds target band (target #{target_grade}, max #{max_grade})"

      [reason | reasons]
    else
      reasons
    end
  end

  defp reject_long_sentences(reasons, text) do
    case Enum.filter(sentence_lengths(text), &(&1 > 20)) do
      [] -> reasons
      long -> ["#{length(long)} sentence(s) exceed 20 words" | reasons]
    end
  end
end
