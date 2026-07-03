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
