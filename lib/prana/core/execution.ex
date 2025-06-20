defmodule Prana.Execution do
  @moduledoc """
  Represents a workflow execution instance
  """
  
  @type status :: :pending | :running | :suspended | :completed | :failed | :cancelled | :timeout
  @type execution_mode :: :sync | :async | :fire_and_forget
  
  @type t :: %__MODULE__{
    id: String.t(),
    workflow_id: String.t(),
    workflow_version: integer(),
    parent_execution_id: String.t() | nil,
    root_execution_id: String.t() | nil,
    trigger_node_id: String.t() | nil,
    execution_mode: execution_mode(),
    status: status(),
    trigger_type: String.t(),
    trigger_data: map(),
    input_data: map(),
    output_data: map() | nil,
    context_data: map(),
    error_data: map() | nil,
    node_executions: [Prana.NodeExecution.t()],
    webhook_callback_url: String.t() | nil,
    resume_token: String.t() | nil,
    started_at: DateTime.t() | nil,
    completed_at: DateTime.t() | nil,
    metadata: map()
  }

  defstruct [
    :id, :workflow_id, :workflow_version, :parent_execution_id, :root_execution_id,
    :trigger_node_id, :execution_mode, :status, :trigger_type, :trigger_data, :input_data,
    :output_data, :context_data, :error_data, :node_executions,
    :webhook_callback_url, :resume_token, :started_at, :completed_at, metadata: %{}
  ]

  @doc """
  Creates a new execution
  """
  def new(workflow_id, workflow_version, trigger_type, input_data, trigger_node_id \\ nil) do
    execution_id = generate_id()
    
    %__MODULE__{
      id: execution_id,
      workflow_id: workflow_id,
      workflow_version: workflow_version,
      parent_execution_id: nil,
      root_execution_id: execution_id,
      trigger_node_id: trigger_node_id,
      execution_mode: :async,
      status: :pending,
      trigger_type: trigger_type,
      trigger_data: %{},
      input_data: input_data,
      output_data: nil,
      context_data: %{},
      error_data: nil,
      node_executions: [],
      webhook_callback_url: nil,
      resume_token: nil,
      started_at: nil,
      completed_at: nil,
      metadata: %{}
    }
  end

  @doc """
  Marks execution as started
  """
  def start(%__MODULE__{} = execution) do
    %{execution | 
      status: :running, 
      started_at: DateTime.utc_now()
    }
  end

  @doc """
  Marks execution as completed
  """
  def complete(%__MODULE__{} = execution, output_data) do
    %{execution |
      status: :completed,
      output_data: output_data,
      completed_at: DateTime.utc_now()
    }
  end

  @doc """
  Marks execution as failed
  """
  def fail(%__MODULE__{} = execution, error_data) do
    %{execution |
      status: :failed,
      error_data: error_data,
      completed_at: DateTime.utc_now()
    }
  end

  @doc """
  Suspends execution with resume token
  """
  def suspend(%__MODULE__{} = execution, resume_token) do
    %{execution |
      status: :suspended,
      resume_token: resume_token
    }
  end

  @doc """
  Gets execution duration in milliseconds
  """
  def duration(%__MODULE__{started_at: nil}), do: nil
  def duration(%__MODULE__{started_at: started, completed_at: nil}) do
    DateTime.diff(DateTime.utc_now(), started, :millisecond)
  end
  def duration(%__MODULE__{started_at: started, completed_at: completed}) do
    DateTime.diff(completed, started, :millisecond)
  end

  @doc """
  Checks if execution is in a terminal state
  """
  def terminal?(%__MODULE__{status: status}) do
    status in [:completed, :failed, :cancelled]
  end

  @doc """
  Checks if execution is still running
  """
  def running?(%__MODULE__{status: status}) do
    status in [:pending, :running, :suspended]
  end

  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.encode64() |> binary_part(0, 16)
  end
end
