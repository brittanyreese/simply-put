defmodule Mix.Tasks.SimplyPut.ImportHumanLabels do
  @shortdoc "Import a human-labeled judge-calibration CSV (ASSET, PLABA TREC)"
  @moduledoc """
  Usage: mix simply_put.import_human_labels <asset|plaba_trec> <path>

  Starts only `Ecto.Repo`, not the full application (Iron Law #12: never
  `app.start` from a mix task).
  """

  use Mix.Task

  alias SimplyPut.HumanLabels.Import

  @impl Mix.Task
  def run([source, path]) when source in ["asset", "plaba_trec"] do
    Mix.Task.run("app.config")
    Application.ensure_all_started(:ecto_sql)
    SimplyPut.Repo.start_link()

    case Import.import(path, String.to_existing_atom(source)) do
      {:ok, count} -> Mix.shell().info("Imported #{count} human-labeled rows (#{source}).")
      {:error, reason} -> Mix.raise("Import failed: #{inspect(reason)}")
    end
  end

  def run(_args) do
    Mix.raise("Usage: mix simply_put.import_human_labels <asset|plaba_trec> <path>")
  end
end
