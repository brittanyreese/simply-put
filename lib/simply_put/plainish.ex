defmodule SimplyPut.Plainish do
  @moduledoc """
  `run/2` is a `with`-chain, not a GenServer -- there is no runtime state to
  hold, so there is no process (no process without a runtime reason).
  """

  alias SimplyPut.LLM
  alias SimplyPut.Readability

  defmodule Result do
    @moduledoc "Outcome of a `Plainish.run/2` call."
    @enforce_keys [:status, :fk_before, :fk_after, :target, :attempts, :text_out]
    defstruct [:status, :fk_before, :fk_after, :target, :attempts, :text_out, :verdict]

    @type verdict :: %{fk_pass: boolean(), meaning_preserved: boolean()}

    @type t :: %__MODULE__{
            status: :passed | :held,
            fk_before: float(),
            fk_after: float(),
            target: float(),
            attempts: pos_integer(),
            text_out: String.t(),
            verdict: verdict() | nil
          }
  end

  @default_target_grade 6.0
  @default_max_attempts 3

  @doc """
  Score, rewrite, re-score, gate -- bounded retry loop on `flesch_kincaid/1`
  feedback. `:ok` on a passing rewrite, `:hold` when attempts are exhausted
  and the text still misses target (never a silent drop).

  When `deps[:judge]` is enabled (default off), a dual-verdict is attached
  to the result: FK-pass and meaning-preserved, from a judge adapter call
  comparing `text` against the final rewrite. With judge off, the result is
  byte-identical to the pre-judge (1.3) output -- no judge call is made.
  """
  @spec run(String.t(), keyword()) ::
          {:ok, Result.t()} | {:hold, Result.t()} | {:error, term()}
  def run(text, opts \\ []) do
    target = Keyword.get(opts, :target_grade, @default_target_grade)
    max_attempts = Keyword.get(opts, :max_attempts, @default_max_attempts)
    fk_before = Readability.flesch_kincaid(text)

    case attempt(text, fk_before, target, max_attempts, 1) do
      {:ok, result} -> {:ok, maybe_judge(result, text)}
      {:hold, result} -> {:hold, maybe_judge(result, text)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp attempt(current_text, fk_before, target, max_attempts, attempt_number) do
    critique = Readability.critique(current_text, target)

    case LLM.rewrite(current_text,
           target_grade: target,
           attempt: attempt_number,
           critique: critique
         ) do
      {:ok, rewritten} ->
        handle_rewrite(rewritten, fk_before, target, max_attempts, attempt_number)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_rewrite(rewritten, fk_before, target, max_attempts, attempt_number) do
    fk_after = Readability.flesch_kincaid(rewritten)

    cond do
      fk_after <= target ->
        {:ok, result(:passed, fk_before, fk_after, target, attempt_number, rewritten)}

      attempt_number >= max_attempts ->
        {:hold, result(:held, fk_before, fk_after, target, attempt_number, rewritten)}

      true ->
        attempt(rewritten, fk_before, target, max_attempts, attempt_number + 1)
    end
  end

  defp result(status, fk_before, fk_after, target, attempts, text_out) do
    %Result{
      status: status,
      fk_before: fk_before,
      fk_after: fk_after,
      target: target,
      attempts: attempts,
      text_out: text_out
    }
  end

  defp maybe_judge(result, original_text) do
    if judge_enabled?() do
      case LLM.judge(original_text, result.text_out) do
        {:ok, %{verdict: verdict}} ->
          %{
            result
            | verdict: %{
                fk_pass: result.status == :passed,
                meaning_preserved: verdict == :preserved
              }
          }

        {:error, _reason} ->
          result
      end
    else
      result
    end
  end

  defp judge_enabled? do
    :simply_put |> Application.get_env(:deps, []) |> Keyword.get(:judge, false)
  end
end
