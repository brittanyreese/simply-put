defmodule SimplyPut.LLM.OpenRouterExtractJsonTest do
  # Non-live: exercises the pure JSON-extraction helper that guards score/2
  # against fenced or preamble-wrapped judge output. No network, so no :live tag.
  use ExUnit.Case, async: true

  alias SimplyPut.LLM.OpenRouter

  test "returns a bare JSON object unchanged" do
    content = ~s({"simplicity": 4, "fidelity": 5, "fluency": 4})
    assert {:ok, json} = OpenRouter.extract_json_object(content)
    assert Jason.decode!(json)["fidelity"] == 5
  end

  test "strips a ```json fence" do
    content = "```json\n{\"simplicity\": 3, \"fidelity\": 4, \"fluency\": 5}\n```"
    assert {:ok, json} = OpenRouter.extract_json_object(content)
    assert Jason.decode!(json)["fluency"] == 5
  end

  test "strips a natural-language preamble" do
    content = "Here is my assessment:\n{\"simplicity\": 2, \"fidelity\": 3, \"fluency\": 3}"
    assert {:ok, json} = OpenRouter.extract_json_object(content)
    assert Jason.decode!(json)["simplicity"] == 2
  end

  test "spans newlines inside the object" do
    content = "{\n  \"simplicity\": 4,\n  \"fidelity\": 4,\n  \"fluency\": 4\n}"
    assert {:ok, json} = OpenRouter.extract_json_object(content)
    assert Jason.decode!(json)["simplicity"] == 4
  end

  test "errors when no JSON object is present" do
    assert {:error, {:no_json_object, "sorry, I cannot comply"}} =
             OpenRouter.extract_json_object("sorry, I cannot comply")
  end
end
