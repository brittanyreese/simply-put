defmodule SimplyPut.MetricProvider.Bumblebee.Servings do
  @moduledoc """
  Lazily loads and caches each metric's `Nx.Serving` on first use, so
  application boot never pays the (network-dependent, multi-GB) checkpoint
  load cost. Not part of `SimplyPut.Application`'s default supervision
  tree -- `SimplyPut.MetricProvider.Bumblebee` starts it on demand, the
  first time any metric function is actually called.

  Checkpoint ids below name the exact HF repos the eval runs load (by
  name, not revision-pinned). Each metric maps onto a stock Bumblebee task
  shape (text classification, embedding, generation, question answering).
  """

  use GenServer

  @summac_checkpoint {:hf, "FacebookAI/roberta-large-mnli"}
  @bertscore_checkpoint {:hf, "FacebookAI/roberta-large"}
  @sle_checkpoint {:hf, "liamcripwell/sle-base"}
  # sle-base ships no Bumblebee-loadable tokenizer of its own; it is a
  # RoBERTa-base fine-tune, so load the stock base tokenizer instead. Same
  # split-repo trick as :qa_extraction below.
  @sle_tokenizer {:hf, "FacebookAI/roberta-base"}
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
        {:reply, safe_run(serving, input), servings}

      :error ->
        case safe_load(metric) do
          {:ok, serving} ->
            {:reply, safe_run(serving, input), Map.put(servings, metric, serving)}

          {:error, reason} ->
            {:reply, {:error, reason}, servings}
        end
    end
  end

  # Checkpoint load can raise (an incompatible tokenizer format, a 404 on a
  # moved repo). Same rule as safe_run: degrade that one metric to {:error}
  # rather than crash the GenServer and abort the batch.
  defp safe_load(metric) do
    load_serving(metric)
  rescue
    exception -> {:error, {:load_raised, Exception.message(exception)}}
  end

  # A serving that raises (bad input shape, OOM on one long row) must not take
  # down the GenServer and abort a whole batch. Degrade that one call to
  # {:error, _}, which every MetricProvider caller already handles by dropping
  # the metric for that row.
  defp safe_run(serving, input) do
    {:ok, Nx.Serving.run(serving, input)}
  rescue
    exception -> {:error, {:serving_raised, Exception.message(exception)}}
  end

  defp load_serving(:summac) do
    with {:ok, model} <- Bumblebee.load_model(@summac_checkpoint),
         {:ok, tokenizer} <- Bumblebee.load_tokenizer(@summac_checkpoint) do
      {:ok, Bumblebee.Text.text_classification(model, tokenizer, top_k: 3)}
    end
  end

  defp load_serving(:bertscore) do
    # Load the base encoder, not the checkpoint's default masked-LM head:
    # only the base architecture exposes the singular :hidden_state that
    # mean-pooling needs. The LM head output map has :logits and :hidden_states
    # (all layers), neither poolable here.
    with {:ok, model} <- Bumblebee.load_model(@bertscore_checkpoint, architecture: :base),
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
         {:ok, tokenizer} <- Bumblebee.load_tokenizer(@sle_tokenizer) do
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
