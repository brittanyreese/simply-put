defmodule SimplyPut.MetricProvider.Bumblebee.Servings do
  @moduledoc """
  Lazily loads and caches each metric's `Nx.Serving` on first use, so
  application boot never pays the (network-dependent, multi-GB) checkpoint
  load cost. Not part of `SimplyPut.Application`'s default supervision
  tree -- `SimplyPut.MetricProvider.Bumblebee` starts it on demand, the
  first time any metric function is actually called.

  Checkpoint ids below are provisional (not yet pinned/verified against a
  live download in this environment -- no network egress here, see
  `docs/plans/phase1-health-demo/scratchpad.md`). Confirm each loads and
  behaves as expected, then record the exact pinned ids per the plan's
  Phase M task before treating any score as reproducible.
  """

  use GenServer

  @summac_checkpoint {:hf, "FacebookAI/roberta-large-mnli"}
  @bertscore_checkpoint {:hf, "FacebookAI/roberta-large"}
  @sle_checkpoint {:hf, "liamcripwell/sle-base"}
  @question_gen_checkpoint {:hf, "iarfmoose/t5-base-question-generator"}
  @qa_extraction_checkpoint {:hf, "deepset/roberta-base-squad2"}
  @qa_extraction_tokenizer {:hf, "FacebookAI/roberta-base"}

  @type metric :: :summac | :bertscore | :sle | :question_gen | :qa_extraction

  @doc """
  The pinned Hugging Face checkpoint id for `metric`, for reproducibility
  logging (Phase F's `faithfulness_provider` column on `rewrite_evaluations`).
  """
  @spec checkpoint_id(metric()) :: String.t()
  def checkpoint_id(:summac), do: elem(@summac_checkpoint, 1)
  def checkpoint_id(:bertscore), do: elem(@bertscore_checkpoint, 1)
  def checkpoint_id(:sle), do: elem(@sle_checkpoint, 1)
  def checkpoint_id(:question_gen), do: elem(@question_gen_checkpoint, 1)
  def checkpoint_id(:qa_extraction), do: elem(@qa_extraction_checkpoint, 1)

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @doc """
  Runs `input` through the named metric's serving, loading (and caching)
  the checkpoint on first call. Loading can take a long time and requires
  network access; callers should expect `:infinity` timeouts.
  """
  @spec run(metric(), term()) :: {:ok, term()} | {:error, term()}
  def run(metric, input) do
    ensure_started()
    GenServer.call(__MODULE__, {:run, metric, input}, :infinity)
  end

  defp ensure_started do
    case GenServer.whereis(__MODULE__) do
      nil ->
        case start_link() do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
        end

      _pid ->
        :ok
    end
  end

  @impl true
  def init(:ok), do: {:ok, %{}}

  @impl true
  def handle_call({:run, metric, input}, _from, servings) do
    case Map.fetch(servings, metric) do
      {:ok, serving} ->
        {:reply, {:ok, Nx.Serving.run(serving, input)}, servings}

      :error ->
        case load_serving(metric) do
          {:ok, serving} ->
            {:reply, {:ok, Nx.Serving.run(serving, input)}, Map.put(servings, metric, serving)}

          {:error, reason} ->
            {:reply, {:error, reason}, servings}
        end
    end
  end

  defp load_serving(:summac) do
    with {:ok, model} <- Bumblebee.load_model(@summac_checkpoint),
         {:ok, tokenizer} <- Bumblebee.load_tokenizer(@summac_checkpoint) do
      {:ok, Bumblebee.Text.text_classification(model, tokenizer, top_k: 3)}
    end
  end

  defp load_serving(:bertscore) do
    with {:ok, model} <- Bumblebee.load_model(@bertscore_checkpoint),
         {:ok, tokenizer} <- Bumblebee.load_tokenizer(@bertscore_checkpoint) do
      {:ok,
       Bumblebee.Text.text_embedding(model, tokenizer,
         output_attribute: :hidden_state,
         output_pool: :mean_pooling
       )}
    end
  end

  defp load_serving(:sle) do
    with {:ok, model} <- Bumblebee.load_model(@sle_checkpoint),
         {:ok, tokenizer} <- Bumblebee.load_tokenizer(@sle_checkpoint) do
      {:ok, Bumblebee.Text.text_classification(model, tokenizer, scores_function: :none)}
    end
  end

  defp load_serving(:question_gen) do
    with {:ok, model} <- Bumblebee.load_model(@question_gen_checkpoint),
         {:ok, tokenizer} <- Bumblebee.load_tokenizer(@question_gen_checkpoint),
         {:ok, generation_config} <- Bumblebee.load_generation_config(@question_gen_checkpoint) do
      {:ok, Bumblebee.Text.generation(model, tokenizer, generation_config)}
    end
  end

  defp load_serving(:qa_extraction) do
    with {:ok, model} <- Bumblebee.load_model(@qa_extraction_checkpoint),
         {:ok, tokenizer} <- Bumblebee.load_tokenizer(@qa_extraction_tokenizer) do
      {:ok, Bumblebee.Text.question_answering(model, tokenizer)}
    end
  end
end
