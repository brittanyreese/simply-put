defmodule SimplyPut.MetricProvider.Bumblebee.ServingsTest do
  use ExUnit.Case, async: true

  alias SimplyPut.MetricProvider.Bumblebee.Servings

  test "checkpoint_id/1 returns a pinned id for every metric" do
    for metric <- [:summac, :bertscore, :sle, :question_gen, :qa_extraction] do
      id = Servings.checkpoint_id(metric)
      assert is_binary(id)
      assert id != ""
    end
  end
end
