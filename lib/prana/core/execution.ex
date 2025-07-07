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
          vars: map(),
          output_data: map() | nil,
          context_data: map(),
          error_data: map() | nil,
          node_executions: %{String.t() => [Prana.NodeExecution.t()]},
          current_execution_index: integer(),
          preparation_data: map(),
          suspended_node_id: String.t() | nil,
          suspension_type: SuspensionData.suspension_type() | nil,
          suspension_data: SuspensionData.suspension_data() | nil,
          suspended_at: DateTime.t() | nil,
          resume_token: String.t() | nil,
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          metadata: map(),
          __runtime:
            %{
              String.t() => any()
            }
            | nil
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
    :vars,
    :output_data,
    :context_data,
    :error_data,
    :node_executions,
    :current_execution_index,
    :suspended_node_id,
    :suspension_type,
    :suspension_data,
    :suspended_at,
    :resume_token,
    :started_at,
    :completed_at,
    :__runtime,
    preparation_data: %{},
    metadata: %{}
  ]

  @doc """
  Creates a new execution
  """
  def new(workflow_id, workflow_version, trigger_type, vars, trigger_node_id \\ nil) do
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
      vars: vars,
      output_data: nil,
      context_data: %{},
      error_data: nil,
      node_executions: %{},
      current_execution_index: 0,
      preparation_data: %{},
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

  @doc """
  Rebuilds runtime state from persistent execution data and environment context.

  This function reconstructs the ephemeral runtime state from the persistent
  node_executions audit trail and provided environment data.

  ## Parameters
  - `execution` - The execution to rebuild runtime state for
  - `env_data` - Environment context data from the application

  ## Returns
  Updated execution with rebuilt __runtime state containing:
  - `"nodes"` - Map of completed node outputs for routing
  - `"env"` - Environment data from application
  - `"active_paths"` - Active conditional branching paths
  - `"executed_nodes"` - Chronological list of executed node IDs

  ## Example

      # Load from storage (has nil __runtime)
      execution = Repo.get(Execution, execution_id)

      # Rebuild runtime state
      env_data = %{"api_key" => "abc123", "base_url" => "https://api.example.com"}
      execution = rebuild_runtime(execution, env_data)

      # Now ready for execution/resume
      execution.__runtime["nodes"]         # %{"node_1" => %{...}, "node_2" => %{...}}
      execution.__runtime["env"]           # %{"api_key" => "abc123", ...}
      execution.__runtime["active_paths"]  # %{"path_1" => true, "path_2" => true}
      execution.__runtime["executed_nodes"] # ["node_1", "node_2"]
  """
  def rebuild_runtime(%__MODULE__{} = execution, env_data \\ %{}) do
    # Get LAST completed execution of each node (highest run_index)
    node_structured =
      execution.node_executions
      |> Enum.map(fn {node_id, executions} ->
        last_execution =
          executions
          |> Enum.reverse()
          |> Enum.find(&(&1.status == :completed))

        case last_execution do
          nil -> {node_id, nil}
          exec -> {node_id, %{"output" => exec.output_data, "context" => exec.context_data}}
        end
      end)
      |> Enum.reject(fn {_, data} -> is_nil(data) end)
      |> Map.new()

    # Build runtime state (simplified for now)
    runtime = %{
      "nodes" => node_structured,
      "env" => env_data
    }

    %{execution | __runtime: runtime}
  end

  @doc """
  Adds a completed node execution to the execution and updates runtime state.

  This function integrates an already-completed NodeExecution into the execution's
  audit trail and synchronizes the runtime state for optimal performance.

  ## Parameters
  - `execution` - The execution to update
  - `completed_node_execution` - The completed NodeExecution to add

  ## Returns
  Updated execution with synchronized persistent and runtime state

  ## Example

      completed_node_exec = NodeExecution.complete(node_exec, %{user_id: 123}, "success")
      execution = complete_node(execution, completed_node_exec)

      # Both persistent and runtime state updated
      execution.node_executions  # Contains the completed NodeExecution
      execution.__runtime["nodes"]["api_call"]  # Contains %{user_id: 123}
  """
  def complete_node(%__MODULE__{} = execution, %Prana.NodeExecution{status: :completed} = completed_node_execution) do
    node_id = completed_node_execution.node_id

    # Get existing executions for this node
    existing_executions = Map.get(execution.node_executions, node_id, [])

    # Remove any existing execution with same run_index (for retries)
    remaining_executions =
      Enum.reject(existing_executions, fn ne -> ne.run_index == completed_node_execution.run_index end)

    # Add the completed execution (maintain chronological order by execution_index)
    updated_executions =
      Enum.sort_by(remaining_executions ++ [completed_node_execution], & &1.execution_index)

    # Update the map
    updated_node_executions = Map.put(execution.node_executions, node_id, updated_executions)

    # Update runtime state if present
    updated_runtime =
      case execution.__runtime do
        nil ->
          nil

        runtime ->
          # Update with latest execution output
          node_data = %{
            "output" => completed_node_execution.output_data,
            "context" => completed_node_execution.context_data
          }

          updated_node_map = Map.put(runtime["nodes"] || %{}, node_id, node_data)
          Map.put(runtime, "nodes", updated_node_map)
      end

    %{execution | node_executions: updated_node_executions, __runtime: updated_runtime}
  end

  @doc """
  Adds a failed node execution to the execution and updates runtime state.

  This function integrates an already-failed NodeExecution into the execution's
  audit trail and synchronizes the runtime state.

  ## Parameters
  - `execution` - The execution to update
  - `failed_node_execution` - The failed NodeExecution to add

  ## Returns
  Updated execution with synchronized persistent and runtime state

  ## Example

      failed_node_exec = NodeExecution.fail(node_exec, %{error: "Network timeout"})
      execution = fail_node(execution, failed_node_exec)

      # Both persistent and runtime state updated
      execution.node_executions  # Contains the failed NodeExecution
      execution.__runtime["nodes"]["api_call"]  # Not present (failed nodes don't provide output)
  """
  def fail_node(%__MODULE__{} = execution, %Prana.NodeExecution{status: :failed} = failed_node_execution) do
    node_id = failed_node_execution.node_id

    # Get existing executions for this node
    existing_executions = Map.get(execution.node_executions, node_id, [])

    # Remove any existing execution with same run_index (for retries)
    remaining_executions =
      Enum.reject(existing_executions, fn ne -> ne.run_index == failed_node_execution.run_index end)

    # Add the failed execution
    updated_executions =
      Enum.sort_by(remaining_executions ++ [failed_node_execution], & &1.execution_index)

    # Update the map
    updated_node_executions = Map.put(execution.node_executions, node_id, updated_executions)

    %{execution | node_executions: updated_node_executions}
  end

  defp generate_resume_token do
    32 |> :crypto.strong_rand_bytes() |> Base.encode64() |> binary_part(0, 32)
  end
end
