defmodule Prana.Execution do
  @moduledoc """
  Represents a workflow execution instance with structured suspension support.

  ## Suspension Fields

  - `suspended_node_id` - ID of the node that caused suspension
  - `suspension_type` - Type of suspension (:webhook, :interval, :schedule, etc.)
  - `suspension_data` - Typed data structure for the suspension
  - `suspended_at` - When the execution was suspended


  The execution now uses both structured suspension data AND a root-level resume_token
  for optimal querying and type safety:

  - **Structured fields** provide type safety and direct access
  - **resume_token** enables fast webhook lookups and database queries

  ## Example

      # Structured suspension data (type-safe)
      execution.suspension_type       # :webhook
      execution.suspension_data       # %{resume_url: "...", webhook_id: "..."}
      execution.suspended_node_id     # "node_123"
      execution.suspended_at          # ~U[2024-01-01 12:00:00Z]

      # Resume token for fast queries
      execution.resume_token          # "abc123def456..." (indexed for fast lookups)

  ## Webhook Resume Benefits

      # Fast webhook resume lookup (single indexed query)
      Repo.get_by(Execution, resume_token: "abc123def456")
  """

  alias Prana.Core.SuspensionData

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
          suspended_node_id: String.t() | nil,
          suspension_type: SuspensionData.suspension_type() | nil,
          suspension_data: SuspensionData.suspension_data() | nil,
          suspended_at: DateTime.t() | nil,
          resume_token: String.t() | nil,
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          metadata: map()
        }

  defstruct [
    :id,
    :workflow_id,
    :workflow_version,
    :parent_execution_id,
    :root_execution_id,
    :trigger_node_id,
    :execution_mode,
    :status,
    :trigger_type,
    :trigger_data,
    :input_data,
    :output_data,
    :context_data,
    :error_data,
    :node_executions,
    :suspended_node_id,
    :suspension_type,
    :suspension_data,
    :suspended_at,
    :resume_token,
    :started_at,
    :completed_at,
    metadata: %{}
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
      suspended_node_id: nil,
      suspension_type: nil,
      suspension_data: nil,
      suspended_at: nil,
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
    %{execution | status: :running, started_at: DateTime.utc_now()}
  end

  @doc """
  Marks execution as completed
  """
  def complete(%__MODULE__{} = execution, output_data) do
    %{execution | status: :completed, output_data: output_data, completed_at: DateTime.utc_now()}
  end

  @doc """
  Marks execution as failed
  """
  def fail(%__MODULE__{} = execution, error_data) do
    %{execution | status: :failed, error_data: error_data, completed_at: DateTime.utc_now()}
  end

  @doc """
  Suspends execution with structured suspension data.

  ## Parameters
  - `execution` - The execution to suspend
  - `node_id` - ID of the node that caused the suspension
  - `suspension_type` - Type of suspension (:webhook, :interval, etc.)
  - `suspension_data` - Typed suspension data structure
  - `resume_token` - Optional resume token for webhook lookups (defaults to generated token)

  ## Example

      suspension_data = SuspensionData.create_webhook_suspension(
        "https://app.com/webhook/abc123",
        "webhook_1",
        3600
      )

      # Auto-generate resume token
      suspend(execution, "node_123", :webhook, suspension_data)

      # Explicit resume token for webhook scenarios
      suspend(execution, "node_123", :webhook, suspension_data, "custom_resume_token_123")
  """
  def suspend(%__MODULE__{} = execution, node_id, suspension_type, suspension_data, resume_token \\ nil) do
    final_resume_token = resume_token || generate_resume_token()

    %{
      execution
      | status: :suspended,
        suspended_node_id: node_id,
        suspension_type: suspension_type,
        suspension_data: suspension_data,
        suspended_at: DateTime.utc_now(),
        resume_token: final_resume_token
    }
  end

  @doc """
  Legacy suspend function for backward compatibility.

  This function is deprecated and will be removed in a future version.
  Use suspend/4 with structured suspension data instead.
  """
  @deprecated "Use suspend/4 with structured suspension data"
  def suspend(%__MODULE__{} = execution, resume_token) when is_binary(resume_token) do
    %{execution | status: :suspended}
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

  @doc """
  Checks if execution is suspended
  """
  def suspended?(%__MODULE__{status: :suspended}), do: true
  def suspended?(%__MODULE__{}), do: false

  @doc """
  Resumes a suspended execution by clearing suspension fields.

  This only clears the suspension state - the caller is responsible for
  updating the status and continuing execution.

  ## Example

      execution
      |> resume_suspension()
      |> Map.put(:status, :running)
  """
  def resume_suspension(%__MODULE__{} = execution) do
    %{
      execution
      | suspended_node_id: nil,
        suspension_type: nil,
        suspension_data: nil,
        suspended_at: nil,
        resume_token: nil
    }
  end

  @doc """
  Gets suspension information if execution is suspended.

  ## Returns
  - `{:ok, suspension_info}` if suspended
  - `:not_suspended` if not suspended

  ## Example

      case get_suspension_info(execution) do
        {:ok, %{type: :webhook, data: data, node_id: node_id}} ->
          # Handle webhook suspension
        :not_suspended ->
          # Execution not suspended
      end
  """
  def get_suspension_info(%__MODULE__{
        status: :suspended,
        suspended_node_id: node_id,
        suspension_type: type,
        suspension_data: data,
        suspended_at: suspended_at
      })
      when not is_nil(node_id) and not is_nil(type) and not is_nil(data) do
    {:ok,
     %{
       node_id: node_id,
       type: type,
       data: data,
       suspended_at: suspended_at
     }}
  end

  def get_suspension_info(%__MODULE__{}) do
    :not_suspended
  end

  @doc """
  Validates suspension data for the execution's suspension type.

  ## Returns
  - `:ok` if valid or not suspended
  - `{:error, reason}` if invalid suspension data
  """
  def validate_suspension_data(%__MODULE__{suspension_type: type, suspension_data: data})
      when not is_nil(type) and not is_nil(data) do
    SuspensionData.validate_suspension_data(type, data)
  end

  def validate_suspension_data(%__MODULE__{}), do: :ok

  defp generate_id do
    16 |> :crypto.strong_rand_bytes() |> Base.encode64() |> binary_part(0, 16)
  end

  defp generate_resume_token do
    32 |> :crypto.strong_rand_bytes() |> Base.encode64() |> binary_part(0, 32)
  end
end
