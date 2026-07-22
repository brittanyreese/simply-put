defmodule SimplyPut.LLM.FailingStub do
  @moduledoc false
  @behaviour SimplyPut.LLM

  @impl true
  def rewrite(_text, _opts), do: {:error, :boom}

  @impl true
  def judge(_original, _rewrite), do: {:error, :boom}

  @impl true
  def score(_original, _rewrite), do: {:error, :boom}
end

defmodule SimplyPut.LLM.CapturingStub do
  @moduledoc false
  @behaviour SimplyPut.LLM

  alias SimplyPut.LLM.Stub

  @impl true
  def rewrite(text, opts) do
    send(self(), {:rewrite_opts, opts})
    Stub.rewrite(text, opts)
  end

  @impl true
  def judge(original, rewrite), do: Stub.judge(original, rewrite)

  @impl true
  def score(original, rewrite) do
    send(self(), :score_called)
    Stub.score(original, rewrite)
  end
end

defmodule SimplyPut.LLM.BoundaryScoreStub do
  @moduledoc false
  @behaviour SimplyPut.LLM

  alias SimplyPut.JudgeScore
  alias SimplyPut.LLM.Stub

  # Judge axes are read from the app env so one stub covers both boundary
  # cases (all-3 clears, a 2 on any axis does not).
  @impl true
  def rewrite(text, opts), do: Stub.rewrite(text, opts)

  @impl true
  def judge(original, rewrite), do: Stub.judge(original, rewrite)

  @impl true
  def score(_original, _rewrite) do
    Application.get_env(:simply_put, :boundary_axes, %{simplicity: 3, fidelity: 3, fluency: 3})
    |> JudgeScore.parse()
  end
end

