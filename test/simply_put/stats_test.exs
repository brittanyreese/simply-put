defmodule SimplyPut.StatsTest do
  use ExUnit.Case, async: true

  alias SimplyPut.Stats

  test "demo/0 self-check passes" do
    assert Stats.demo() == :ok
  end

  describe "cohens_kappa/2" do
    test "matches a hand-worked confusion matrix (kappa = 5/7)" do
      # 10 items. a: 5x rating 1, 5x rating 2. b: 4x1, 1x2 (paired with a's
      # first five 1s), 4x2, 1x3 (paired with a's five 2s). Full worked
      # arithmetic (weighted observed/expected, quadratic weights, span=4)
      # is in the plan's Phase G notes; expected kappa = 1 - 0.125/0.4375
      # = 5/7.
      rater_a = [1, 1, 1, 1, 1, 2, 2, 2, 2, 2]
      rater_b = [1, 1, 1, 1, 2, 2, 2, 2, 2, 3]

      kappa = Stats.cohens_kappa(rater_a, rater_b)
      assert_in_delta kappa, 5 / 7, 0.0001
    end

    test "identical raters score kappa 1.0" do
      raters = [1, 2, 3, 4, 5, 1, 2, 3, 4, 5]
      assert_in_delta Stats.cohens_kappa(raters, raters), 1.0, 0.0001
    end

    test "a 1-vs-5 disagreement penalizes more than a 3-vs-4 disagreement" do
      # A constant rater always yields kappa 0 regardless of the other
      # side's disagreement structure (a known property: kappa needs
      # variance in both marginals), so `base` needs its own spread for
      # this comparison to be meaningful.
      base = [1, 2, 3, 4, 5, 1, 2, 3, 4, 5]
      near_miss = [1, 2, 3, 4, 5, 1, 2, 3, 4, 4]
      far_miss = [1, 2, 3, 4, 5, 1, 2, 3, 4, 1]

      near_kappa = Stats.cohens_kappa(base, near_miss)
      far_kappa = Stats.cohens_kappa(base, far_miss)

      assert near_kappa > far_kappa
    end

    test "a constant rater yields kappa 0 regardless of the other rater's spread" do
      constant = [3, 3, 3, 3, 3, 3, 3, 3, 3, 3]
      varied = [1, 2, 3, 4, 5, 1, 2, 3, 4, 5]

      assert Stats.cohens_kappa(constant, varied) == 0.0
    end
  end

  describe "bootstrap_ci/3" do
    test "a constant dataset brackets its own mean exactly" do
      values = List.duplicate(10.0, 30)

      assert {lower, upper} = Stats.bootstrap_ci(values, 500, 0.95)
      assert_in_delta lower, 10.0, 0.0001
      assert_in_delta upper, 10.0, 0.0001
    end

    test "brackets the true mean of a known dataset" do
      values = Enum.map(1..100, &(&1 * 1.0))
      true_mean = 50.5

      assert {lower, upper} = Stats.bootstrap_ci(values, 1000, 0.95)
      assert lower <= true_mean
      assert upper >= true_mean
    end

    test "lower bound never exceeds the upper bound" do
      values = [1.0, 5.0, 10.0, 2.0, 8.0, 3.0, 9.0]

      assert {lower, upper} = Stats.bootstrap_ci(values, 200, 0.90)
      assert lower <= upper
    end
  end
end
