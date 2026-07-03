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
