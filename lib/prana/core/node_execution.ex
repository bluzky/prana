defmodule Prana.NodeExecution do
  @moduledoc """
  Represents execution state of an individual node
  """

  @type status :: :pending | :running | :completed | :failed | :skipped | :suspended

  @type t :: %__MODULE__{
          id: String.t(),
          execution_id: String.t(),
          node_id: String.t(),
          status: status(),
          input_data: map(),
          output_data: map() | nil,
          output_port: String.t() | nil,
          error_data: map() | nil,
          retry_count: integer(),
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          duration_ms: integer() | nil,
          suspension_type: atom() | nil,
          suspension_data: term() | nil,
          metadata: map()
        }

  defstruct [
    :id,
    :execution_id,
    :node_id,
    :status,
    :input_data,
    :output_data,
    :output_port,
    :error_data,
    :started_at,
    :completed_at,
    :duration_ms,
    :suspension_type,
    :suspension_data,
    retry_count: 0,
    metadata: %{}
  ]

  @doc """
  Creates a new node execution
  """
  def new(execution_id, node_id, input_data) do
    %__MODULE__{
      id: generate_id(),
      execution_id: execution_id,
      node_id: node_id,
      status: :pending,
      input_data: input_data,
      output_data: nil,
      output_port: nil,
      error_data: nil,
      retry_count: 0,
      started_at: nil,
      completed_at: nil,
      duration_ms: nil,
      suspension_type: nil,
      suspension_data: nil,
      metadata: %{}
    }
  end

  @doc """
  Marks node execution as started
  """
  def start(%__MODULE__{} = node_execution) do
    %{node_execution | status: :running, started_at: DateTime.utc_now()}
  end

  @doc """
  Marks node execution as completed
  """
  def complete(%__MODULE__{} = node_execution, output_data, output_port) do
    duration = calculate_duration(node_execution.started_at)

    %{
      node_execution
      | status: :completed,
        output_data: output_data,
        output_port: output_port,
        completed_at: DateTime.utc_now(),
        duration_ms: duration
    }
  end

  @doc """
  Marks node execution as failed
  """
  def fail(%__MODULE__{} = node_execution, error_data) do
    duration = calculate_duration(node_execution.started_at)

    %{
      node_execution
      | status: :failed,
        error_data: error_data,
        output_port: nil,
        completed_at: DateTime.utc_now(),
        duration_ms: duration
    }
  end

  @doc """
  Increments retry count
  """
  def increment_retry(%__MODULE__{} = node_execution) do
    %{node_execution | retry_count: node_execution.retry_count + 1}
  end

  defp calculate_duration(nil), do: nil

  defp calculate_duration(started_at) do
    DateTime.diff(DateTime.utc_now(), started_at, :millisecond)
  end

  defp generate_id do
    16 |> :crypto.strong_rand_bytes() |> Base.encode64() |> binary_part(0, 16)
  end
end
