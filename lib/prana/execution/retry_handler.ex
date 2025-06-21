defmodule Prana.RetryHandler do
  @moduledoc """
  Handles retry logic for failed node executions.

  Supports different backoff strategies and error filtering.
  """

  alias Prana.Node
  alias Prana.NodeExecution
  alias Prana.RetryPolicy

  require Logger

  @doc """
  Determine if a failed node execution should be retried.
  """
  @spec should_retry?(Node.t(), NodeExecution.t()) :: boolean()
  def should_retry?(%Node{retry_policy: nil}, _execution), do: false

  def should_retry?(%Node{retry_policy: policy} = node, %NodeExecution{} = execution) do
    with true <- retry_count_available?(policy, execution) do
      error_type_retryable?(policy, execution)
    end
  end

  @doc """
  Calculate delay before next retry attempt.
  """
  @spec calculate_retry_delay(RetryPolicy.t(), integer()) :: integer()
  def calculate_retry_delay(%RetryPolicy{} = policy, retry_count) do
    base_delay =
      case policy.backoff_strategy do
        :fixed ->
          policy.initial_delay_ms

        :linear ->
          policy.initial_delay_ms * (retry_count + 1)

        :exponential ->
          round(policy.initial_delay_ms * :math.pow(policy.backoff_multiplier, retry_count))
      end

    # Apply max delay limit
    capped_delay = min(base_delay, policy.max_delay_ms)

    # Add jitter if enabled
    if policy.jitter do
      add_jitter(capped_delay)
    else
      capped_delay
    end
  end

  @doc """
  Create a new node execution for retry attempt.
  """
  @spec prepare_retry_execution(NodeExecution.t()) :: NodeExecution.t()
  def prepare_retry_execution(%NodeExecution{} = failed_execution) do
    %NodeExecution{
      id: generate_id(),
      execution_id: failed_execution.execution_id,
      node_id: failed_execution.node_id,
      status: :pending,
      input_data: failed_execution.input_data,
      output_data: nil,
      output_port: nil,
      error_data: nil,
      retry_count: failed_execution.retry_count + 1,
      started_at: nil,
      completed_at: nil,
      duration_ms: nil,
      metadata: %{
        "original_execution_id" => failed_execution.id,
        "retry_attempt" => failed_execution.retry_count + 1
      }
    }
  end

  @doc """
  Execute retry with proper delay and logging.
  """
  @spec execute_retry(Node.t(), NodeExecution.t(), function()) ::
          {:ok, NodeExecution.t()} | {:error, {term(), NodeExecution.t()}}
  def execute_retry(%Node{} = node, %NodeExecution{} = failed_execution, executor_fn) do
    if should_retry?(node, failed_execution) do
      retry_delay = calculate_retry_delay(node.retry_policy, failed_execution.retry_count)

      Logger.info("Retrying node #{node.id}, attempt #{failed_execution.retry_count + 1}, delay: #{retry_delay}ms")

      # Wait for retry delay
      :timer.sleep(retry_delay)

      # Create new execution for retry
      retry_execution = prepare_retry_execution(failed_execution)

      # Execute retry
      executor_fn.(retry_execution)
    else
      Logger.info("Retry exhausted for node #{node.id}, attempt #{failed_execution.retry_count}")
      {:error, {:retry_exhausted, failed_execution}}
    end
  end

  @doc """
  Handle retry in the context of GraphExecutor batch processing.
  """
  @spec handle_batch_retry(Node.t(), NodeExecution.t(), function()) ::
          {:retry, NodeExecution.t()} | {:exhausted, NodeExecution.t()}
  def handle_batch_retry(%Node{} = node, %NodeExecution{} = failed_execution, _executor_fn) do
    if should_retry?(node, failed_execution) do
      retry_execution = prepare_retry_execution(failed_execution)
      {:retry, retry_execution}
    else
      {:exhausted, failed_execution}
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  @spec retry_count_available?(RetryPolicy.t(), NodeExecution.t()) :: boolean()
  defp retry_count_available?(%RetryPolicy{max_attempts: max}, %NodeExecution{retry_count: count}) do
    count < max
  end

  @spec error_type_retryable?(RetryPolicy.t(), NodeExecution.t()) :: boolean()
  defp error_type_retryable?(%RetryPolicy{retry_on_errors: []}, _execution) do
    # Empty list means retry on all errors
    true
  end

  defp error_type_retryable?(%RetryPolicy{retry_on_errors: error_types}, %NodeExecution{error_data: error_data}) do
    error_type = get_in(error_data, ["type"]) || "unknown"
    error_type in error_types
  end

  @spec add_jitter(integer()) :: integer()
  defp add_jitter(delay) do
    # Add ±25% random jitter
    jitter_range = div(delay, 4)
    jitter = :rand.uniform(jitter_range * 2) - jitter_range
    max(delay + jitter, 0)
  end

  defp generate_id do
    16 |> :crypto.strong_rand_bytes() |> Base.encode64() |> binary_part(0, 16)
  end
end