defmodule SimplyPut.PlainishTest do
  use ExUnit.Case, async: true

  alias SimplyPut.Plainish
  alias SimplyPut.Plainish.Result

  @complex_fixture "Individuals utilize numerous significant facilitate additionally " <>
                     "demonstrate subsequently commence endeavor terminate comprehend " <>
                     "approximately sufficient methods."

  test "rewrites a complex fixture below grade 6, green on clone with no API key" do
    assert {:ok, %Result{status: :passed} = result} = Plainish.run(@complex_fixture)
    assert result.fk_after <= 6.0
    assert result.fk_before > result.fk_after
    assert result.attempts >= 1
    assert result.verdict == nil
  end

  test "judge OFF (default) leaves the result byte-identical to the pre-judge path" do
    refute Application.get_env(:simply_put, :deps, [])[:judge]

    assert {:ok, %Result{verdict: nil}} = Plainish.run(@complex_fixture)
    assert {:hold, %Result{verdict: nil}} = Plainish.run("Extraordinarily discombobulated.")
  end

  test "judge ON attaches a dual verdict via the stub judge" do
    Application.put_env(:simply_put, :deps, judge: true)
    on_exit(fn -> Application.delete_env(:simply_put, :deps) end)

    assert {:ok, %Result{verdict: %{fk_pass: true, meaning_preserved: true}}} =
             Plainish.run(@complex_fixture)
  end

  test "holds when the rewrite can't reach target within max_attempts" do
    unreachable = "Extraordinarily discombobulated hippopotamuses perambulate philosophically."

    assert {:hold, %Result{status: :held} = result} =
             Plainish.run(unreachable, max_attempts: 3)

    assert result.attempts == 3
    assert result.fk_after > 6.0
  end

  test "propagates adapter errors explicitly, never a bare match" do
    Application.put_env(:simply_put, :llm, SimplyPut.LLM.FailingStub)
    on_exit(fn -> Application.delete_env(:simply_put, :llm) end)

    assert {:error, :boom} = Plainish.run("some text")
  end

  test "feeds a natural-language critique, not just the numeric grade, to the adapter" do
    Application.put_env(:simply_put, :llm, SimplyPut.LLM.CapturingStub)
    on_exit(fn -> Application.delete_env(:simply_put, :llm) end)

    Plainish.run(@complex_fixture)

    assert_received {:rewrite_opts, opts}
    critique = Keyword.fetch!(opts, :critique)
    assert critique =~ "Grade"
    assert critique =~ "Preserve meaning"
  end

  describe "run_mode :iterative (default)" do
    test "gates each attempt on the structural gate before ever calling the judge" do
      Application.put_env(:simply_put, :llm, SimplyPut.LLM.CapturingStub)
      on_exit(fn -> Application.delete_env(:simply_put, :llm) end)

      assert {:ok, %Result{status: :passed, gate_passed: true, judge_score: score}} =
               Plainish.run(@complex_fixture)

      assert %SimplyPut.JudgeScore{} = score
      assert_received :score_called
    end

    test "gate hard-reject forces a retry, eventually passing once sentences are short enough" do
      words =
        ~w(happy little garden helpful morning gentle quiet lovely evening yellow simple pretty friendly careful joyful)

      text = (words |> Enum.take(24) |> Enum.join(" ")) <> "."

      assert {:ok, %Result{status: :passed, attempts: attempts, gate_passed: true}} =
               Plainish.run(text, target_grade: 7.0)

      assert attempts > 1
    end
  end

  describe "run_mode :single_shot" do
    test "makes exactly one attempt regardless of max_attempts, even when it fails" do
      unreachable = "Extraordinarily discombobulated hippopotamuses perambulate philosophically."

      assert {:hold, %Result{status: :held, attempts: 1, run_mode: :single_shot}} =
               Plainish.run(unreachable, max_attempts: 3, run_mode: :single_shot)
    end

    test "can pass on the first and only attempt" do
      assert {:ok, %Result{status: :passed, attempts: 1, run_mode: :single_shot}} =
               Plainish.run(@complex_fixture, run_mode: :single_shot)
    end
  end

  describe "run_mode :self_refine" do
    test "never calls the external judge" do
      Application.put_env(:simply_put, :llm, SimplyPut.LLM.CapturingStub)
      on_exit(fn -> Application.delete_env(:simply_put, :llm) end)

      assert {:ok, %Result{status: :passed, judge_score: nil, run_mode: :self_refine}} =
               Plainish.run(@complex_fixture, run_mode: :self_refine)

      refute_received :score_called
    end

    test "still retries against the deterministic gate and can hold" do
      unreachable = "Extraordinarily discombobulated hippopotamuses perambulate philosophically."

      assert {:hold, %Result{status: :held, judge_score: nil, run_mode: :self_refine}} =
               Plainish.run(unreachable, max_attempts: 3, run_mode: :self_refine)
    end
  end

  # The judge-pass threshold is `>= 3` on every axis. Only stub fixtures
  # returning 4/5 exercise it elsewhere, so an off-by-one (flipping `>=` to
  # `>`, or moving the threshold) would slip through. Pin the exact boundary.
  describe "judge-pass threshold boundary" do
    setup do
      Application.put_env(:simply_put, :llm, SimplyPut.LLM.BoundaryScoreStub)

      on_exit(fn ->
        Application.delete_env(:simply_put, :llm)
        Application.delete_env(:simply_put, :boundary_axes)
      end)
    end

    test "a score of exactly 3 on every axis clears (status :passed)" do
      Application.put_env(:simply_put, :boundary_axes, %{simplicity: 3, fidelity: 3, fluency: 3})

      assert {:ok, %Result{status: :passed}} = Plainish.run(@complex_fixture)
    end

    test "a score of 2 on any one axis does not clear (status :held)" do
      Application.put_env(:simply_put, :boundary_axes, %{simplicity: 2, fidelity: 3, fluency: 3})

      assert {:hold, %Result{status: :held}} = Plainish.run(@complex_fixture)
    end
  end
end
