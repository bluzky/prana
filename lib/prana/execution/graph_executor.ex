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
      "nodes" => %{node_key => output_data},     # completed node outputs
      "env" => map(),                           # environment data
      "active_nodes" => MapSet.t(String.t()),   # nodes ready for execution
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
    prepared_execution = Execution.rebuild_runtime(%{suspended_execution | execution_graph: execution_graph}, env_data)

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
    execution = Execution.new(execution_graph, "graph_executor", execution_graph.variables)
    execution = Execution.start(execution)

    # Initialize runtime state once at the start of execution
    env_data = Map.get(context, :env, %{})
    execution = Execution.rebuild_runtime(execution, env_data)

    # For new executions, initialize active_nodes with trigger node and node_depth map
    active_nodes = MapSet.new([execution_graph.trigger_node_key])
    node_depth = %{execution_graph.trigger_node_key => 0}

    execution =
      execution
      |> put_in([Access.key(:__runtime), "active_nodes"], active_nodes)
      |> put_in([Access.key(:__runtime), "node_depth"], node_depth)

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
          failed_execution = Execution.fail(execution)
          Middleware.call(:execution_failed, %{execution: failed_execution, reason: reason})
          {:error, failed_execution}
      end
    rescue
      error ->
        reason = %{type: "execution_exception", message: Exception.message(error), details: %{}}
        failed_execution = Execution.fail(execution)
        Middleware.call(:execution_failed, %{execution: failed_execution, reason: reason})
        {:error, failed_execution}
    end
  end

  # Main workflow execution loop - continues until workflow is complete or error occurs.
  # Uses Execution.__runtime for all workflow-level coordination.
  defp execute_workflow_loop(execution, execution_graph) do
    # Check for infinite loop protection
    # Note: iteration_count is persisted in metadata to survive suspension/resume cycles
    iteration_count = execution.__runtime["iteration_count"] || 0
    max_iterations = execution.__runtime["max_iterations"] || 100

    if iteration_count >= max_iterations do
      failed_execution = Execution.fail(execution)
      {:error, failed_execution}
    else
      # Increment iteration counter in both runtime and persistent metadata
      new_count = iteration_count + 1

      execution =
        execution
        |> put_in([Access.key(:__runtime), "iteration_count"], new_count)
        |> put_in([Access.key(:metadata), "iteration_count"], new_count)

      # Get active nodes from runtime state
      active_nodes = execution.__runtime["active_nodes"] || MapSet.new()

      # Continue execution with updated state
      # Note: Execution.__runtime is updated internally by NodeExecutor

      if MapSet.size(active_nodes) == 0 do
        final_execution = Execution.complete(execution)
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
  end

  # Find ready nodes and execute following branch-completion strategy.
  # Uses Execution.__runtime for tracking active paths and executed nodes.
  defp find_and_execute_ready_nodes(execution, execution_graph) do
    ready_nodes =
      find_ready_nodes(execution_graph, execution.node_executions, execution.__runtime)

    if Enum.empty?(ready_nodes) do
      # No ready nodes but workflow not complete - likely an error condition
      failed_execution = Execution.fail(execution)
      {:error, failed_execution}
    else
      # Select single node to execute, prioritizing branch completion
      selected_node = select_node_for_branch_following(ready_nodes, execution.__runtime)

      case execute_single_node_with_events(selected_node, execution_graph, execution) do
        {%NodeExecution{status: :completed} = node_execution, updated_execution} ->
          # Output routing and context updates are now handled internally by NodeExecutor
          # and the Execution.complete_node/2 function
          # Update active_nodes based on completed node's outputs
          final_execution =
            Execution.update_active_nodes_on_completion(
              updated_execution,
              selected_node.key,
              node_execution.output_port,
              execution_graph
            )

          {:ok, final_execution}

        {%NodeExecution{status: :suspended} = node_execution, updated_execution} ->
          # Extract suspension information from NodeExecution fields
          suspension_type = node_execution.suspension_type || :sub_workflow
          suspend_data = node_execution.suspension_data || %{}

          # Suspend the entire execution with structured suspension data
          suspended_execution =
            Execution.suspend(updated_execution, selected_node.key, suspension_type, suspend_data)

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
            |> Execution.fail()

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
  @spec select_node_for_branch_following([Node.t()], map()) :: Node.t()
  def select_node_for_branch_following(ready_nodes, execution_context) do
    node_depth = Map.get(execution_context, "node_depth", %{})

    # Sort nodes by depth (deepest first) to ensure branch following
    ready_nodes
    |> Enum.sort_by(fn node ->
      depth = Map.get(node_depth, node.key, 0)
      # Use negative depth for descending sort (deepest first)
      -depth
    end)
    |> List.first()
  end

  # This function is no longer needed with depth-based approach
  # defp node_continues_active_branch? - removed

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
  @spec find_ready_nodes(ExecutionGraph.t(), map(), map()) :: [Node.t()]
  def find_ready_nodes(%ExecutionGraph{} = execution_graph, node_executions, execution_context) do
    # Get active nodes from execution context
    active_nodes = execution_context["active_nodes"] || MapSet.new()

    # Extract completed node IDs from map structure for dependency checking
    completed_node_ids =
      node_executions
      |> Enum.map(fn {node_key, executions} -> {node_key, List.last(executions)} end)
      |> Enum.filter(fn {_, exec} -> exec.status == :completed end)
      |> MapSet.new(fn {node_key, _} -> node_key end)

    # Only check active nodes instead of all nodes
    active_nodes
    |> Enum.map(fn node_key -> execution_graph.node_map[node_key] end)
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(fn node ->
      dependencies_satisfied?(node, execution_graph, completed_node_ids)
    end)
  end

  # Check if all input ports for a node are satisfied (port-based logic)
  defp dependencies_satisfied?(node, execution_graph, completed_node_ids) do
    # Get input ports for this node
    input_ports =
      case Execution.get_action_input_ports(node) do
        {:ok, ports} -> ports
        # fallback to default
        _error -> ["input"]
      end

    # For each input port, check if at least one source connection is satisfied
    Enum.all?(input_ports, fn input_port ->
      input_port_satisfied?(node.key, input_port, execution_graph, completed_node_ids)
    end)
  end

  # Check if a specific input port is satisfied (at least one source available)
  defp input_port_satisfied?(node_key, input_port, execution_graph, completed_node_ids) do
    # Get all incoming connections for this node and port
    incoming_connections = Execution.get_incoming_connections_for_node_port(execution_graph, node_key, input_port)

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

  # Execute a single node with middleware events using unified execution architecture
  defp execute_single_node_with_events(node, execution_graph, execution) do
    # Extract multi-port input data for this node from execution graph and runtime state
    routed_input = Execution.extract_multi_port_input(node, execution_graph, execution)

    # Get execution tracking indices
    execution_index = execution.current_execution_index
    run_index = Execution.get_next_run_index(execution, node.key)

    # Emit node starting event
    Middleware.call(:node_starting, %{node: node, execution: execution})

    # Execute the node using the new tracking interface
    case NodeExecutor.execute_node(node, execution, routed_input, execution_index, run_index) do
      {:ok, result_node_execution, updated_execution} ->
        # Increment execution index for next node
        final_execution = %{updated_execution | current_execution_index: execution_index + 1}
        Middleware.call(:node_completed, %{node: node, node_execution: result_node_execution})
        {result_node_execution, final_execution}

      {:suspend, suspended_node_execution} ->
        # Handle node suspension - emit middleware event for application handling
        Middleware.call(:node_suspended, %{
          node: node,
          node_execution: suspended_node_execution,
          suspension_type: suspended_node_execution.suspension_type,
          suspend_data: suspended_node_execution.suspension_data
        })

        # Increment execution index and add suspended node to execution
        final_execution = %{execution | current_execution_index: execution_index + 1}
        updated_execution = Execution.add_node_execution_to_map(final_execution, suspended_node_execution)
        {suspended_node_execution, updated_execution}

      {:error, {_reason, error_node_execution}} ->
        Middleware.call(:node_failed, %{node: node, node_execution: error_node_execution})
        # Increment execution index and add failed node to execution
        final_execution = %{execution | current_execution_index: execution_index + 1}
        updated_execution = Execution.add_node_execution_to_map(final_execution, error_node_execution)
        {error_node_execution, updated_execution}
    end
  end

  # Complete a suspended node execution with resume data
  defp resume_suspended_node(execution_graph, suspended_execution, suspended_node_id, resume_data) do
    # Find the suspended node definition and execution
    suspended_node = Map.get(execution_graph.node_map, suspended_node_id)

    # Find the suspended node execution from the map structure
    suspended_node_executions = Map.get(suspended_execution.node_executions, suspended_node_id, [])
    suspended_node_execution = Enum.find(suspended_node_executions, &(&1.status == :suspended))

    if suspended_node && suspended_node_execution do
      # Clear suspension state for resume (runtime state already initialized in resume_workflow)
      resume_ready_execution = Execution.resume_suspension(suspended_execution)

      # Call NodeExecutor with new unified interface
      case NodeExecutor.resume_node(suspended_node, resume_ready_execution, suspended_node_execution, resume_data) do
        {:ok, completed_node_execution, updated_execution} ->
          # Update active nodes based on completed node's outputs
          final_execution =
            Execution.update_active_nodes_on_completion(
              updated_execution,
              suspended_node_id,
              completed_node_execution.output_port,
              execution_graph
            )

          {:ok, final_execution}

        {:error, {reason, _failed_node_execution}} ->
          {:error, reason}
      end
    else
      {:error, %{type: "suspended_node_not_found", node_key: suspended_node_id}}
    end
  end

  # Prepare all workflow actions during the preparation phase.
  # Scans all nodes in the workflow, calls prepare/1 on each action module,
  # and stores the preparation data in the execution struct.
  defp prepare_workflow_actions(execution_graph, execution) do
    # Prepare all actions and collect preparation data
    case prepare_all_actions(Map.values(execution_graph.node_map)) do
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
          {:halt, {:error, %{type: "action_preparation_failed", node_key: node.key, reason: reason}}}
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
end
