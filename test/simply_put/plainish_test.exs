defmodule SimplyPut.LLM.FailingStub do
  @moduledoc false
  @behaviour SimplyPut.LLM

  @impl true
  def rewrite(_text, _opts), do: {:error, :boom}

  @impl true
  def judge(_original, _rewrite), do: {:error, :boom}
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
end
