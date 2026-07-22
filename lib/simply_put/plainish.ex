defmodule SimplyPut.Plainish do
  @moduledoc """
  `run/2` is a `with`-chain, not a GenServer -- there is no runtime state to
  hold, so there is no process (no process without a runtime reason).

  Three `run_mode`s share the same rewrite step but differ in what gates a
  retry:

    * `:iterative` (default) -- each attempt runs the deterministic
      `Readability.structural_gate/2` first (hard reject retries with
      reasons), then, only on a gate pass, the multi-axis judge
      (`LLM.score/2`). Passes only when both clear. This is the target
      system Phase 1 evaluates.
    * `:single_shot` -- one rewrite attempt, no retry regardless of outcome.
      Negative control: shows what a naive non-iterative baseline scores.
    * `:self_refine` -- retries against the structural gate only, the
      external judge is never called (`judge_score` stays `nil`). Negative
      control approximating "no external verifier". This mode
      doesn't add a separate self-critique LLM call (the literature's
      literal Self-Refine loop), since the comparison this project needs is
      "external judge helps vs. doesn't," not self-critique fidelity. Add a
      real self-critique call if that distinction ever matters.

  The judge only sees gate-passing candidates (gate runs first, cheaply,
  before any judge call) -- see the plan's Risks section on cost/latency.
  """

  require Logger

  alias SimplyPut.JudgeScore
  alias SimplyPut.LLM
  alias SimplyPut.Readability

  defmodule Result do
    @moduledoc "Outcome of a `Plainish.run/2` call."
    @enforce_keys [:status, :fk_before, :fk_after, :target, :attempts, :text_out, :run_mode]
    defstruct [
      :status,
      :fk_before,
      :fk_after,
      :target,
      :attempts,
      :text_out,
      :run_mode,
      :gate_passed,
      :judge_score,
      :verdict
    ]

    @type verdict :: %{fk_pass: boolean(), meaning_preserved: boolean()}

    @type t :: %__MODULE__{
            status: :passed | :held,
            fk_before: float(),
            fk_after: float(),
            target: float(),
            attempts: pos_integer(),
            text_out: String.t(),
            run_mode: SimplyPut.Plainish.run_mode(),
            gate_passed: boolean() | nil,
            judge_score: SimplyPut.JudgeScore.t() | nil,
            verdict: verdict() | nil
          }
  end

  @type run_mode :: :iterative | :single_shot | :self_refine

  @default_target_grade 6.0
  @default_max_attempts 3

  # Placeholder rubric threshold (1..5 scale): every axis must clear this to
  # pass in :iterative mode. Under-specified per the plan's own risk note --
  # resolve empirically against a dev sample rather than trusting this
  # number.
  @judge_threshold 3

  @doc """
  Score, rewrite, re-score, gate -- bounded retry loop. `:ok` on a passing
  rewrite, `:hold` when attempts are exhausted and the text still hasn't
  passed (never a silent drop).

  `opts[:run_mode]` selects one of the three modes documented above
  (default `:iterative`).

  Independently of `run_mode`, `opts[:deps][:judge]` (via
  `Application.get_env(:simply_put, :deps, [])`) still controls the legacy
  binary `verdict` field for backward compatibility with `RewriteWorker`
  and the `/runs` dashboard -- unrelated to the new gate/judge-in-loop
  restructure above, and untouched by it.
  """
  @spec run(String.t(), keyword()) ::
          {:ok, Result.t()} | {:hold, Result.t()} | {:error, term()}
  def run(text, opts \\ []) do
    target = Keyword.get(opts, :target_grade, @default_target_grade)
    max_attempts = Keyword.get(opts, :max_attempts, @default_max_attempts)
    run_mode = Keyword.get(opts, :run_mode, :iterative)
    fk_before = Readability.flesch_kincaid(text)

    case attempt(text, text, fk_before, target, max_attempts, 1, run_mode) do
      {:ok, result} -> {:ok, maybe_judge(result, text)}
      {:hold, result} -> {:hold, maybe_judge(result, text)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp attempt(
         original_text,
         current_text,
         fk_before,
         target,
         max_attempts,
         attempt_number,
         run_mode
       ) do
    critique = Readability.critique(current_text, target)

    case LLM.rewrite(current_text,
           target_grade: target,
           attempt: attempt_number,
           critique: critique
         ) do
      {:ok, rewritten} ->
        handle_rewrite(
          original_text,
          rewritten,
          fk_before,
          target,
          max_attempts,
          attempt_number,
          run_mode
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_rewrite(
         original_text,
         rewritten,
         fk_before,
         target,
         max_attempts,
         attempt_number,
         run_mode
       ) do
    grades = %{
      fk_before: fk_before,
      fk_after: Readability.flesch_kincaid(rewritten),
      target: target,
      attempts: attempt_number
    }

    gate_passed? = gate_passed?(Readability.structural_gate(rewritten, target))

    case run_mode do
      :single_shot ->
        single_shot_result(original_text, rewritten, grades, gate_passed?)

      :self_refine ->
        self_refine_step(original_text, rewritten, grades, max_attempts, gate_passed?)

      :iterative ->
        iterative_step(original_text, rewritten, grades, max_attempts, gate_passed?)
    end
  end

  defp single_shot_result(original_text, rewritten, grades, gate_passed?) do
    judge_score = if gate_passed?, do: fetch_judge_score(original_text, rewritten)
    status = if gate_passed? and judge_clears?(judge_score), do: :passed, else: :held

    {status_tag(status),
     build_result(status, grades, rewritten, :single_shot, gate_passed?, judge_score)}
  end

  defp self_refine_step(original_text, rewritten, grades, max_attempts, gate_passed?) do
    cond do
      gate_passed? ->
        {:ok, build_result(:passed, grades, rewritten, :self_refine, gate_passed?, nil)}

      grades.attempts >= max_attempts ->
        {:hold, build_result(:held, grades, rewritten, :self_refine, gate_passed?, nil)}

      true ->
        attempt(
          original_text,
          rewritten,
          grades.fk_before,
          grades.target,
          max_attempts,
          grades.attempts + 1,
          :self_refine
        )
    end
  end

  defp iterative_step(original_text, rewritten, grades, max_attempts, gate_passed?) do
    judge_score = if gate_passed?, do: fetch_judge_score(original_text, rewritten)

    cond do
      gate_passed? and judge_clears?(judge_score) ->
        {:ok, build_result(:passed, grades, rewritten, :iterative, gate_passed?, judge_score)}

      grades.attempts >= max_attempts ->
        {:hold, build_result(:held, grades, rewritten, :iterative, gate_passed?, judge_score)}

      true ->
        attempt(
          original_text,
          rewritten,
          grades.fk_before,
          grades.target,
          max_attempts,
          grades.attempts + 1,
          :iterative
        )
    end
  end

  defp gate_passed?({:ok, []}), do: true
  defp gate_passed?({:reject, _reasons}), do: false

  defp judge_clears?(nil), do: false

  defp judge_clears?(%JudgeScore{simplicity: s, fidelity: f, fluency: fl}) do
    s >= @judge_threshold and f >= @judge_threshold and fl >= @judge_threshold
  end

  defp fetch_judge_score(original, rewrite) do
    case LLM.score(original, rewrite) do
      {:ok, %JudgeScore{} = score} ->
        score

      {:error, %Ecto.Changeset{} = changeset} ->
        Logger.warning(
          "judge score malformed, treating as failed attempt: #{inspect(changeset.errors)}"
        )

        nil

      {:error, reason} ->
        Logger.warning("judge score call failed, treating as failed attempt: #{inspect(reason)}")
        nil
    end
  end

  defp status_tag(:passed), do: :ok
  defp status_tag(:held), do: :hold

  defp build_result(status, grades, text_out, run_mode, gate_passed?, judge_score) do
    %Result{
      status: status,
      fk_before: grades.fk_before,
      fk_after: grades.fk_after,
      target: grades.target,
      attempts: grades.attempts,
      text_out: text_out,
      run_mode: run_mode,
      gate_passed: gate_passed?,
      judge_score: judge_score
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

        {:error, reason} ->
          Logger.warning("judge call failed, result has no verdict: #{inspect(reason)}")
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
