import Config

if api_key = System.get_env("OPENROUTER_API_KEY") do
  config :simply_put, :llm, SimplyPut.LLM.OpenRouter

  config :simply_put, SimplyPut.LLM.OpenRouter,
    api_key: api_key,
    rewrite_model: System.get_env("OPENROUTER_REWRITE_MODEL", "openai/gpt-4o-mini"),
    judge_model: System.get_env("OPENROUTER_JUDGE_MODEL", "anthropic/claude-haiku-4.5")
end

# Opt in to real model-based metrics. Left unset (the default), every
# metric resolves to SimplyPut.MetricProvider.Stub, so `mix test` never
# loads a checkpoint. Set METRIC_PROVIDER=bumblebee for a real eval run;
# the first call to each metric then downloads its pinned checkpoint.
if System.get_env("METRIC_PROVIDER") == "bumblebee" do
  config :simply_put, :metric_provider, SimplyPut.MetricProvider.Bumblebee
end
