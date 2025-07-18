defmodule Prana.NodeExecution do
  @moduledoc """
  Represents execution state of an individual node
  """

  use Skema

  defschema do
    field(:node_key, :string, required: true)
    field(:status, :atom, default: :pending)
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

  @type status :: :pending | :running | :completed | :failed | :skipped | :suspended

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

  defp calculate_duration(nil), do: nil

  defp calculate_duration(started_at) do
    DateTime.diff(DateTime.utc_now(), started_at, :millisecond)
  end
end
