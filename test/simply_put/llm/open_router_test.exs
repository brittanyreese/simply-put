defmodule SimplyPut.LLM.OpenRouterTest do
  # async: false -- mutates global :simply_put OpenRouter config (VM-wide).
  use ExUnit.Case, async: false

  alias SimplyPut.LLM.OpenRouter

  @moduletag :live

  setup do
    api_key = System.fetch_env!("OPENROUTER_API_KEY")

    Application.put_env(:simply_put, OpenRouter,
      api_key: api_key,
      rewrite_model: System.get_env("OPENROUTER_REWRITE_MODEL", "openai/gpt-4o-mini"),
      judge_model: System.get_env("OPENROUTER_JUDGE_MODEL", "anthropic/claude-haiku-4.5")
    )

    :ok
  end

  test "rewrite/2 simplifies text via a real OpenRouter call" do
    text =
      "The multifaceted implementation necessitates comprehensive stakeholder " <>
        "deliberation prior to deployment."

    assert {:ok, rewritten} =
             OpenRouter.rewrite(text, target_grade: 6.0, attempt: 1, critique: nil)

    assert is_binary(rewritten)
    assert rewritten != ""
  end

  test "score/2 returns a validated multi-axis JudgeScore" do
    original = "The cat sat on the mat."
    rewrite = "The cat sat on the mat."

    assert {:ok, %SimplyPut.JudgeScore{simplicity: s, fidelity: f, fluency: fl}} =
             OpenRouter.score(original, rewrite)

    assert s in 1..5
    assert f in 1..5
    assert fl in 1..5
  end
end
