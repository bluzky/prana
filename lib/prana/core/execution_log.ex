defmodule Prana.ExecutionLog do
  @moduledoc """
  Represents a log entry for execution debugging and monitoring
  """
  
  @type level :: :debug | :info | :warn | :error
  
  @type t :: %__MODULE__{
    id: String.t(),
    execution_id: String.t(),
    node_execution_id: String.t() | nil,
    level: level(),
    message: String.t(),
    data: map() | nil,
    timestamp: DateTime.t(),
    source: String.t()
  }

  defstruct [:id, :execution_id, :node_execution_id, :level, :message, :data, :timestamp, :source]

  @doc """
  Creates a new execution log
  """
  def new(execution_id, level, message, opts \\ []) do
    %__MODULE__{
      id: generate_id(),
      execution_id: execution_id,
      node_execution_id: Keyword.get(opts, :node_execution_id),
      level: level,
      message: message,
      data: Keyword.get(opts, :data),
      timestamp: DateTime.utc_now(),
      source: Keyword.get(opts, :source, "prana")
    }
  end

  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.encode64() |> binary_part(0, 16)
  end
end
