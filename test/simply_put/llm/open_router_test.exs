defmodule SimplyPut.LLM.OpenRouterTest do
  use ExUnit.Case, async: true

  alias SimplyPut.LLM.OpenRouter

  @moduletag :live

  setup do
    api_key = System.fetch_env!("OPENROUTER_API_KEY")

    Application.put_env(:simply_put, OpenRouter,
      api_key: api_key,
      rewrite_model: System.get_env("OPENROUTER_REWRITE_MODEL", "openai/gpt-4o-mini"),
      judge_model: System.get_env("OPENROUTER_JUDGE_MODEL", "anthropic/claude-3-5-haiku")
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

  test "judge/2 returns a preserved/lost verdict with a rationale" do
    original = "The cat sat on the mat."
    rewrite = "The cat sat on the mat."

    assert {:ok, %{verdict: verdict, rationale: rationale}} =
             OpenRouter.judge(original, rewrite)

    assert verdict in [:preserved, :lost]
    assert is_binary(rationale)
  end
end
