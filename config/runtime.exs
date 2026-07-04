import Config

if api_key = System.get_env("OPENROUTER_API_KEY") do
  config :simply_put, :llm, SimplyPut.LLM.OpenRouter

  config :simply_put, SimplyPut.LLM.OpenRouter,
    api_key: api_key,
    rewrite_model: System.get_env("OPENROUTER_REWRITE_MODEL", "openai/gpt-4o-mini"),
    judge_model: System.get_env("OPENROUTER_JUDGE_MODEL", "anthropic/claude-haiku-4.5")
end
