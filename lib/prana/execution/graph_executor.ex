defmodule Prana.GraphExecutor do
  @moduledoc """
  GraphExecutor: Branch-Following Workflow Execution Engine

  Orchestrates workflow execution using pre-compiled ExecutionGraphs from WorkflowCompiler.
  Implements branch-following execution strategy that prioritizes completing active execution
  paths before starting new branches, providing predictable and efficient workflow execution.

  ## Primary API

      execute_graph(execution_graph, input_data, context \\ %{})
        :: {:ok, Execution.t()} | {:error, reason}

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
  - Uses `NodeExecutor.execute_node/3` for individual node execution
  - Uses `ExpressionEngine.process_map/2` for input preparation (via NodeExecutor)
  - Uses `Middleware.call/2` for lifecycle events
  - Uses `ExecutionContext` for shared state management

  ## Context Types Used

  This module uses TWO different context structures for different purposes:

  ### OrchestrationContext
  ```elixir
  %{
    "input" => map(),           # Workflow input data
    "variables" => map(),       # Workflow variables
    "nodes" => map(),          # Completed node results
    "executed_nodes" => [binary()],  # List of executed node IDs
    "active_paths" => map()     # Active conditional paths
  }
  ```
  - **Purpose**: Workflow orchestration, data routing, conditional branching
  - **Keys**: String keys for expression engine compatibility (`$input.field`)
  - **Used by**: GraphExecutor internal functions

  ### ExecutionContext (struct)
  ```elixir
  %ExecutionContext{
    workflow: Workflow.t(),
    execution: Execution.t(),
    nodes: map(),             # Node results (for expressions)
    variables: map()          # Variables (for expressions)
  }
  ```
  - **Purpose**: Individual node execution and expression evaluation
  - **Keys**: Atom keys for compile-time validation
  - **Used by**: NodeExecutor.execute_node/3

  ### Conversion Point

  The conversion happens in `execute_single_node_with_events/3`:
  `OrchestrationContext` → `ExecutionContext` → `NodeExecutor.execute_node/3`
  """

  alias Prana.Execution
  alias Prana.ExecutionContext
  alias Prana.ExecutionGraph
  alias Prana.Middleware
  alias Prana.Node
  alias Prana.NodeExecution
  alias Prana.NodeExecutor

  require Logger

  # Type alias for clarity in function signatures
  @type orchestration_context :: %{
          required(String.t()) => any()
        }

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
    # Find the suspended node and complete it with the resume data
    suspended_node_id = suspended_execution.suspended_node_id

    if suspended_node_id do
      # Resume the suspended node execution using NodeExecutor
      case resume_suspended_node(execution_graph, suspended_execution, suspended_node_id, resume_data, execution_context) do
        {:ok, {updated_execution, updated_context}} ->
          # Node resumed successfully, continue execution (same pattern as main loop)
          execute_workflow_loop(updated_execution, execution_graph, updated_context)

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
  Execute a workflow graph with the given input data and context.

  ## Parameters

  - `execution_graph` - Pre-compiled ExecutionGraph from WorkflowCompiler
  - `input_data` - Initial input data for the workflow
  - `context` - Execution context with workflow_loader callback and optional variables/metadata

  ## Returns

  - `{:ok, execution}` - Successful execution with final state
  - `{:suspend, execution}` - Execution suspended for async coordination (sub-workflows, external events, etc.)
  - `{:error, reason}` - Execution failed with error details

  ## Examples

      context = %{
        workflow_loader: &MyApp.WorkflowLoader.load_workflow/1,
        variables: %{api_url: "https://api.example.com"},
        metadata: %{user_id: 123}
      }

      # Normal execution
      {:ok, execution} = GraphExecutor.execute_graph(graph, %{email: "user@example.com"}, context)

      # Suspended execution (sub-workflow coordination)
      {:suspend, execution} = GraphExecutor.execute_graph(graph, %{workflow_id: "child"}, context)
  """
  @spec execute_graph(ExecutionGraph.t(), map(), map()) ::
          {:ok, Execution.t()} | {:suspend, Execution.t()} | {:error, any()}
  def execute_graph(%ExecutionGraph{} = execution_graph, input_data, context \\ %{}) do
    # Create initial execution and context
    execution = Execution.new(execution_graph.workflow.id, 1, "graph_executor", input_data)
    execution = Execution.start(execution)
    orchestration_context = create_initial_orchestration_context(input_data, context)

    # Emit execution started event
    Middleware.call(:execution_started, %{execution: execution})

    try do
      # Main execution loop
      case execute_workflow_loop(execution, execution_graph, orchestration_context) do
        {:ok, final_execution} ->
          Middleware.call(:execution_completed, %{execution: final_execution})
          {:ok, final_execution}

        {:suspend, suspended_execution} ->
          # Workflow suspended for async coordination - return suspended execution
          {:suspend, suspended_execution}

        {:error, reason} = error ->
          failed_execution = Execution.fail(execution, reason)
          Middleware.call(:execution_failed, %{execution: failed_execution, reason: reason})
          error
      end
    rescue
      error ->
        reason = %{type: "execution_exception", message: Exception.message(error), details: %{}}
        failed_execution = Execution.fail(execution, reason)
        Middleware.call(:execution_failed, %{execution: failed_execution, reason: reason})
        {:error, reason}
    end
  end

  # Main workflow execution loop - continues until workflow is complete or error occurs.
  # Uses OrchestrationContext (simple map with string keys) for workflow-level coordination.
  defp execute_workflow_loop(execution, execution_graph, orchestration_context) do
    if workflow_complete?(execution, execution_graph) do
      final_execution = Execution.complete(execution, %{})
      {:ok, final_execution}
    else
      case find_and_execute_ready_nodes(execution, execution_graph, orchestration_context) do
        {:ok, {updated_execution, updated_orchestration_context}} ->
          execute_workflow_loop(updated_execution, execution_graph, updated_orchestration_context)

        {:suspend, suspended_execution} ->
          # Workflow execution suspended - return suspended execution for application handling
          {:suspend, suspended_execution}

        {:error, _reason} = error ->
          error
      end
    end
  end

  # Find ready nodes and execute following branch-completion strategy.
  # Uses OrchestrationContext for tracking active paths and executed nodes.
  defp find_and_execute_ready_nodes(execution, execution_graph, orchestration_context) do
    ready_nodes = find_ready_nodes(execution_graph, execution.node_executions, orchestration_context)

    if Enum.empty?(ready_nodes) do
      # No ready nodes but workflow not complete - likely an error condition
      {:error, %{type: "execution_stalled", message: "No ready nodes found but workflow not complete"}}
    else
      # Select single node to execute, prioritizing branch completion
      selected_node = select_node_for_branch_following(ready_nodes, execution_graph, orchestration_context)

      case execute_single_node_with_events(selected_node, execution_graph, orchestration_context, execution) do
        %NodeExecution{status: :completed} = node_execution ->
          # Update execution with completed node execution
          updated_execution = update_execution_progress(execution, [node_execution])

          # Route output data and update orchestration context immediately
          updated_orchestration_context = route_node_output(node_execution, execution_graph, orchestration_context)
          updated_orchestration_context = store_node_result_in_context(node_execution, updated_orchestration_context, selected_node)

          {:ok, {updated_execution, updated_orchestration_context}}

        %NodeExecution{status: :suspended} = node_execution ->
          # Node suspended for async coordination - pause workflow execution
          updated_execution = update_execution_progress(execution, [node_execution])

          # Suspend the entire execution and emit middleware event for application handling
          # TODO: Phase 2 - Update to use proper suspension types and data
          suspension_data = %{
            suspended_node_id: selected_node.id,
            suspension_metadata: node_execution.metadata
          }
          
          suspended_execution =
            Execution.suspend(updated_execution, selected_node.id, :sub_workflow, suspension_data)

          Middleware.call(:execution_suspended, %{
            execution: suspended_execution,
            suspended_node: selected_node,
            node_execution: node_execution
          })

          {:suspend, suspended_execution}

        %NodeExecution{status: :failed} = node_execution ->
          # Node failed, return error
          _updated_execution = update_execution_progress(execution, [node_execution])
          _updated_orchestration_context = store_node_result_in_context(node_execution, orchestration_context)

          {:error,
           %{
             type: "node_execution_failed",
             message: "Node #{selected_node.id} failed during execution",
             node_id: selected_node.id,
             node_execution: node_execution,
             error_data: node_execution.error_data
           }}

        %NodeExecution{} = node_execution ->
          # Node finished with other status
          updated_execution = update_execution_progress(execution, [node_execution])
          updated_orchestration_context = store_node_result_in_context(node_execution, orchestration_context)

          {:ok, {updated_execution, updated_orchestration_context}}
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

  # Execute a single node with middleware events.
  # Critical Context Conversion Point: OrchestrationContext → ExecutionContext
  defp execute_single_node_with_events(node, execution_graph, orchestration_context, execution) do
    # Extract routed input data for this node from connection routing
    node_input = extract_node_input_from_routing(node, orchestration_context)

    # CONTEXT CONVERSION: OrchestrationContext → ExecutionContext
    # Convert our OrchestrationContext (string keys) to ExecutionContext struct (atom keys)

    node_execution_context =
      ExecutionContext.new(execution_graph.workflow, execution, %{
        # Use routed input data for this specific node
        input: node_input,
        nodes: Map.get(orchestration_context, "nodes", %{}),
        variables: Map.get(orchestration_context, "variables", %{})
      })

    # Emit node starting event (NodeExecutor will create and manage NodeExecution)
    Middleware.call(:node_starting, %{node: node, execution: execution})

    # Execute the node using ExecutionContext struct (atom keys)
    case NodeExecutor.execute_node(node, node_execution_context) do
      {:ok, result_node_execution, _updated_context} ->
        Middleware.call(:node_completed, %{node: node, node_execution: result_node_execution})
        result_node_execution

      {:suspend, suspension_type, suspend_data, suspended_node_execution} ->
        # Handle node suspension - emit middleware event for application handling
        Middleware.call(:node_suspended, %{
          node: node,
          node_execution: suspended_node_execution,
          suspension_type: suspension_type,
          suspend_data: suspend_data
        })

        suspended_node_execution

      {:error, {_reason, error_node_execution}} ->
        Middleware.call(:node_failed, %{node: node, node_execution: error_node_execution})
        error_node_execution
    end
  end

  @doc """
  Route output data from completed nodes to dependent nodes based on ports.

  Uses ExecutionGraph.connections to determine data flow paths. For successful
  node executions, routes output data to connected nodes. Failed nodes
  (output_port = nil) do not route data.

  ## Context Usage

  This function operates on OrchestrationContext (string keys) for workflow
  data routing and conditional path activation.

  ## Parameters

  - `node_execution` - Completed NodeExecution with output data and port
  - `execution_graph` - ExecutionGraph containing connections
  - `orchestration_context` - Current orchestration context to update (string keys)

  ## Returns

  Updated OrchestrationContext with routed data and active paths.
  """
  @spec route_node_output(NodeExecution.t(), ExecutionGraph.t(), map()) :: map()
  def route_node_output(%NodeExecution{} = node_execution, %ExecutionGraph{} = execution_graph, orchestration_context) do
    # Only route output for successful executions (output_port is not nil)
    if node_execution.output_port do
      # Find connections from this node's output port using O(1) lookup
      connections =
        get_connections_from_node_port(
          execution_graph,
          node_execution.node_id,
          node_execution.output_port
        )

      # Route data through each connection
      Enum.reduce(connections, orchestration_context, fn connection, acc_orchestration_context ->
        route_data_through_connection(node_execution, connection, acc_orchestration_context)
      end)
    else
      # Failed nodes don't route data, but store their result in context
      store_node_result_in_context(node_execution, orchestration_context)
    end
  end

  # Get connections from a specific node and port using O(1) lookup
  defp get_connections_from_node_port(execution_graph, node_id, output_port) do
    Map.get(execution_graph.connection_map, {node_id, output_port}, [])
  end

  # Route data through a single connection with optimized context updates.
  defp route_data_through_connection(node_execution, connection, orchestration_context) do
    routed_data = node_execution.output_data

    # Store routed data in context for the target node
    target_input_key = "#{connection.to}_#{connection.to_port}"

    # Mark this conditional path as active for branching logic
    path_key = "#{connection.from}_#{connection.from_port}"

    # Batch context updates to reduce map copying
    orchestration_context
    |> Map.put(target_input_key, routed_data)
    |> Map.update("active_paths", %{path_key => true}, &Map.put(&1, path_key, true))
  end

  # Store node execution result in orchestration context for $nodes.node_id access.
  defp store_node_result_in_context(node_execution, orchestration_context, node \\ nil) do
    # Use custom_id if node is provided, otherwise fallback to node_id for backward compatibility
    node_key = if node, do: node.custom_id, else: node_execution.node_id

    result_data =
      if node_execution.status == :completed do
        node_execution.output_data
      else
        %{"error" => node_execution.error_data, "status" => node_execution.status}
      end

    # Batch context updates to reduce map copying
    orchestration_context
    |> Map.update("nodes", %{node_key => result_data}, &Map.put(&1, node_key, result_data))
    |> Map.update("executed_nodes", [node_execution.node_id], &[node_execution.node_id | &1])
  end


  @doc """
  Update execution progress with completed node executions.

  Adds the completed node executions to the main execution tracking
  and updates execution statistics.

  ## Parameters

  - `execution` - Current Execution struct
  - `completed_node_executions` - List of newly completed NodeExecution structs

  ## Returns

  Updated Execution struct with progress tracking.
  """
  @spec update_execution_progress(Execution.t(), [NodeExecution.t()]) :: Execution.t()
  def update_execution_progress(%Execution{} = execution, completed_node_executions) do
    updated_executions = execution.node_executions ++ completed_node_executions
    %{execution | node_executions: updated_executions}
  end

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
          node_exec.output_data
        else
          %{"error" => node_exec.error_data, "status" => node_exec.status}
        end

      Map.put(acc, node_exec.node_id, result_data)
    end)
  end

  # Create initial orchestration context for workflow execution.
  # Creates OrchestrationContext (string keys) for workflow orchestration.
  @spec create_initial_orchestration_context(map(), map()) :: map()
  defp create_initial_orchestration_context(input_data, external_context) do
    # Create orchestration context with string keys for expression engine compatibility
    # This is NOT the same as ExecutionContext struct used by NodeExecutor
    %{
      "input" => input_data,
      "variables" => Map.get(external_context, :variables, %{}),
      "metadata" => Map.get(external_context, :metadata, %{}),
      "nodes" => %{},
      "executed_nodes" => [],
      "active_paths" => %{}
    }
  end

  # Complete a suspended node execution with resume data
  defp resume_suspended_node(execution_graph, suspended_execution, suspended_node_id, resume_data, execution_context) do
    # Find the suspended node definition and execution
    suspended_node = Map.get(execution_graph.node_map, suspended_node_id)
    suspended_node_execution = Enum.find(suspended_execution.node_executions, &(&1.node_id == suspended_node_id))

    if suspended_node && suspended_node_execution do
      # Create ExecutionContext for resume
      node_execution_context =
        ExecutionContext.new(execution_graph.workflow, suspended_execution, %{
          input: extract_node_input_from_routing(suspended_node, execution_context),
          nodes: Map.get(execution_context, "nodes", %{}),
          variables: Map.get(execution_context, "variables", %{})
        })

      # Call NodeExecutor to handle resume
      case NodeExecutor.resume_node(suspended_node, node_execution_context, suspended_node_execution, resume_data) do
        {:ok, completed_node_execution, _updated_context} ->
          # Update node_executions list with completed execution
          updated_executions =
            Enum.map(suspended_execution.node_executions, fn node_exec ->
              if node_exec.node_id == suspended_node_id do
                completed_node_execution
              else
                node_exec
              end
            end)

          # Build complete execution and context like find_and_execute_ready_nodes does
          updated_execution = %{
            suspended_execution
            | status: :running,
              node_executions: updated_executions,
              resume_token: nil
          }

          # Handle context updates exactly like regular execution flow
          updated_context = route_node_output(completed_node_execution, execution_graph, execution_context)
          updated_context = store_node_result_in_context(completed_node_execution, updated_context, suspended_node)

          {:ok, {updated_execution, updated_context}}

        {:error, {reason, failed_node_execution}} ->
          {:error, %{type: "resume_failed", reason: reason, node_execution: failed_node_execution}}
      end
    else
      {:error, %{type: "suspended_node_not_found", node_id: suspended_node_id}}
    end
  end


  # Extract input data for a specific node from routed connection data
  # This function looks for data routed to this node via connections and prepares
  # it as the input data for expression evaluation
  defp extract_node_input_from_routing(node, execution_context) do
    # Handle case where input_ports might be nil
    # Default to "input" port
    input_ports = node.input_ports || ["input"]

    # Look for routed data using the connection target key format
    # For a node with input ports, check if data has been routed to any of its ports
    routed_data =
      Enum.reduce(input_ports, %{}, fn input_port, acc ->
        routed_data_key = "#{node.id}_#{input_port}"

        case Map.get(execution_context, routed_data_key) do
          nil -> acc
          data when is_map(data) -> Map.merge(acc, data)
          data -> Map.put(acc, input_port, data)
        end
      end)

    case routed_data do
      empty when map_size(empty) == 0 ->
        # No routed data found, use workflow input (for trigger nodes)
        Map.get(execution_context, "input", %{})

      _ ->
        routed_data
    end
  end
end
