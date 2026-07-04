defmodule SimplyPut.LLM.OpenRouter do
  @moduledoc """
  Real adapter over OpenRouter's OpenAI-compatible chat completions API.
  Selected only when `OPENROUTER_API_KEY` is set (see `config/runtime.exs`) --
  the absent-key path stays on `SimplyPut.LLM.Stub`, so a fresh clone never
  needs a key.

  Rewrite and judge default to different model vendors on purpose: a judge
  from the rewriter's own vendor family inflates "meaning preserved"
  verdicts (self-preference bias, Wataoka et al. 2024 -- see plan
  scratchpad, deferred from the methodology-grounding pass).
  """

  @behaviour SimplyPut.LLM

  @endpoint ~c"https://openrouter.ai/api/v1/chat/completions"

  @impl true
  def rewrite(text, opts) do
    target = Keyword.fetch!(opts, :target_grade)
    critique = Keyword.get(opts, :critique)

    prompt = """
    Rewrite the following text so it scores at or below a Flesch-Kincaid \
    grade level of #{target}. Keep every fact, number, and defined term -- \
    simplify language and sentence structure, do not shorten by deleting \
    content. Return only the rewritten text, no preamble.
    #{if critique, do: "\nCritique of the last attempt:\n#{critique}\n"}
    Text:
    #{text}
    """

    request(config(:rewrite_model), prompt)
  end

  @impl true
  def judge(original, rewrite) do
    prompt = """
    Compare the ORIGINAL and REWRITE below. Reply with exactly one word on \
    the first line, "preserved" or "lost", then a one-sentence rationale on \
    the second line. "lost" means the rewrite dropped a fact, number, or \
    defined term present in the original.

    ORIGINAL:
    #{original}

    REWRITE:
    #{rewrite}
    """

    with {:ok, content} <- request(config(:judge_model), prompt) do
      {:ok, parse_verdict(content)}
    end
  end

  defp parse_verdict(content) do
    [first | rest] = content |> String.trim() |> String.split("\n", parts: 2)
    verdict = if String.downcase(String.trim(first)) == "preserved", do: :preserved, else: :lost
    rationale = rest |> List.first("") |> String.trim()
    %{verdict: verdict, rationale: rationale}
  end

  defp request(model, prompt) do
    body = Jason.encode!(%{model: model, messages: [%{role: "user", content: prompt}]})
    headers = [{~c"authorization", String.to_charlist("Bearer " <> config(:api_key))}]

    case :httpc.request(
           :post,
           {@endpoint, headers, ~c"application/json", body},
           http_options(),
           []
         ) do
      {:ok, {{_, 200, _}, _headers, resp_body}} ->
        extract_content(resp_body)

      {:ok, {{_, status, _}, _headers, resp_body}} ->
        {:error, {:http_error, status, IO.iodata_to_binary(resp_body)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # :httpc does not verify TLS certs unless told to -- without this, the
  # Bearer token above would go out over a connection that accepts any
  # certificate, which is exploitable by an active MITM.
  defp http_options do
    [
      ssl: [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
      ],
      timeout: 30_000
    ]
  end

  defp extract_content(resp_body) do
    case Jason.decode(IO.iodata_to_binary(resp_body)) do
      {:ok, %{"choices" => [%{"message" => %{"content" => content}} | _]}} -> {:ok, content}
      {:ok, decoded} -> {:error, {:unexpected_response, decoded}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp config(key), do: :simply_put |> Application.fetch_env!(__MODULE__) |> Keyword.fetch!(key)
end
