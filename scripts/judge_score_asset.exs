# Scores the 100 ASSET pairs with the configured judge and writes one
# row per item (item_id, simplicity, fidelity, fluency) so the Python
# agreement analysis can add the judge as one more rater alongside the 15
# humans and compute both columns with a single estimator (Krippendorff).
#
# item_id matches scripts/pivot_asset_labels.py exactly:
#   "asset_" + sha1(original <> simplification)[:12]
# so it joins to the raw worker ratings by the same key.
#
# Usage: OPENROUTER_API_KEY=... METRIC_PROVIDER unset \
#   mix run scripts/judge_score_asset.exs > .scratch/asset/judge_scores.csv
#
# Makes ~100 paid judge calls (one per pair). Errors are skipped, not fatal.

import Ecto.Query
alias SimplyPut.{HumanLabel, LLM, Repo}

labels = Repo.all(from(l in HumanLabel, where: l.source_dataset == :asset))

item_id = fn original, candidate ->
  hash = :crypto.hash(:sha, original <> candidate) |> Base.encode16(case: :lower)
  "asset_" <> binary_part(hash, 0, 12)
end

IO.puts("item_id,simplicity,fidelity,fluency")

{ok, err} =
  Enum.reduce(labels, {0, 0}, fn label, {ok, err} ->
    case LLM.score(label.original_text, label.candidate_text) do
      {:ok, s} ->
        IO.puts(
          "#{item_id.(label.original_text, label.candidate_text)},#{s.simplicity},#{s.fidelity},#{s.fluency}"
        )

        {ok + 1, err}

      {:error, _reason} ->
        {ok, err + 1}
    end
  end)

IO.puts(:stderr, "scored_ok=#{ok} errors=#{err} total=#{length(labels)}")
