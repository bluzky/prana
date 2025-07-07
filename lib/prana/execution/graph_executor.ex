defmodule Prana.GraphExecutor do
  @moduledoc """
  GraphExecutor: Branch-Following Workflow Execution Engine

  Orchestrates workflow execution using pre-compiled ExecutionGraphs from WorkflowCompiler.
  Implements branch-following execution strategy that prioritizes completing active execution
  paths before starting new branches, providing predictable and efficient workflow execution.

  ## Primary API

      execute_graph(execution_graph, input_data, context \\ %{})
        :: {:ok, Execution.t()} | {:suspend, Execution.t()} | {:error, Execution.t()}

  ## Required Context Structure

      context = %{
        workflow_loader: (workflow_id -> {:ok, ExecutionGraph.t()} | {:error, reason}),
        variables: %{},     # optional
        metadata: %{}       # optional
      }

  ## Execution Model

  **Branch-Following Strategy**: Executes one node at a time, prioritizing nodes that continue
  active execution branches before starting new branches. This provides:

  - **Predictable execution order**: Branches complete fully before others start
  - **Efficient resource utilization**: Reduced contention between competing nodes
  - **Enhanced conditional branching**: Proper IF/ELSE and switch/case behavior
  - **Improved debuggability**: Clear execution flow for complex workflows

  ## Core Features

  - Branch-following execution with intelligent node selection
  - O(1) connection lookups using pre-built optimization maps
  - Port-based data routing with immediate output processing
  - Context management with optimized batch updates
  - Sub-workflow support (sync and fire-and-forget modes)
  - Conditional path tracking for IF/ELSE and switch patterns
  - Middleware event emission during execution
  - Comprehensive error handling and propagation

  ## Integration Points

  - Uses `WorkflowCompiler` compiled ExecutionGraphs with optimization maps
  - Uses `NodeExecutor.execute_node/3` for individual node execution (unified execution architecture)
  - Uses `ExpressionEngine.process_map/2` for input preparation (via NodeExecutor)
  - Uses `Middleware.call/2` for lifecycle events
  - Uses unified `Execution` struct with runtime state for all context management
  - Initializes runtime state once per execution/resume for optimal performance

  ## Unified Execution Architecture

  This module now uses a single, unified execution context structure:

  ### Execution with Runtime State
  ```elixir
  %Execution{
    # Persistent metadata and audit trail
    id: String.t(),
    workflow_id: String.t(),
    node_executions: [NodeExecution.t()],
    vars: map(),

    # Ephemeral runtime state (rebuilt on load)
    __runtime: %{
      "nodes" => %{node_id => output_data},     # completed node outputs
      "env" => map(),                           # environment data
      "active_paths" => %{path_key => true},    # conditional branching state
      "executed_nodes" => [String.t()]          # execution order tracking
    }
  }
  ```
  - **Purpose**: Single source of truth for all execution state
  - **Keys**: String keys in runtime for expression engine compatibility
  - **Used by**: Both GraphExecutor and NodeExecutor
  - **Benefits**: No context conversion overhead, perfect state rebuilding

  ### Multi-Port Input Routing

  Data flow uses multi-port input routing:
  `extract_multi_port_input/3` → `%{"port_name" => data}` → `NodeExecutor.execute_node/3`
  """

  alias Prana.Execution
  alias Prana.ExecutionGraph
  alias Prana.Middleware
  alias Prana.Node
  alias Prana.NodeExecution
  alias Prana.NodeExecutor

  require Logger

  # Note: Orchestration context type removed - using unified Execution struct only

  @doc """
  Resume a suspended workflow execution with sub-workflow results.

  ## Parameters

  - `suspended_execution` - The suspended Execution struct
  - `resume_data` - Data to resume with (sub-workflow results, external event data, etc.)
  - `execution_graph` - The original ExecutionGraph
  - `execution_context` - The original execution context

  ## Returns

  - `{:ok, execution}` - Successful completion after resume
  - `{:suspend, execution}` - Execution suspended again (for nested async operations)
  - `{:error, reason}` - Resume failed with error details
  """
  @spec resume_workflow(Execution.t(), map(), ExecutionGraph.t(), map()) ::
          {:ok, Execution.t()} | {:suspend, Execution.t()} | {:error, any()}
  def resume_workflow(
        %Execution{status: :suspended} = suspended_execution,
        resume_data,
        execution_graph,
        execution_context
      ) do
    # Initialize runtime state once for resume (execution loaded from storage)
    env_data = Map.get(execution_context, :env, %{})
    prepared_execution = Execution.rebuild_runtime(suspended_execution, env_data)

    # Find the suspended node and complete it with the resume data
    suspended_node_id = prepared_execution.suspended_node_id

    if suspended_node_id do
      # Resume the suspended node execution using NodeExecutor
      case resume_suspended_node(execution_graph, prepared_execution, suspended_node_id, resume_data) do
        {:ok, updated_execution} ->
          # Node resumed successfully, continue execution (same pattern as main loop)
          execute_workflow_loop(updated_execution, execution_graph)

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, %{type: "invalid_suspended_execution", message: "Cannot find suspended node ID"}}
    end
  end

  def resume_workflow(%Execution{status: status}, _resume_data, _execution_graph, _execution_context) do
    {:error, %{type: "invalid_execution_status", message: "Can only resume suspended executions", status: status}}
  end

  @doc """
  Execute a workflow graph with the given context.

  ## Parameters

  - `execution_graph` - Pre-compiled ExecutionGraph from WorkflowCompiler
  - `context` - Execution context with workflow_loader callback and optional variables/metadata

  ## Returns

  - `{:ok, execution}` - Successful execution with final state
  - `{:suspend, execution}` - Execution suspended for async coordination (sub-workflows, external events, etc.)
  - `{:error, failed_execution}` - Execution failed with complete state including failed node details

  ## Examples

      context = %{
        workflow_loader: &MyApp.WorkflowLoader.load_workflow/1,
        variables: %{api_url: "https://api.example.com"},
        metadata: %{user_id: 123}
      }

      # Normal execution
      {:ok, execution} = GraphExecutor.execute_graph(graph, context)

      # Suspended execution (sub-workflow coordination)
      {:suspend, execution} = GraphExecutor.execute_graph(graph, context)
  """
  @spec execute_graph(ExecutionGraph.t(), map()) ::
          {:ok, Execution.t()} | {:suspend, Execution.t()} | {:error, Execution.t()}
  def execute_graph(%ExecutionGraph{} = execution_graph, context \\ %{}) do
    # Create initial execution and context
    execution = Execution.new(execution_graph.workflow.id, 1, "graph_executor", execution_graph.workflow.variables)
    execution = Execution.start(execution)

    # Initialize runtime state once at the start of execution
    env_data = Map.get(context, :env, %{})
    execution = Execution.rebuild_runtime(execution, env_data)

    # Emit execution started event
    Middleware.call(:execution_started, %{execution: execution})

    try do
      # Workflow preparation phase - prepare all actions and store in execution
      case prepare_workflow_actions(execution_graph, execution) do
        {:ok, enriched_execution} ->
          # Main execution loop with enriched execution
          case execute_workflow_loop(enriched_execution, execution_graph) do
            {:ok, final_execution} ->
              Middleware.call(:execution_completed, %{execution: final_execution})
              {:ok, final_execution}

            {:suspend, suspended_execution} ->
              # Workflow suspended for async coordination - return suspended execution
              {:suspend, suspended_execution}

            {:error, failed_execution} ->
              # Failed execution already contains complete state with failed node
              Middleware.call(:execution_failed, %{execution: failed_execution, reason: failed_execution.error_data})
              {:error, failed_execution}
          end

        {:error, reason} ->
          # Preparation failed, fail the execution
          failed_execution = Execution.fail(execution, reason)
          Middleware.call(:execution_failed, %{execution: failed_execution, reason: reason})
          {:error, failed_execution}
      end
    rescue
      error ->
        reason = %{type: "execution_exception", message: Exception.message(error), details: %{}}
        failed_execution = Execution.fail(execution, reason)
        Middleware.call(:execution_failed, %{execution: failed_execution, reason: reason})
        {:error, failed_execution}
    end
  end

  # Main workflow execution loop - continues until workflow is complete or error occurs.
  # Uses Execution.__runtime for all workflow-level coordination.
  defp execute_workflow_loop(execution, execution_graph) do
    if workflow_complete?(execution, execution_graph) do
      final_execution = Execution.complete(execution, %{})
      {:ok, final_execution}
    else
      case find_and_execute_ready_nodes(execution, execution_graph) do
        {:ok, updated_execution} ->
          execute_workflow_loop(updated_execution, execution_graph)

        {:suspend, suspended_execution} ->
          {:suspend, suspended_execution}

        {:error, failed_execution} ->
          {:error, failed_execution}
      end
    end
  end

  # Find ready nodes and execute following branch-completion strategy.
  # Uses Execution.__runtime for tracking active paths and executed nodes.
  defp find_and_execute_ready_nodes(execution, execution_graph) do
    ready_nodes = find_ready_nodes(execution_graph, execution.node_executions, execution.__runtime)

    if Enum.empty?(ready_nodes) do
      # No ready nodes but workflow not complete - likely an error condition
      {:error, %{type: "execution_stalled", message: "No ready nodes found but workflow not complete"}}
    else
      # Select single node to execute, prioritizing branch completion
      selected_node = select_node_for_branch_following(ready_nodes, execution_graph, execution.__runtime)

      case execute_single_node_with_events(selected_node, execution_graph, execution) do
        {%NodeExecution{status: :completed} = _node_execution, updated_execution} ->
          # Output routing and context updates are now handled internally by NodeExecutor
          # and the Execution.complete_node/2 function
          {:ok, updated_execution}

        {%NodeExecution{status: :suspended} = node_execution, updated_execution} ->
          # Extract suspension information from NodeExecution fields
          suspension_type = node_execution.suspension_type || :sub_workflow
          suspend_data = node_execution.suspension_data || %{}

          # Suspend the entire execution with structured suspension data
          suspended_execution =
            Execution.suspend(updated_execution, selected_node.id, suspension_type, suspend_data)

          Middleware.call(:execution_suspended, %{
            execution: suspended_execution,
            suspended_node: selected_node,
            node_execution: node_execution
          })

          {:suspend, suspended_execution}

        {%NodeExecution{status: :failed} = node_execution, updated_execution} ->
          # Update execution with failed node and mark execution as failed
          failed_execution =
            updated_execution
            |> Execution.fail_node(node_execution)
            |> Execution.fail(node_execution.error_data)

          {:error, failed_execution}

        {%NodeExecution{} = _node_execution, updated_execution} ->
          # Node finished with other status - no additional handling needed
          # All context updates are handled by NodeExecutor and Execution functions
          {:ok, updated_execution}
      end
    end
  rescue
    error ->
      # Unexpected error during node execution
      {:error,
       %{
         type: "execution_exception",
         message: "Exception during node execution: #{Exception.message(error)}",
         details: %{exception: error}
       }}
  end

  @doc """
  Select a single node for execution, prioritizing branch completion over batch execution.

  Strategy:
  1. If there are nodes continuing active branches, prioritize those
  2. Otherwise, select the first ready node to start a new branch
  3. Prefer nodes with fewer dependencies (closer to completion)

  ## Parameters

  - `ready_nodes` - List of Node structs that are ready for execution
  - `execution_graph` - The ExecutionGraph for connection analysis
  - `execution_context` - Current execution context with active path tracking

  ## Returns

  Single Node struct selected for execution.
  """
  @spec select_node_for_branch_following([Node.t()], ExecutionGraph.t(), map()) :: Node.t()
  def select_node_for_branch_following(ready_nodes, execution_graph, execution_context) do
    active_paths = Map.get(execution_context, "active_paths", %{})

    # Strategy 1: Find nodes that continue active branches
    continuing_nodes =
      Enum.filter(ready_nodes, fn node ->
        node_continues_active_branch?(node, execution_graph, active_paths)
      end)

    # Prioritize nodes continuing active branches
    if Enum.empty?(continuing_nodes) do
      # No continuing nodes, select any ready node (start new branch)
      # Prefer nodes with fewer dependencies
      ready_nodes
      |> Enum.sort_by(fn node ->
        dependency_count = length(Map.get(execution_graph.dependency_graph, node.id, []))
        dependency_count
      end)
      |> List.first()
    else
      # Among continuing nodes, prefer those with fewer dependencies (closer to completion)
      continuing_nodes
      |> Enum.sort_by(fn node ->
        dependency_count = length(Map.get(execution_graph.dependency_graph, node.id, []))
        dependency_count
      end)
      |> List.first()
    end
  end

  # Check if a node continues an active branch (has incoming connection from active path)
  defp node_continues_active_branch?(node, execution_graph, active_paths) do
    incoming_connections = get_incoming_connections_for_node(execution_graph, node.id)

    Enum.any?(incoming_connections, fn conn ->
      path_key = "#{conn.from}_#{conn.from_port}"
      Map.get(active_paths, path_key, false)
    end)
  end

  @doc """
  Find nodes that are ready to execute based on their dependencies and conditional paths.

  A node is ready if:
  1. It hasn't been executed yet (not in completed node executions)
  2. All its input dependencies have been satisfied
  3. It's reachable from completed nodes or is an entry node
  4. It's on an active conditional execution path (for conditional branching)

  ## Parameters

  - `execution_graph` - The ExecutionGraph containing nodes and dependencies
  - `completed_node_executions` - List of completed NodeExecution structs
  - `execution_context` - Current execution context with conditional path tracking

  ## Returns

  List of Node structs that are ready for execution.
  """
  @spec find_ready_nodes(ExecutionGraph.t(), [NodeExecution.t()], map()) :: [Node.t()]
  def find_ready_nodes(%ExecutionGraph{} = execution_graph, completed_node_executions, execution_context) do
    completed_node_ids = MapSet.new(completed_node_executions, & &1.node_id)

    execution_graph.workflow.nodes
    |> Enum.reject(fn node -> MapSet.member?(completed_node_ids, node.id) end)
    |> Enum.filter(fn node ->
      dependencies_satisfied?(node, execution_graph.dependency_graph, completed_node_ids)
    end)
    |> filter_conditional_branches(execution_graph, execution_context)
  end

  # Check if all dependencies for a node are satisfied
  defp dependencies_satisfied?(node, dependencies, completed_node_ids) do
    node_dependencies = Map.get(dependencies, node.id, [])

    Enum.all?(node_dependencies, fn dep_node_id ->
      MapSet.member?(completed_node_ids, dep_node_id)
    end)
  end

  # Filter nodes based on conditional branching logic
  defp filter_conditional_branches(ready_nodes, execution_graph, execution_context) do
    # Apply conditional filtering if context has active_paths
    if is_map(execution_context) and Map.has_key?(execution_context, "active_paths") do
      # Filter nodes that are on active conditional paths
      Enum.filter(ready_nodes, fn node ->
        node_on_active_conditional_path?(node, execution_graph, execution_context)
      end)
    else
      # No conditional path tracking, return all ready nodes
      ready_nodes
    end
  end

  # Check if a node is on an active conditional execution path
  defp node_on_active_conditional_path?(node, execution_graph, execution_context) do
    # Get all incoming connections to this node using optimized lookup
    incoming_connections = get_incoming_connections_for_node(execution_graph, node.id)

    if Enum.empty?(incoming_connections) do
      # Entry/trigger nodes are always on active path
      true
    else
      # Node is on active path if ANY incoming connection is from an active path
      active_paths = Map.get(execution_context, "active_paths", %{})

      Enum.any?(incoming_connections, fn conn ->
        path_key = "#{conn.from}_#{conn.from_port}"
        Map.get(active_paths, path_key, false)
      end)
    end
  end

  # Get incoming connections for a specific node using optimized lookup
  defp get_incoming_connections_for_node(execution_graph, node_id) do
    # Use reverse connection map if available, otherwise fall back to filtering
    case Map.get(execution_graph, :reverse_connection_map) do
      nil ->
        # Fallback: filter all connections (less efficient but functional)
        Enum.filter(execution_graph.workflow.connections, fn conn ->
          conn.to == node_id
        end)

      reverse_map ->
        # Optimized: direct lookup
        Map.get(reverse_map, node_id, [])
    end
  end

  # Execute a single node with middleware events using unified execution architecture
  defp execute_single_node_with_events(node, execution_graph, execution) do
    # Extract multi-port input data for this node from execution graph and runtime state
    routed_input = extract_multi_port_input(node, execution_graph, execution)

    # Emit node starting event
    Middleware.call(:node_starting, %{node: node, execution: execution})

    # Execute the node using the new unified interface
    case NodeExecutor.execute_node(node, execution, routed_input) do
      {:ok, result_node_execution, updated_execution} ->
        Middleware.call(:node_completed, %{node: node, node_execution: result_node_execution})
        {result_node_execution, updated_execution}

      {:suspend, suspended_node_execution} ->
        # Handle node suspension - emit middleware event for application handling
        Middleware.call(:node_suspended, %{
          node: node,
          node_execution: suspended_node_execution,
          suspension_type: suspended_node_execution.suspension_type,
          suspend_data: suspended_node_execution.suspension_data
        })

        # Add the suspended node execution to the execution's node_executions list
        # This is needed for resume_suspended_node/4 to find the suspended node execution
        updated_execution = %{execution | node_executions: execution.node_executions ++ [suspended_node_execution]}
        {suspended_node_execution, updated_execution}

      {:error, {_reason, error_node_execution}} ->
        Middleware.call(:node_failed, %{node: node, node_execution: error_node_execution})
        # Add the failed node execution to the execution's node_executions list
        # This ensures failed node executions are preserved in the audit trail
        updated_execution = %{execution | node_executions: execution.node_executions ++ [error_node_execution]}
        {error_node_execution, updated_execution}
    end
  end

  # Note: Output routing and context updates are now handled internally by NodeExecutor
  # and the Execution.complete_node/2 function. No separate routing logic needed.

  # Get connections from a specific node and port using O(1) lookup (still needed for active path reconstruction)
  defp get_connections_from_node_port(execution_graph, node_id, output_port) do
    Map.get(execution_graph.connection_map, {node_id, output_port}, [])
  end

  # Note: Execution progress updates are now handled internally by NodeExecutor

  @doc """
  Check if workflow execution is complete.

  A workflow is complete when there are no more nodes ready to execute
  and all nodes on executed conditional paths have been processed.
  For conditional workflows, only nodes on active execution paths
  need to be completed, not all reachable nodes.

  ## Parameters

  - `execution` - Current Execution struct
  - `execution_graph` - ExecutionGraph with nodes and dependencies

  ## Returns

  Boolean indicating if workflow execution is complete.
  """
  @spec workflow_complete?(Execution.t(), ExecutionGraph.t()) :: boolean()
  def workflow_complete?(%Execution{} = execution, %ExecutionGraph{} = execution_graph) do
    # Build execution context that properly tracks active paths
    execution_context = build_execution_context_for_completion(execution, execution_graph)
    ready_nodes = find_ready_nodes(execution_graph, execution.node_executions, execution_context)

    # Workflow is complete if no more nodes are ready to execute
    Enum.empty?(ready_nodes)
  end

  # Build execution context for completion checking with proper active path reconstruction
  defp build_execution_context_for_completion(execution, execution_graph) do
    # Build active paths by analyzing completed executions
    active_paths = reconstruct_active_paths(execution.node_executions, execution_graph)

    %{
      "nodes" => extract_nodes_from_executions(execution.node_executions),
      "executed_nodes" => Enum.map(execution.node_executions, & &1.node_id),
      "active_paths" => active_paths
    }
  end

  # Reconstruct active paths from completed node executions
  defp reconstruct_active_paths(node_executions, execution_graph) do
    # For each completed node execution that has an output_port,
    # mark the paths from that node as active
    Enum.reduce(node_executions, %{}, fn node_execution, acc_paths ->
      if node_execution.output_port do
        # Find connections from this node's output port using O(1) lookup
        connections =
          get_connections_from_node_port(
            execution_graph,
            node_execution.node_id,
            node_execution.output_port
          )

        # Mark each connection path as active
        Enum.reduce(connections, acc_paths, fn connection, path_acc ->
          path_key = "#{connection.from}_#{connection.from_port}"
          Map.put(path_acc, path_key, true)
        end)
      else
        # Failed executions don't create active paths
        acc_paths
      end
    end)
  end

  # Extract node results from node executions
  defp extract_nodes_from_executions(node_executions) do
    Enum.reduce(node_executions, %{}, fn node_exec, acc ->
      result_data =
        if node_exec.status == :completed do
          %{
            "output" => node_exec.output_data,
            "context" => node_exec.context_data
          }
        else
          %{"error" => node_exec.error_data, "status" => node_exec.status}
        end

      Map.put(acc, node_exec.node_id, result_data)
    end)
  end

  # Note: Initial context creation is no longer needed with unified execution architecture

  # Complete a suspended node execution with resume data
  defp resume_suspended_node(execution_graph, suspended_execution, suspended_node_id, resume_data) do
    # Find the suspended node definition and execution
    suspended_node = Map.get(execution_graph.node_map, suspended_node_id)
    suspended_node_execution = Enum.find(suspended_execution.node_executions, &(&1.node_id == suspended_node_id))

    if suspended_node && suspended_node_execution do
      # Clear suspension state for resume (runtime state already initialized in resume_workflow)
      resume_ready_execution = Execution.resume_suspension(suspended_execution)

      # Call NodeExecutor with new unified interface
      case NodeExecutor.resume_node(suspended_node, resume_ready_execution, suspended_node_execution, resume_data) do
        {:ok, _completed_node_execution, updated_execution} ->
          {:ok, updated_execution}

        {:error, {reason, _failed_node_execution}} ->
          {:error, reason}
      end
    else
      {:error, %{type: "suspended_node_not_found", node_id: suspended_node_id}}
    end
  end

  # Prepare all workflow actions during the preparation phase.
  # Scans all nodes in the workflow, calls prepare/1 on each action module,
  # and stores the preparation data in the execution struct.
  defp prepare_workflow_actions(execution_graph, execution) do
    # Prepare all actions and collect preparation data
    case prepare_all_actions(execution_graph.workflow.nodes) do
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
          updated_prep_data = Map.put(acc_prep_data, node.custom_id, node_prep_data)
          {:cont, {:ok, updated_prep_data}}

        {:error, reason} ->
          {:halt, {:error, %{type: "action_preparation_failed", node_id: node.id, reason: reason}}}
      end
    end)

    # Store preparation data using node custom_id
  end

  # Prepare a single action
  defp prepare_single_action(node) do
    # Look up action from integration registry
    case Prana.IntegrationRegistry.get_action(node.integration_name, node.action_name) do
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
            {:error, %{type: "preparation_exception", message: Exception.message(error)}}
        end

      {:error, _reason} ->
        # Action not found in registry, return empty preparation data
        {:ok, nil}
    end
  end

  # Extract multi-port input data for a node by computing routing from execution graph and runtime state
  # Returns a map with port names as keys and routed data as values
  defp extract_multi_port_input(node, execution_graph, execution) do
    # Get input ports from the action definition, not the node
    input_ports = case get_action_input_ports(node) do
      {:ok, ports} -> ports
      _error -> ["input"]  # fallback to default
    end

    # Build multi-port input map: port_name => routed_data
    multi_port_input =
      Enum.reduce(input_ports, %{}, fn input_port, acc ->
        # Find all connections that target this node's input port
        incoming_connections = get_incoming_connections_for_node_port(execution_graph, node.id, input_port)

        # Collect data from all connections targeting this port
        port_data =
          Enum.reduce(incoming_connections, nil, fn connection, _acc ->
            # Get the structured node data and extract output
            source_node_data = execution.__runtime["nodes"][connection.from]
            if source_node_data, do: source_node_data["output"]
          end)

        if port_data do
          Map.put(acc, input_port, port_data)
        else
          acc
        end
      end)

    multi_port_input
  end

  # Get input ports from the action definition
  defp get_action_input_ports(node) do
    case Prana.IntegrationRegistry.get_action(node.integration_name, node.action_name) do
      {:ok, action} ->
        {:ok, action.input_ports || ["input"]}
      
      {:error, _reason} ->
        {:error, :action_not_found}
    end
  end

  # Get incoming connections for a specific node and port
  defp get_incoming_connections_for_node_port(execution_graph, node_id, input_port) do
    # Use reverse connection map for O(1) lookup (exists after proper compilation)
    # For manually created ExecutionGraphs in tests, fall back to empty list
    reverse_map = Map.get(execution_graph, :reverse_connection_map, %{})
    all_incoming = Map.get(reverse_map, node_id, [])

    # Filter for connections targeting the specific input port
    Enum.filter(all_incoming, fn conn -> conn.to_port == input_port end)
  end
end
