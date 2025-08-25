defmodule Prana.NodeExecution do
  @moduledoc """
  Represents execution state of an individual node
  """

  use Skema

  defschema do
    field(:node_key, :string, required: true)
    field(:status, :string, default: "pending")
    field(:params, :map, default: %{})
    field(:output_data, :map)
    field(:output_port, :string)
    field(:error_data, :map)
    field(:started_at, :datetime)
    field(:completed_at, :datetime)
    field(:duration_ms, :integer)
    field(:suspension_type, :atom)
    field(:suspension_data, :any)
    field(:execution_index, :integer, default: 0)
    field(:run_index, :integer, default: 0)
  end

  #  status :: "pending" | "running" | "completed" | "failed" | "suspended"

  @doc """
  Creates a new node execution
  """
  def new(node_key, execution_index, run_index) do
    new(%{
      node_key: node_key,
      execution_index: execution_index,
      run_index: run_index
    })
  end

  @doc """
  Marks node execution as started
  """
  def start(%__MODULE__{} = node_execution) do
    %{node_execution | status: "running", started_at: DateTime.utc_now()}
  end

  def suspend(%__MODULE__{} = node_execution, suspension_type, suspension_data) do
    %{
      node_execution
      | status: "suspended",
        suspension_type: suspension_type,
        suspension_data: suspension_data
    }
  end

  def resume(%__MODULE__{} = node_execution) do
    %{
      node_execution
      | status: "running",
        suspension_type: nil,
        suspension_data: nil,
        started_at: DateTime.utc_now()
    }
  end

  @doc """
  Marks node execution as completed
  """
  def complete(%__MODULE__{} = node_execution, output_data, output_port) do
    duration = calculate_duration(node_execution.started_at)

    %{
      node_execution
      | status: "completed",
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
      | status: "failed",
        error_data: error_data,
        output_port: nil,
        completed_at: DateTime.utc_now(),
        duration_ms: duration
    }
  end

  @doc """
  Loads a node execution from a map with string keys, converting to proper types.

  Automatically converts:
  - String keys to atoms where appropriate (status)
  - DateTime strings to DateTime structs
  - Preserves all execution state and output data

  ## Examples

      node_execution_map = %{
        "node_key" => "api_call",
        "status" => "completed",
        "output_data" => %{"user_id" => 123, "email" => "user@example.com"},
        "output_port" => "success",
        "started_at" => "2024-01-01T10:00:00Z",
        "completed_at" => "2024-01-01T10:05:00Z",
        "duration_ms" => 5000
      }

      node_execution = NodeExecution.from_map(node_execution_map)
      # Status is converted to atom, DateTime strings to DateTime structs
  """
  def from_map(data) when is_map(data) do
    {:ok, data} = Skema.load(data, __MODULE__)
    data
  end

  @doc """
  Converts a node execution to a JSON-compatible map.

  Preserves all execution state including output data, timing, and error information
  for round-trip serialization.

  ## Examples

      node_execution = %NodeExecution{
        node_key: "api_call",
        status: "completed",
        output_data: %{"user_id" => 123, "email" => "user@example.com"},
        output_port: "success",
        started_at: ~U[2024-01-01 10:00:00Z],
        completed_at: ~U[2024-01-01 10:05:00Z],
        duration_ms: 5000
      }

      node_execution_map = NodeExecution.to_map(node_execution)
      json_string = Jason.encode!(node_execution_map)
      # Ready for database storage or API transport
  """
  def to_map(%__MODULE__{} = node_execution) do
    Map.from_struct(node_execution)
  end

  defp calculate_duration(nil), do: nil

  defp calculate_duration(started_at) do
    DateTime.diff(DateTime.utc_now(), started_at, :millisecond)
  end
end
