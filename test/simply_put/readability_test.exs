defmodule SimplyPut.ReadabilityTest do
  use ExUnit.Case, async: true

  alias SimplyPut.Readability

  test "demo/0 self-check passes" do
    assert Readability.demo() == :ok
  end

  test "known text lands on its hand-computed grade" do
    # 10 monosyllabic words, 2 sentences -> 5 words/sentence, 1.0 syllables/word
    # 0.39 * 5 + 11.8 * 1.0 - 15.59 = -1.84
    grade = Readability.flesch_kincaid("The cat sat on the mat. The dog ran fast.")
    assert_in_delta grade, -1.84, 0.01
  end

  test "harder text scores a higher grade than simple text" do
    simple = Readability.flesch_kincaid("The cat sat on the mat.")

    complex =
      Readability.flesch_kincaid(
        "The Australian platypus is seemingly a hybrid of a mammal and reptilian creature."
      )

    assert complex > simple
  end

  test "empty string returns 0.0" do
    assert Readability.flesch_kincaid("") == 0.0
  end

  test "single word with no terminal punctuation does not raise" do
    grade = Readability.flesch_kincaid("Hello")
    assert is_float(grade)
  end

  test "text with no terminal punctuation is treated as one sentence" do
    grade = Readability.flesch_kincaid("this is a test with no punctuation at all")
    assert is_float(grade)
  end

  describe "tokenization" do
    test "a decimal does not split a sentence" do
      # "3.5" must not be read as two sentences; the period is not followed by
      # whitespace, so the whole thing is one sentence.
      assert length(Readability.sentence_lengths("The dose is 3.5 mg per day.")) == 1
    end

    test "numeric tokens count as words" do
      # "50" is a word under the standard FK/SMOG definition: I/have/50/cats.
      assert Readability.sentence_lengths("I have 50 cats.") == [4]
    end

    test "a lone hyphen between spaces is not counted as a word" do
      assert Readability.sentence_lengths("a - b.") == [2]
    end
  end

  describe "syllables/1" do
    test "counts vowel groups, dropping a silent trailing e" do
      assert Readability.syllables("cat") == 1
      assert Readability.syllables("cake") == 1
      assert Readability.syllables("banana") == 3
    end
  end

  describe "smog/1" do
    test "known text lands on its hand-computed grade" do
      # 2 sentences, 1 polysyllable word ("multifaceted", 4 syllables >= 3):
      # 1.0430 * sqrt(1 * (30 / 2)) + 3.1291 = 1.0430 * sqrt(15) + 3.1291
      text = "The multifaceted plan worked. The cat sat."
      grade = Readability.smog(text)
      expected = 1.0430 * :math.sqrt(1 * (30 / 2)) + 3.1291
      assert_in_delta grade, expected, 0.01
    end

    test "empty string returns 0.0" do
      assert Readability.smog("") == 0.0
    end

    test "fewer than 30 sentences still returns a grade (small-sample estimate)" do
      grade = Readability.smog("One short sentence.")
      assert is_float(grade)
    end
  end

  describe "sentence_lengths/1" do
    test "returns word count per sentence in order" do
      assert Readability.sentence_lengths("The cat sat. A longer sentence has five words.") == [
               3,
               6
             ]
    end
  end

  describe "structural_gate/2" do
    test "passes simple, on-target text" do
      assert Readability.structural_gate("The cat sat on the mat.", 6.0) == {:ok, []}
    end

    test "rejects text whose FK grade exceeds the target band" do
      hard =
        "The multifaceted organization facilitated an extraordinarily convoluted understanding."

      assert {:reject, reasons} = Readability.structural_gate(hard, 2.0)
      assert Enum.any?(reasons, &(&1 =~ "exceeds target band"))
    end

    test "rejects a long sentence regardless of grade band" do
      long = String.duplicate("word ", 25) <> "."
      assert {:reject, reasons} = Readability.structural_gate(long, 20.0)
      assert Enum.any?(reasons, &(&1 =~ "exceed 20 words"))
    end
  end

  describe "critique/2" do
    test "always includes the anti-gaming clause" do
      critique = Readability.critique("The cat sat on the mat.", 6.0)
      assert critique =~ "Preserve meaning"
      assert critique =~ "do not drop content"
    end

    test "flags a long sentence for splitting" do
      long = String.duplicate("word ", 25) <> "."
      critique = Readability.critique(long, 6.0)
      assert critique =~ "split it"
    end

    test "flags hard words by syllable count" do
      critique =
        Readability.critique("The multifaceted organization facilitated understanding.", 6.0)

      assert critique =~ "Hardest words"
    end

    test "reports no issues for short, simple text" do
      critique = Readability.critique("The cat sat on the mat.", 6.0)
      assert critique =~ "Sentence length looks fine"
      assert critique =~ "No standout hard words"
    end
  end
end
