defmodule Prana.WorkflowExecution do
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

  use Skema

  alias Prana.Core.Error

  defschema do
    field(:id, :string, required: true)
    field(:workflow_id, :string, required: true)
    field(:workflow_version, :integer, default: 1)
    field(:execution_graph, Prana.ExecutionGraph)
    field(:parent_execution_id, :string)
    field(:execution_mode, :atom, default: :async)
    field(:status, :string, default: "pending")
    field(:error, :map)
    field(:trigger_type, :string)
    field(:trigger_data, :map, default: %{})
    field(:vars, :map, default: %{})

    #   node_executions: %{String.t() => [Prana.NodeExecution.t()]},
    # NodeExecution list is stored in reverse order from newest to oldest. This helps reducing traversal when accessing the latest execution.
    field(:node_executions, :map, default: %{})
    field(:current_execution_index, :integer, default: 0)

    # Structured suspension fields
    field(:suspended_node_id, :string)
    field(:suspension_type, :string)
    field(:suspension_data, :map)
    field(:suspended_at, :datetime)

    # Execution timestamps
    field(:started_at, :datetime)
    field(:completed_at, :datetime)

    # Runtime state
    field(:__runtime, :map, default: %{})

    # Additional metadata
    field(:preparation_data, :map, default: %{})
    field(:metadata, :map, default: %{})
  end

  # status :: "pending" | "running" | "suspended" | "completed" | "failed" | "timeout"
  @type execution_mode :: :sync | :async | :fire_and_forget

  @doc """
  Creates a new execution
  """
  def new(graph, trigger_type, vars) do
    execution_id = generate_id()

    new(%{
      id: execution_id,
      workflow_id: graph.workflow_id,
      execution_graph: graph,
      execution_mode: :async,
      status: "pending",
      trigger_type: trigger_type,
      vars: vars
    })
  end

  @doc """
  Marks execution as started
  """
  def start(%__MODULE__{} = execution) do
    %{execution | status: "running", started_at: DateTime.utc_now()}
  end

  @doc """
  Marks execution as completed
  """
  def complete(%__MODULE__{} = execution) do
    %{execution | status: "completed", completed_at: DateTime.utc_now()}
  end

  @doc """
  Marks execution as failed
  """
  def fail(%__MODULE__{} = execution, error \\ nil) do
    %{execution | status: "failed", error: error, completed_at: DateTime.utc_now()}
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
      | status: "suspended",
        suspended_node_id: node_key,
        suspension_type: suspension_type,
        suspension_data: suspension_data,
        suspended_at: DateTime.utc_now()
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
    status in ["completed", "failed", :cancelled]
  end

  @doc """
  Checks if execution is still running
  """
  def running?(%__MODULE__{status: status}) do
    status in ["pending", "running", "suspended"]
  end

  @doc """
  Resumes a suspended execution by clearing suspension fields.

  This only clears the suspension state - the caller is responsible for
  updating the status and continuing execution.

  ## Example

      execution
      |> resume_suspension()
      |> Map.put(:status, "running")
  """
  def resume_suspension(%__MODULE__{} = execution) do
    %{
      execution
      | suspended_node_id: nil,
        suspension_type: nil,
        suspension_data: nil,
        suspended_at: nil,
        current_execution_index: execution.current_execution_index - 1
    }
  end

  @doc """
  Loads a workflow execution from a map with string keys, converting nested structures to proper types.

  Automatically converts:
  - Nested node_execution maps to NodeExecution structs
  - String keys to atoms where appropriate (status, execution_mode)
  - DateTime strings to DateTime structs
  - Preserves all execution state and audit trail

  ## Examples

      execution_map = %{
        "id" => "exec_123",
        "workflow_id" => "wf_456",
        "status" => "suspended",
        "execution_mode" => "async",
        "node_executions" => %{
          "node_1" => [%{
            "node_key" => "node_1",
            "status" => "completed",
            "output_data" => %{"result" => "success"}
          }]
        },
        "started_at" => "2024-01-01T10:00:00Z"
      }

      execution = WorkflowExecution.from_map(execution_map)
      # All nested NodeExecution maps are converted to proper structs
      # DateTime strings are converted to DateTime structs
  """
  def from_map(data) when is_map(data) do
    {:ok, execution} = Skema.load(data, __MODULE__)

    # Convert nested node_execution maps to NodeExecution structs
    node_executions = convert_node_executions_to_structs(execution.node_executions)

    %{execution | node_executions: node_executions}
  end

  @doc """
  Converts a workflow execution to a JSON-compatible map with nested structs converted to maps.

  Automatically converts:
  - NodeExecution structs to maps
  - DateTime structs to ISO8601 strings
  - Preserves all execution state and audit trail for round-trip serialization

  ## Examples

      execution = %WorkflowExecution{
        id: "exec_123",
        workflow_id: "wf_456",
        status: "suspended",
        execution_mode: :async,
        node_executions: %{
          "node_1" => [%NodeExecution{
            node_key: "node_1",
            status: "completed",
            output_data: %{"result" => "success"}
          }]
        },
        started_at: ~U[2024-01-01 10:00:00Z]
      }

      execution_map = WorkflowExecution.to_map(execution)
      json_string = Jason.encode!(execution_map)
      # Ready for database storage or API transport
  """
  def to_map(%__MODULE__{} = execution) do
    execution
    |> Map.from_struct()
    |> Map.update!(:node_executions, fn node_executions ->
      convert_node_executions_to_maps(node_executions)
    end)
  end

  # Convert nested node_execution maps to NodeExecution structs
  defp convert_node_executions_to_structs(node_executions) when is_map(node_executions) do
    Map.new(node_executions, fn {node_key, executions} ->
      converted_executions =
        Enum.map(executions, fn exec_map ->
          Prana.NodeExecution.from_map(exec_map)
        end)

      {node_key, converted_executions}
    end)
  end

  # Convert nested NodeExecution structs to maps
  defp convert_node_executions_to_maps(node_executions) when is_map(node_executions) do
    Map.new(node_executions, fn {node_key, executions} ->
      converted_executions =
        Enum.map(executions, fn exec_struct ->
          Map.from_struct(exec_struct)
        end)

      {node_key, converted_executions}
    end)
  end

  defp generate_id do
    UUID.uuid4()
  end

  # Rebuild completed node outputs from execution history
  defp rebuild_completed_node_outputs(node_executions) do
    node_executions
    |> Enum.map(fn {node_key, executions} ->
      last_execution = Enum.find(executions, &(&1.status == "completed"))

      case last_execution do
        nil -> {node_key, nil}
        exec -> {node_key, %{"output" => exec.output_data}}
      end
    end)
    |> Enum.reject(fn {_, data} -> is_nil(data) end)
    |> Map.new()
  end

  # Rebuild active_paths and active_nodes using DFS algorithm for loop handling
  defp rebuild_active_paths_and_active_nodes(execution) do
    execution_graph = execution.execution_graph
    trigger_node_key = execution_graph.trigger_node_key

    completed_node_maps =
      Map.new(execution.node_executions || %{}, fn {node_key, executions} ->
        {node_key, hd(executions)}
      end)

    dfs_traverse(
      execution_graph,
      completed_node_maps,
      trigger_node_key,
      # previous node execution
      nil,
      # initial active_paths
      %{},
      # initial active_nodes
      %{}
    )
  end

  # Depth-first search traversal following the loop-aware algorithm
  #
  # This algorithm builds active paths and active nodes from the execution graph and completed node executions.
  # For the given current_node_key:
  # - if current execution is nil, then add node to active_nodes because node execution not completed
  # - if current execution is completed:
  #   + if previous_node_execution is nil, then add to active_paths,
  #     then for each connection from current node via output port, recursively traverse to next node and accumulate both active_paths and active_nodes
  #   + if previous_node_execution is not nil, then check execution_index:
  #     - if current execution_index is greater than previous, then add to active_paths
  #       then for each connection from current node via output port, recursively traverse to next node and accumulate both active_paths and active_nodes
  #     - if current execution_index is less than or equal to previous, then do not add to active_paths but add to active_nodes

  defp dfs_traverse(
         execution_graph,
         completed_node_maps,
         current_node_key,
         previous_node_execution,
         active_paths,
         active_nodes
       ) do
    current_execution = Map.get(completed_node_maps, current_node_key)

    next_execution_index = if is_nil(previous_node_execution), do: 0, else: previous_node_execution.execution_index + 1

    cond do
      is_nil(current_execution) ->
        # No execution found for this node, add to active_nodes
        {active_paths, Map.put(active_nodes, current_node_key, next_execution_index)}

      current_execution.status == "completed" and
          (is_nil(previous_node_execution) or
             current_execution.execution_index > previous_node_execution.execution_index) ->
        # if no previous execution, or current execution is newer than previous
        # add to active_paths and continue traversal
        new_active_paths =
          Map.put(active_paths, current_node_key, %{
            execution_index: current_execution.execution_index
          })

        # Get all target nodes connected to this node via output port
        target_nodes =
          execution_graph.connection_map
          |> Map.get({current_node_key, current_execution.output_port}, [])
          |> Enum.map(& &1.to)

        Enum.reduce(target_nodes, {new_active_paths, active_nodes}, fn target_node_key,
                                                                       {acc_active_paths, acc_active_nodes} ->
          # Recursively traverse to next nodes
          dfs_traverse(
            execution_graph,
            completed_node_maps,
            target_node_key,
            current_execution,
            acc_active_paths,
            acc_active_nodes
          )
        end)

      current_execution.status == "completed" ->
        # if current execution is completed but not newer than previous
        # Do not add to active_paths, but add to active_nodes
        new_active_nodes = Map.put(active_nodes, current_node_key, next_execution_index)
        {active_paths, new_active_nodes}

      true ->
        # Current execution is not completed, add to active_nodes for example in case of resuming, retrying, etc.
        {active_paths, Map.put(active_nodes, current_node_key, next_execution_index)}
    end
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
  - `"active_paths"` - Map of completed nodes in current loop iterations: %{node_key => %{execution_index: index}}
  - `"active_nodes"` - Map of ready-to-execute nodes with their execution depths: %{node_key => depth}
  - `"shared_state"` - Shared state data that persists across node executions within the same workflow

  ## Example

      # Load from storage (has nil __runtime)
      execution = Repo.get(Execution, execution_id)

      # Rebuild runtime state
      env_data = %{"api_key" => "abc123", "base_url" => "https://api.example.com"}
      execution = rebuild_runtime(execution, env_data)

      # Now ready for execution/resume
      execution.__runtime["nodes"]         # %{"node_1" => %{...}, "node_2" => %{...}}
      execution.__runtime["env"]           # %{"api_key" => "abc123", ...}
      execution.__runtime["active_paths"]  # %{"loop_node" => %{execution_index: 3}}
      execution.__runtime["active_nodes"]  # %{"ready_node" => 4}
      execution.__runtime["shared_state"]  # %{"counter" => 5, "user_data" => %{...}}
  """
  def rebuild_runtime(%__MODULE__{} = execution, env_data \\ %{}) do
    node_outputs = rebuild_completed_node_outputs(execution.node_executions)
    {active_paths, active_nodes} = rebuild_active_paths_and_active_nodes(execution)

    max_iterations = Application.get_env(:prana, :max_execution_iterations, 100)
    current_iteration_count = execution.metadata["iteration_count"] || 0

    # Restore shared state from metadata if available
    shared_state = execution.metadata["shared_state"] || %{}

    runtime = %{
      "nodes" => node_outputs,
      "env" => env_data,
      "iteration_count" => current_iteration_count,
      "max_iterations" => max_iterations,
      "active_paths" => active_paths,
      "active_nodes" => active_nodes,
      "shared_state" => shared_state
    }

    %{execution | __runtime: runtime}
  end

  # Update node executions list, handling retries by replacing same run_index
  defp update_node_executions([], new_execution), do: [new_execution]

  defp update_node_executions(existing_executions, new_execution) do
    # remaining_executions =
    #   Enum.reject(existing_executions, fn ne -> ne.run_index == new_execution.run_index end)

    # Enum.sort_by([new_execution | remaining_executions], & &1.execution_index, :desc)
    [last | remaining_executions] = existing_executions

    if last.run_index == new_execution.run_index do
      # Replace existing execution with same run_index
      [new_execution | remaining_executions]
    else
      [new_execution | existing_executions]
    end
  end

  # Get input ports for a node, with fallback to default "input" port
  defp get_node_input_ports(node) do
    case Prana.IntegrationRegistry.get_action_by_type(node.type) do
      {:ok, action} ->
        action.input_ports || ["input"]

      {:error, _reason} ->
        ["input"]
    end
  end

  # Safely update runtime state, handling nil runtime
  defp update_runtime_safely(execution, update_fn) do
    case execution.__runtime do
      nil -> execution
      runtime -> %{execution | __runtime: update_fn.(runtime)}
    end
  end

  @doc """
  Adds a completed node execution to the execution and updates all completion-related state.

  This function integrates an already-completed NodeExecution into the execution's
  audit trail and synchronizes both persistent and runtime state, including updating
  active nodes and node depth tracking for workflow orchestration.

  ## Parameters
  - `execution` - The execution to update
  - `completed_node_execution` - The completed NodeExecution to add

  ## Returns
  Updated execution with synchronized persistent and runtime state, including updated active nodes

  ## Example

      completed_node_exec = NodeExecution.complete(node_exec, %{user_id: 123}, "success")
      execution = complete_node(execution, completed_node_exec)

      # Both persistent and runtime state updated
      execution.node_executions  # Contains the completed NodeExecution
      execution.__runtime["nodes"]["api_call"]  # Contains %{user_id: 123}
      execution.__runtime["active_nodes"]  # Updated based on completed node's outputs
  """
  def complete_node(%__MODULE__{} = execution, %Prana.NodeExecution{status: "completed"} = completed_node_execution) do
    node_key = completed_node_execution.node_key
    existing_executions = Map.get(execution.node_executions, node_key, [])

    # Update node executions list
    updated_executions = update_node_executions(existing_executions, completed_node_execution)
    updated_node_executions = Map.put(execution.node_executions, node_key, updated_executions)

    # Update execution with persistent state
    updated_execution = %{
      execution
      | node_executions: updated_node_executions,
        current_execution_index: execution.current_execution_index + 1
    }

    # Update runtime state if present
    updated_execution =
      update_runtime_safely(updated_execution, fn runtime ->
        node_data = %{"output" => completed_node_execution.output_data}
        updated_node_map = Map.put(runtime["nodes"] || %{}, node_key, node_data)
        Map.put(runtime, "nodes", updated_node_map)
      end)

    # Update active nodes and node depth tracking based on completion
    update_active_nodes_on_completion(updated_execution, node_key, completed_node_execution)
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
  def fail_node(%__MODULE__{} = execution, %Prana.NodeExecution{status: "failed"} = failed_node_execution) do
    node_key = failed_node_execution.node_key
    existing_executions = Map.get(execution.node_executions, node_key, [])

    # Update node executions list
    updated_executions = update_node_executions(existing_executions, failed_node_execution)
    updated_node_executions = Map.put(execution.node_executions, node_key, updated_executions)

    %{
      execution
      | node_executions: updated_node_executions,
        current_execution_index: execution.current_execution_index + 1
    }
  end

  @doc """
  Get next run index for a specific node.

  This function calculates the next run index for a node based on its existing executions.
  Used for retry scenarios where a node needs to be executed multiple times.

  ## Parameters
  - `execution` - The execution containing node execution history
  - `node_key` - The key of the node to get the next run index for

  ## Returns
  Integer representing the next run index for the node
  """
  def get_next_run_index(%__MODULE__{} = execution, node_key) do
    case Map.get(execution.node_executions, node_key, []) do
      [] ->
        0

      executions ->
        max_run_index = Enum.max_by(executions, & &1.run_index).run_index
        max_run_index + 1
    end
  end

  # @doc """
  # Get incoming connections for a specific node and port.

  # This function retrieves all connections that target a specific node and input port
  # using the execution graph's reverse connection map for O(1) lookup performance.

  # ## Parameters
  # - `execution_graph` - The execution graph containing connection maps
  # - `node_key` - The key of the target node
  # - `input_port` - The name of the input port

  # ## Returns
  # List of Connection structs targeting the specified node and port
  # """
  defp get_incoming_connections_for_node_port(execution_graph, node_key, input_port) do
    reverse_map = Map.get(execution_graph, :reverse_connection_map, %{})
    all_incoming = Map.get(reverse_map, node_key, [])

    # Filter for connections targeting the specific input port
    Enum.filter(all_incoming, fn conn -> conn.to_port == input_port end)
  end

  @doc """
  Extract multi-port input data for a node by computing routing from execution graph and runtime state.

  This function builds a complete input map for a node by examining all its input ports
  and routing the appropriate data from connected nodes based on the execution graph.

  ## Parameters
  - `node` - The node to extract input data for
  - `execution_graph` - The execution graph containing connection information
  - `execution` - The execution containing runtime state and completed node outputs

  ## Returns
  Map with port names as keys and routed data as values
  """
  def extract_multi_port_input(node, execution) do
    # Get input ports from the action definition, not the node
    input_ports = get_node_input_ports(node)

    # Build multi-port input map: port_name => routed_data
    multi_port_input =
      Enum.reduce(input_ports, %{}, fn input_port, acc ->
        # Find all connections that target this node's input port
        incoming_connections = get_incoming_connections_for_node_port(execution.execution_graph, node.key, input_port)

        # For same input port with multiple connections, use most recent execution_index
        port_data = resolve_input_port_data(incoming_connections, execution)

        if port_data do
          Map.put(acc, input_port, port_data)
        else
          acc
        end
      end)

    multi_port_input
  end

  # Get valid connection data for a source node
  defp get_connection_data(connection, execution) do
    node_executions = Map.get(execution.node_executions, connection.from, [])
    latest_execution = List.first(node_executions)

    if latest_execution && latest_execution.output_port == connection.from_port do
      source_node_data = execution.__runtime["nodes"][connection.from]
      output_data = if source_node_data, do: source_node_data["output"]
      {connection, latest_execution, output_data}
    end
  end

  # Select most recent output data from multiple connections
  defp select_most_recent_output(connection_data_list) do
    {_, _, output_data} =
      Enum.max_by(connection_data_list, fn {_, execution, _} ->
        execution.execution_index
      end)

    output_data
  end

  @doc """
  Resolve input port data when multiple connections target the same port.

  This function handles the case where multiple connections feed into the same input port
  by using execution_index to select the most recent execution's output data.

  ## Parameters
  - `connections` - List of Connection structs targeting the same input port
  - `execution` - The execution containing runtime state and node execution history

  ## Returns
  The output data from the most recent execution, or nil if no valid data found
  """
  def resolve_input_port_data(connections, execution) do
    valid_connections =
      connections
      |> Enum.map(&get_connection_data(&1, execution))
      |> Enum.reject(&is_nil/1)

    case valid_connections do
      [] -> nil
      [{_, _, output_data}] -> output_data
      connection_data_list -> select_most_recent_output(connection_data_list)
    end
  end

  # Update active_nodes when a node completes.
  # This function updates the runtime state to reflect that a node has completed execution
  # by removing it from active_nodes and adding its target nodes based on the output port.
  # It also maintains active_nodes tracking for branch-following execution strategy.
  defp update_active_nodes_on_completion(execution, completed_node_key, node_execution) do
    update_runtime_safely(execution, fn runtime ->
      # Get current active_nodes and active_paths from runtime
      current_active_nodes = runtime["active_nodes"] || %{}
      current_active_paths = runtime["active_paths"] || %{}

      # Get completed node's execution index
      completed_execution_index = node_execution.execution_index

      # Remove completed node from active_nodes
      updated_active_nodes = Map.delete(current_active_nodes, completed_node_key)

      # Add completed node to active_paths for loop tracking
      updated_active_paths =
        Map.put(current_active_paths, completed_node_key, %{execution_index: completed_execution_index})

      # Add target nodes from completed node's output connections
      # this check because some test missing the runtime state
      {final_active_nodes, final_active_paths} =
        if execution.execution_graph && Map.has_key?(execution.execution_graph, :connection_map) do
          connections =
            Map.get(execution.execution_graph.connection_map, {completed_node_key, node_execution.output_port}, [])

          new_active_nodes =
            Enum.reduce(connections, updated_active_nodes, fn %{to: node_key}, acc_active_nodes ->
              Map.put(acc_active_nodes, node_key, completed_execution_index + 1)
            end)

          existing_path_node = Map.get(updated_active_paths, completed_node_key)

          new_active_paths =
            case existing_path_node do
              nil ->
                Map.put(updated_active_paths, completed_node_key, %{execution_index: node_execution.execution_index})

              _ ->
                # If path already exists, remove all nodes with higher execution index of existing node
                # then add the completed node with its execution index
                updated_active_paths
                |> Enum.reject(fn {_, path_info} ->
                  path_info.execution_index > existing_path_node.execution_index
                end)
                |> Map.new()
                |> Map.put(completed_node_key, %{execution_index: node_execution.execution_index})
            end

          {new_active_nodes, new_active_paths}
        else
          {updated_active_nodes, updated_active_paths}
        end

      # Update runtime state with both active_nodes and active_paths
      runtime
      |> Map.put("active_nodes", final_active_nodes)
      |> Map.put("active_paths", final_active_paths)
    end)
  end

  @doc """
  Add a node execution to the execution map structure.

  This function adds a NodeExecution to the execution's audit trail, handling
  retry scenarios by replacing existing executions with the same run_index.

  ## Parameters
  - `execution` - The execution to update
  - `node_execution` - The NodeExecution to add

  ## Returns
  Updated execution with the node execution added to node_executions map
  """
  def add_node_execution_to_map(execution, node_execution) do
    node_key = node_execution.node_key
    existing_executions = Map.get(execution.node_executions, node_key, [])

    # Update node executions list
    updated_executions = update_node_executions(existing_executions, node_execution)
    updated_node_executions = Map.put(execution.node_executions, node_key, updated_executions)

    %{
      execution
      | node_executions: updated_node_executions,
        current_execution_index: execution.current_execution_index + 1
    }
  end

  @doc """
  Increment iteration count for loop protection.

  This function increments the iteration counter in both runtime and persistent
  metadata to track workflow execution progress and prevent infinite loops.

  ## Parameters
  - `execution` - The execution to update

  ## Returns
  Updated execution with incremented iteration count
  """
  def increment_iteration_count(execution) do
    current_count = execution.__runtime["iteration_count"] || 0
    new_count = current_count + 1

    execution
    |> put_in([Access.key(:__runtime), "iteration_count"], new_count)
    |> put_in([Access.key(:metadata), "iteration_count"], new_count)
  end

  @doc """
  Get iteration count from runtime state.

  ## Parameters
  - `execution` - The execution to get iteration count from

  ## Returns
  Current iteration count as integer
  """
  def get_iteration_count(execution) do
    execution.__runtime["iteration_count"] || 0
  end

  @doc """
  Get maximum iterations from runtime state.

  ## Parameters
  - `execution` - The execution to get max iterations from

  ## Returns
  Maximum iterations as integer
  """
  def get_max_iterations(execution) do
    execution.__runtime["max_iterations"] || 100
  end

  @doc """
  Get active nodes from runtime state.

  ## Parameters
  - `execution` - The execution to get active nodes from

  ## Returns
  MapSet of active node keys
  """
  def get_active_nodes(execution) do
    (execution.__runtime["active_nodes"] || %{}) |> Map.keys() |> MapSet.new()
  end

  @doc """
  Update shared state with new or modified values.

  This function updates the shared state both in runtime context and persists
  it to metadata for recovery after suspension/resume cycles.

  ## Parameters
  - `execution` - The execution to update
  - `updates` - Map of key-value pairs to update in shared state

  ## Returns
  Updated execution with modified shared state
  """
  def update_shared_state(execution, updates) when is_map(updates) do
    current_shared_state = execution.__runtime["shared_state"] || %{}
    new_shared_state = Map.merge(current_shared_state, updates)

    # Update both runtime and persistent metadata
    execution
    |> update_runtime_safely(fn runtime ->
      Map.put(runtime, "shared_state", new_shared_state)
    end)
    |> put_in([Access.key(:metadata), "shared_state"], new_shared_state)
  end

  @doc """
  Prepare all workflow actions during the preparation phase.

  Scans all nodes in the workflow, calls prepare/1 on each action module,
  and stores the preparation data in the execution struct.

  ## Parameters
  - `execution_graph` - The execution graph containing all nodes
  - `execution` - The execution to store preparation data in

  ## Returns
  - `{:ok, enriched_execution}` - Execution with preparation data stored
  - `{:error, reason}` - Preparation failed with error details
  """
  def prepare_workflow_actions(execution) do
    # Prepare all actions and collect preparation data
    case prepare_all_actions(Map.values(execution.execution_graph.node_map)) do
      {:ok, preparation_data} ->
        # Store preparation data in execution
        enriched_execution = %{execution | preparation_data: preparation_data}
        {:ok, enriched_execution}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Prepare all actions in the workflow
  defp prepare_all_actions(nodes) do
    Enum.reduce_while(nodes, {:ok, %{}}, fn node, {:ok, acc_prep_data} ->
      case prepare_single_action(node) do
        {:ok, nil} ->
          {:cont, {:ok, acc_prep_data}}

        {:ok, node_prep_data} ->
          updated_prep_data = Map.put(acc_prep_data, node.key, node_prep_data)
          {:cont, {:ok, updated_prep_data}}

        {:error, reason} ->
          {:halt,
           {:error,
            Error.new("action_preparation_failed", "Action preparation failed", %{
              "node_key" => node.key,
              "reason" => reason
            })}}
      end
    end)
  end

  # Prepare a single action
  defp prepare_single_action(node) do
    # Look up action from integration registry
    case Prana.IntegrationRegistry.get_action_by_type(node.type) do
      {:ok, action} ->
        # Call prepare/1 on the action module
        try do
          case action.module.prepare(node) do
            {:ok, preparation_data} ->
              {:ok, preparation_data}

            {:error, reason} ->
              {:error, reason}
          end
        rescue
          error ->
            {:error, Error.new("preparation_exception", Exception.message(error))}
        end

      {:error, _reason} ->
        # Action not found in registry, return empty preparation data
        {:ok, nil}
    end
  end

  @doc """
  Find nodes that are ready to execute based on their dependencies and conditional paths.

  A node is ready if:
  1. It hasn't been executed yet (not in completed node executions)
  2. All its input dependencies have been satisfied
  3. It's reachable from completed nodes or is an entry node
  4. It's on an active conditional execution path (for conditional branching)

  ## Parameters

  - `execution` - The execution containing ExecutionGraph and runtime state
  - `execution_context` - Current execution context with conditional path tracking

  ## Returns

  List of Node structs that are ready for execution.
  """
  @spec find_ready_nodes(t()) :: [Prana.Node.t()]
  def find_ready_nodes(%__MODULE__{} = execution) do
    # Get active nodes from execution context
    active_nodes = get_active_nodes(execution)

    # Extract completed node IDs from map structure for dependency checking
    completed_node_ids =
      execution.node_executions
      |> Enum.map(fn {node_key, executions} -> {node_key, List.first(executions)} end)
      |> Enum.filter(fn {_, exec} -> exec.status == "completed" end)
      |> MapSet.new(fn {node_key, _} -> node_key end)

    # Only check active nodes instead of all nodes
    active_nodes
    |> Enum.map(fn node_key -> execution.execution_graph.node_map[node_key] end)
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(fn node ->
      dependencies_satisfied?(node, execution.execution_graph, completed_node_ids)
    end)
  end

  # Check if all input ports for a node are satisfied (port-based logic)
  defp dependencies_satisfied?(node, execution_graph, completed_node_ids) do
    # Get input ports for this node
    input_ports = get_node_input_ports(node)

    # For each input port, check if at least one source connection is satisfied
    Enum.all?(input_ports, fn input_port ->
      input_port_satisfied?(node.key, input_port, execution_graph, completed_node_ids)
    end)
  end

  # Check if a specific input port is satisfied (at least one source available)
  defp input_port_satisfied?(node_key, input_port, execution_graph, completed_node_ids) do
    # Get all incoming connections for this node and port
    incoming_connections = get_incoming_connections_for_node_port(execution_graph, node_key, input_port)

    # If no incoming connections, port is satisfied (no dependencies)
    if Enum.empty?(incoming_connections) do
      true
    else
      # At least one source node must be completed
      Enum.any?(incoming_connections, fn conn ->
        MapSet.member?(completed_node_ids, conn.from)
      end)
    end
  end
end
