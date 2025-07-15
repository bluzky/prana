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
          execution_graph: Prana.ExecutionGraph.t(),
          parent_execution_id: String.t() | nil,
          execution_mode: execution_mode(),
          status: status(),
          trigger_type: String.t(),
          trigger_data: map(),
          vars: map(),
          context_data: map(),
          node_executions: %{String.t() => [Prana.NodeExecution.t()]},
          current_execution_index: integer(),
          preparation_data: map(),
          suspended_node_id: String.t() | nil,
          suspension_type: SuspensionData.suspension_type() | nil,
          suspension_data: SuspensionData.suspension_data() | nil,
          suspended_at: DateTime.t() | nil,
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
    :execution_graph,
    :parent_execution_id,
    :execution_mode,
    :status,
    :trigger_type,
    :trigger_data,
    :vars,
    :context_data,
    :node_executions,
    :current_execution_index,
    :suspended_node_id,
    :suspension_type,
    :suspension_data,
    :suspended_at,
    :started_at,
    :completed_at,
    :__runtime,
    preparation_data: %{},
    metadata: %{}
  ]

  @doc """
  Creates a new execution
  """
  def new(graph, trigger_type, vars) do
    execution_id = generate_id()

    %__MODULE__{
      id: execution_id,
      workflow_id: graph.workflow_id,
      parent_execution_id: nil,
      execution_mode: :async,
      status: :pending,
      trigger_type: trigger_type,
      trigger_data: %{},
      vars: vars,
      context_data: %{},
      node_executions: %{},
      current_execution_index: 0,
      preparation_data: %{},
      suspended_node_id: nil,
      suspension_type: nil,
      suspension_data: nil,
      suspended_at: nil,
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
  def complete(%__MODULE__{} = execution) do
    %{execution | status: :completed, completed_at: DateTime.utc_now()}
  end

  @doc """
  Marks execution as failed
  """
  def fail(%__MODULE__{} = execution) do
    %{execution | status: :failed, completed_at: DateTime.utc_now()}
  end

  @doc """
  Suspends execution with structured suspension data.

  ## Parameters
  - `execution` - The execution to suspend
  - `node_key` - ID of the node that caused the suspension
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
  def suspend(%__MODULE__{} = execution, node_key, suspension_type, suspension_data) do
    %{
      execution
      | status: :suspended,
        suspended_node_id: node_key,
        suspension_type: suspension_type,
        suspension_data: suspension_data,
        suspended_at: DateTime.utc_now()
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

  # Rebuild active_nodes from execution state with loop support
  defp rebuild_active_nodes(execution, execution_graph) do
    # 1. Do not include suspended nodes in active nodes during runtime rebuild
    # Suspended nodes will be resumed and completed, so they shouldn't be active
    base_active_nodes = MapSet.new()

    # 2. Get all completed nodes with their execution info
    completed_nodes = get_completed_nodes_with_execution_info(execution)

    # 3. Find nodes that have received fresh input since their last execution
    nodes_with_fresh_input =
      execution_graph.node_map
      |> Map.keys()
      |> Enum.filter(fn node_key ->
        has_fresh_input_since_last_execution?(node_key, completed_nodes, execution_graph)
      end)
      |> MapSet.new()

    MapSet.union(base_active_nodes, nodes_with_fresh_input)
  end

  # Check if a node has received fresh input since its last execution
  defp has_fresh_input_since_last_execution?(node_key, completed_nodes, execution_graph) do
    # Get incoming connections to this node
    incoming_connections = get_incoming_connections_for_node(execution_graph, node_key)

    # Get the last execution info for this node (if any)
    last_execution = Map.get(completed_nodes, node_key)

    # Check if any incoming connection has fresh data
    Enum.any?(incoming_connections, fn conn ->
      source_execution = Map.get(completed_nodes, conn.from)

      case {last_execution, source_execution} do
        {nil, %{}} ->
          # Node never executed, but has input from completed node
          true

        {%{execution_index: last_idx}, %{execution_index: source_idx}} ->
          # Node was executed, check if source completed AFTER this node's last execution
          source_idx > last_idx

        {%{}, nil} ->
          # Node was executed but source hasn't completed - no fresh input
          false

        _ ->
          false
      end
    end)
  end

  # Get completed nodes with their execution information
  defp get_completed_nodes_with_execution_info(execution) do
    Map.new(execution.node_executions, fn {node_key, executions} ->
      last_execution = List.last(executions)

      if last_execution && last_execution.status == :completed do
        {node_key, last_execution}
      else
        {node_key, nil}
      end
    end)
  end

  # Get incoming connections for a specific node
  defp get_incoming_connections_for_node(execution_graph, node_key) do
    # Use reverse connection map if available, otherwise fall back to filtering
    case Map.get(execution_graph, :reverse_connection_map) do
      nil ->
        # Fallback: filter all connections (less efficient but functional)
        Enum.filter(execution_graph.workflow.connections, fn conn ->
          conn.to == node_key
        end)

      reverse_map ->
        # Optimized: direct lookup
        Map.get(reverse_map, node_key, [])
    end
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
        suspended_at: nil
    }
  end

  @doc """
  Gets suspension information if execution is suspended.

  ## Returns
  - `{:ok, suspension_info}` if suspended
  - `:not_suspended` if not suspended

  ## Example

      case get_suspension_info(execution) do
        {:ok, %{type: :webhook, data: data, node_key: node_key}} ->
          # Handle webhook suspension
        :not_suspended ->
          # Execution not suspended
      end
  """
  def get_suspension_info(%__MODULE__{
        status: :suspended,
        suspended_node_id: node_key,
        suspension_type: type,
        suspension_data: data,
        suspended_at: suspended_at
      })
      when not is_nil(node_key) and not is_nil(type) and not is_nil(data) do
    {:ok,
     %{
       node_key: node_key,
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
  - `"active_nodes"` - List of node that is actively to check for executable. They are nodes without input or node with fresh input data. Or nodes that are waiting for all inputs to be ready.

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
  def rebuild_runtime(%__MODULE__{} = execution, env_data \\ %{}, execution_graph \\ nil) do
    # Get LAST completed execution of each node (highest run_index)
    node_structured =
      execution.node_executions
      |> Enum.map(fn {node_key, executions} ->
        last_execution =
          executions
          |> Enum.reverse()
          |> Enum.find(&(&1.status == :completed))

        case last_execution do
          nil -> {node_key, nil}
          exec -> {node_key, %{"output" => exec.output_data, "context" => exec.context_data}}
        end
      end)
      |> Enum.reject(fn {_, data} -> is_nil(data) end)
      |> Map.new()

    # Rebuild active_nodes if execution_graph is provided
    active_nodes =
      if execution_graph do
        rebuild_active_nodes(execution, execution_graph)
      else
        # Default empty for cases without execution_graph
        MapSet.new()
      end

    # Build runtime state
    max_iterations = Application.get_env(:prana, :max_execution_iterations, 100)

    # Get iteration count from persistent metadata (survives suspension/resume)
    current_iteration_count = execution.metadata["iteration_count"] || 0

    runtime = %{
      "nodes" => node_structured,
      "env" => env_data,
      "active_nodes" => active_nodes,
      "iteration_count" => current_iteration_count,
      "max_iterations" => max_iterations
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
    node_key = completed_node_execution.node_key

    # Get existing executions for this node
    existing_executions = Map.get(execution.node_executions, node_key, [])

    # Remove any existing execution with same run_index (for retries)
    remaining_executions =
      Enum.reject(existing_executions, fn ne -> ne.run_index == completed_node_execution.run_index end)

    # Add the completed execution (maintain chronological order by execution_index)
    updated_executions =
      Enum.sort_by(remaining_executions ++ [completed_node_execution], & &1.execution_index)

    # Update the map
    updated_node_executions = Map.put(execution.node_executions, node_key, updated_executions)

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

          updated_node_map = Map.put(runtime["nodes"] || %{}, node_key, node_data)
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
    node_key = failed_node_execution.node_key

    # Get existing executions for this node
    existing_executions = Map.get(execution.node_executions, node_key, [])

    # Remove any existing execution with same run_index (for retries)
    remaining_executions =
      Enum.reject(existing_executions, fn ne -> ne.run_index == failed_node_execution.run_index end)

    # Add the failed execution
    updated_executions =
      Enum.sort_by(remaining_executions ++ [failed_node_execution], & &1.execution_index)

    # Update the map
    updated_node_executions = Map.put(execution.node_executions, node_key, updated_executions)

    %{execution | node_executions: updated_node_executions}
  end
end
