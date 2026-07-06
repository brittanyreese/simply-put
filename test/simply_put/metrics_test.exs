defmodule SimplyPut.MetricsTest do
  use ExUnit.Case, async: true

  alias SimplyPut.Metrics

  describe "sari_at_order/4 (hand-verified, single n-gram order)" do
    test "candidate exactly matching the reference scores 1.0" do
      source = "big dog runs fast"
      reference = "big dog runs quickly"
      candidate = "big dog runs quickly"

      assert Metrics.sari_at_order(candidate, source, reference, 1) == 1.0
    end

    test "candidate with a wrong substitution scores 2/3 (add fails, keep and delete succeed)" do
      source = "big dog runs fast"
      reference = "big dog runs quickly"
      candidate = "big dog runs slowly"

      score = Metrics.sari_at_order(candidate, source, reference, 1)
      assert_in_delta score, 2 / 3, 0.0001
    end

    test "candidate identical to source (no simplification attempted) scores lower than a correct rewrite" do
      source = "big dog runs fast"
      reference = "big dog runs quickly"

      no_op_score = Metrics.sari_at_order(source, source, reference, 1)
      correct_score = Metrics.sari_at_order(reference, source, reference, 1)

      assert correct_score > no_op_score
    end
  end

  describe "sari/3 (averaged across n-gram orders 1-4)" do
    test "identical source, reference, and candidate scores 1.0" do
      text = "The cat sat on the mat"
      assert Metrics.sari(text, text, text) == 1.0
    end

    test "candidate exactly matching the reference scores 1.0" do
      source = "The multifaceted organization facilitated understanding among many people"
      reference = "The big group helped people understand"
      candidate = "The big group helped people understand"

      assert Metrics.sari(candidate, source, reference) == 1.0
    end

    test "a candidate closer to the reference scores higher than one further away" do
      source = "The multifaceted organization facilitated understanding among many people"
      reference = "The big group helped people understand"
      close_candidate = "The big group helped many people understand"
      far_candidate = "Xylophone quantum bicycle underneath the moon"

      close_score = Metrics.sari(close_candidate, source, reference)
      far_score = Metrics.sari(far_candidate, source, reference)

      assert close_score > far_score
    end

    test "returns a float in 0..1" do
      score =
        Metrics.sari(
          "A simple sentence.",
          "An elaborate and complicated sentence structure.",
          "A simple sentence."
        )

      assert score >= 0.0
      assert score <= 1.0
    end
  end

  describe "grade_band_compliance/2" do
    test "text within the band is compliant" do
      assert Metrics.grade_band_compliance("The cat sat on the mat.", {-5.0, 8.0})
    end

    test "text above the band is not compliant" do
      hard =
        "The multifaceted organization facilitated an extraordinarily convoluted understanding."

      refute Metrics.grade_band_compliance(hard, {0.0, 2.0})
    end

    test "text below the band is not compliant" do
      refute Metrics.grade_band_compliance("The cat sat on the mat.", {10.0, 12.0})
    end
  end
end
