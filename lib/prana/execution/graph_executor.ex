defmodule Prana.GraphExecutor do
  @moduledoc """
  GraphExecutor Phase 1: Core Execution (Sync/Fire-and-Forget Only)

  Orchestrates workflow execution using pre-compiled ExecutionGraphs from WorkflowCompiler.
  Handles parallel node execution, port-based data routing, context management, and
  sub-workflow execution in sync and fire-and-forget modes.

  ## Primary API

      execute_graph(execution_graph, input_data, context \\ %{})
        :: {:ok, Execution.t()} | {:error, reason}

  ## Required Context Structure

      context = %{
        workflow_loader: (workflow_id -> {:ok, ExecutionGraph.t()} | {:error, reason}),
        variables: %{},     # optional
        metadata: %{}       # optional
      }

  ## Core Features

  - Graph execution orchestration with dependency-based ordering
  - Parallel execution of independent nodes using Tasks
  - Port-based data routing between nodes
  - Context management with node result storage
  - Sub-workflow support (sync and fire-and-forget modes)
  - Middleware event emission during execution
  - Comprehensive error handling and propagation

  ## Integration Points

  - Uses `WorkflowCompiler` compiled ExecutionGraphs
  - Uses `NodeExecutor.execute_node/3` for individual node execution
  - Uses `ExpressionEngine.process_map/2` for input preparation
  - Uses `Middleware.call/2` for lifecycle events
  - Uses `ExecutionContext` for shared state management
  """

  alias Prana.Execution
  alias Prana.ExecutionContext
  alias Prana.ExecutionGraph
  alias Prana.ExpressionEngine
  alias Prana.Middleware
  alias Prana.Node
  alias Prana.NodeExecution
  alias Prana.NodeExecutor

  require Logger

  @doc """
  Execute a workflow graph with the given input data and context.

  ## Parameters

  - `execution_graph` - Pre-compiled ExecutionGraph from WorkflowCompiler
  - `input_data` - Initial input data for the workflow
  - `context` - Execution context with workflow_loader callback and optional variables/metadata

  ## Returns

  - `{:ok, execution}` - Successful execution with final state
  - `{:error, reason}` - Execution failed with error details

  ## Examples

      context = %{
        workflow_loader: &MyApp.WorkflowLoader.load_workflow/1,
        variables: %{api_url: "https://api.example.com"},
        metadata: %{user_id: 123}
      }

      {:ok, execution} = GraphExecutor.execute_graph(graph, %{email: "user@example.com"}, context)
  """
  @spec execute_graph(ExecutionGraph.t(), map(), map()) :: {:ok, Execution.t()} | {:error, any()}
  def execute_graph(%ExecutionGraph{} = execution_graph, input_data, context \\ %{}) do
    # Create initial execution and context
    execution = Execution.new(execution_graph.workflow.id, 1, "graph_executor", input_data)
    execution = Execution.start(execution)
    execution_context = create_initial_context(input_data, context)

    # Emit execution started event
    Middleware.call(:execution_started, %{execution: execution})

    try do
      # Main execution loop
      case execute_workflow_loop(execution, execution_graph, execution_context) do
        {:ok, final_execution} ->
          Middleware.call(:execution_completed, %{execution: final_execution})
          {:ok, final_execution}

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

  # Main execution loop - continues until workflow is complete or error occurs
  defp execute_workflow_loop(execution, execution_graph, execution_context) do
    if workflow_complete?(execution, execution_graph) do
      final_execution = Execution.complete(execution, %{})
      {:ok, final_execution}
    else
      case find_and_execute_ready_nodes(execution, execution_graph, execution_context) do
        {:ok, {updated_execution, updated_context}} ->
          execute_workflow_loop(updated_execution, execution_graph, updated_context)

        {:error, _reason} = error ->
          error
      end
    end
  end

  # Find ready nodes and execute them in parallel
  defp find_and_execute_ready_nodes(execution, execution_graph, execution_context) do
    ready_nodes = find_ready_nodes(execution_graph, execution.node_executions, execution_context)

    if Enum.empty?(ready_nodes) do
      # No ready nodes but workflow not complete - likely an error condition
      {:error, %{type: "execution_stalled", message: "No ready nodes found but workflow not complete"}}
    else
      case execute_nodes_batch(ready_nodes, execution_graph, execution_context) do
        {:ok, node_executions} ->
          # Update execution with completed node executions
          updated_execution = update_execution_progress(execution, node_executions)

          # Route output data and update context
          updated_context = route_batch_outputs(node_executions, execution_graph, execution_context)

          {:ok, {updated_execution, updated_context}}

        {:error, _reason} = error ->
          error
      end
    end
  end

  @doc """
  Find nodes that are ready to execute based on their dependencies.

  A node is ready if:
  1. It hasn't been executed yet (not in completed node executions)
  2. All its input dependencies have been satisfied
  3. It's reachable from completed nodes or is an entry node

  ## Parameters

  - `execution_graph` - The ExecutionGraph containing nodes and dependencies
  - `completed_node_executions` - List of completed NodeExecution structs
  - `execution_context` - Current execution context

  ## Returns

  List of Node structs that are ready for execution.
  """
  @spec find_ready_nodes(ExecutionGraph.t(), [NodeExecution.t()], map()) :: [Node.t()]
  def find_ready_nodes(%ExecutionGraph{} = execution_graph, completed_node_executions, _execution_context) do
    completed_node_ids = MapSet.new(completed_node_executions, & &1.node_id)

    execution_graph.workflow.nodes
    |> Enum.reject(fn node -> MapSet.member?(completed_node_ids, node.id) end)
    |> Enum.filter(fn node ->
      dependencies_satisfied?(node, execution_graph.dependency_graph, completed_node_ids)
    end)
  end

  # Check if all dependencies for a node are satisfied
  defp dependencies_satisfied?(node, dependencies, completed_node_ids) do
    node_dependencies = Map.get(dependencies, node.id, [])

    Enum.all?(node_dependencies, fn dep_node_id ->
      MapSet.member?(completed_node_ids, dep_node_id)
    end)
  end

  @doc """
  Execute a batch of nodes in parallel using Tasks.

  Each node is executed using NodeExecutor.execute_node/3. Nodes are executed
  concurrently where possible, with proper error handling and task coordination.

  ## Parameters

  - `ready_nodes` - List of Node structs ready for execution
  - `execution_graph` - The ExecutionGraph for context
  - `execution_context` - Current execution context

  ## Returns

  - `{:ok, node_executions}` - List of completed NodeExecution structs
  - `{:error, reason}` - Execution failed
  """
  @spec execute_nodes_batch([Node.t()], ExecutionGraph.t(), map()) ::
          {:ok, [NodeExecution.t()]} | {:error, any()}
  def execute_nodes_batch(ready_nodes, execution_graph, execution_context) do
    if Enum.empty?(ready_nodes) do
      {:ok, []}
    else
      # Execute nodes in parallel using async tasks
      tasks =
        Enum.map(ready_nodes, fn node ->
          Task.async(fn ->
            execute_single_node_with_events(node, execution_graph, execution_context)
          end)
        end)

      # Wait for all tasks to complete and collect results
      try do
        node_executions = Task.await_many(tasks, :infinity)
        {:ok, node_executions}
      rescue
        error ->
          # Clean up any remaining tasks
          Enum.each(tasks, &Task.shutdown(&1, :brutal_kill))
          {:error, %{type: "parallel_execution_failed", message: Exception.message(error)}}
      end
    end
  end

  # Execute a single node with middleware events
  defp execute_single_node_with_events(node, execution_graph, execution_context) do
    # Convert our simple map context to ExecutionContext struct
    # We need a temporary workflow and execution for the ExecutionContext
    temp_execution = Execution.new(execution_graph.workflow.id, 1, "temp", Map.get(execution_context, "input", %{}))
    context_struct = ExecutionContext.new(execution_graph.workflow, temp_execution, %{
      nodes: Map.get(execution_context, "nodes", %{}),
      variables: Map.get(execution_context, "variables", %{})
    })
    
    # Create node execution and emit started event
    node_execution = NodeExecution.new(temp_execution.id, node.id, %{})
    node_execution = NodeExecution.start(node_execution)
    
    Middleware.call(:node_started, %{node: node, node_execution: node_execution})

    # Execute the node
    case NodeExecutor.execute_node(node, context_struct, %{}) do
      {:ok, result_node_execution, _updated_context} ->
        Middleware.call(:node_completed, %{node: node, node_execution: result_node_execution})
        result_node_execution

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

  ## Parameters

  - `node_execution` - Completed NodeExecution with output data and port
  - `execution_graph` - ExecutionGraph containing connections
  - `execution_context` - Current execution context to update

  ## Returns

  Updated ExecutionContext with routed data.
  """
  @spec route_node_output(NodeExecution.t(), ExecutionGraph.t(), map()) :: map()
  def route_node_output(%NodeExecution{} = node_execution, %ExecutionGraph{} = execution_graph, execution_context) do
    # Only route output for successful executions (output_port is not nil)
    if node_execution.output_port do
      # Find connections from this node's output port
      connections =
        get_connections_from_node_port(
          execution_graph.workflow.connections,
          node_execution.node_id,
          node_execution.output_port
        )

      # Route data through each connection
      Enum.reduce(connections, execution_context, fn connection, acc_context ->
        route_data_through_connection(node_execution, connection, acc_context)
      end)
    else
      # Failed nodes don't route data, but store their result in context
      store_node_result_in_context(node_execution, execution_context)
    end
  end

  # Route output from multiple node executions
  defp route_batch_outputs(node_executions, execution_graph, execution_context) do
    Enum.reduce(node_executions, execution_context, fn node_execution, acc_context ->
      updated_context = route_node_output(node_execution, execution_graph, acc_context)
      store_node_result_in_context(node_execution, updated_context)
    end)
  end

  # Get connections from a specific node and port
  defp get_connections_from_node_port(connections, node_id, output_port) do
    Enum.filter(connections, fn connection ->
      connection.from_node_id == node_id and connection.from_port == output_port
    end)
  end

  # Route data through a single connection
  defp route_data_through_connection(node_execution, connection, execution_context) do
    # Apply data mapping if specified, otherwise pass output data directly
    routed_data =
      if map_size(connection.data_mapping) > 0 do
        apply_data_mapping(node_execution.output_data, connection.data_mapping, execution_context)
      else
        node_execution.output_data
      end

    # Store routed data in context for the target node
    target_input_key = "#{connection.to_node_id}_#{connection.to_port}"
    Map.put(execution_context, target_input_key, routed_data)
  end

  # Apply data mapping using expression engine
  defp apply_data_mapping(output_data, data_mapping, execution_context) do
    # Create a temporary context for expression evaluation
    temp_context = Map.put(execution_context, "output", output_data)
    ExpressionEngine.process_map(data_mapping, temp_context)
  end

  # Store node execution result in context for $nodes.node_id access
  defp store_node_result_in_context(node_execution, execution_context) do
    # Get the node's custom_id for context storage
    # Note: We need to look up the node from the graph to get custom_id
    # For now, we'll use the node_id as fallback
    node_key = node_execution.node_id

    result_data =
      if node_execution.status == :completed do
        node_execution.output_data
      else
        %{"error" => node_execution.error_data, "status" => node_execution.status}
      end

    # Update the nodes section of the context
    nodes = Map.get(execution_context, "nodes", %{})
    updated_nodes = Map.put(nodes, node_key, result_data)
    Map.put(execution_context, "nodes", updated_nodes)
  end

  @doc """
  Execute a sub-workflow synchronously - parent waits for completion.

  Loads the sub-workflow using the workflow_loader callback, executes it,
  and merges the result back into the parent execution context.

  ## Parameters

  - `node` - Node requesting sub-workflow execution
  - `context` - Current execution context with workflow_loader

  ## Returns

  - `{:ok, updated_context}` - Sub-workflow completed successfully
  - `{:error, reason}` - Sub-workflow failed or couldn't be loaded
  """
  @spec execute_sub_workflow_sync(Node.t(), map()) :: {:ok, map()} | {:error, any()}
  def execute_sub_workflow_sync(%Node{} = node, context) do
    workflow_id = Map.get(node.input_map, "workflow_id")

    if workflow_id do
      case load_sub_workflow(workflow_id, context) do
        {:ok, sub_execution_graph} ->
          # Prepare input data for sub-workflow
          sub_input_data = Map.get(node.input_map, "input_data", %{})

          # Execute sub-workflow
          case execute_graph(sub_execution_graph, sub_input_data, context) do
            {:ok, sub_execution} ->
              # Merge sub-workflow results into parent context
              # This is a simplified merge - real implementation might be more sophisticated
              updated_context = merge_sub_workflow_results(context, sub_execution)
              {:ok, updated_context}

            {:error, _reason} = error ->
              error
          end

        {:error, _reason} = error ->
          error
      end
    else
      {:error, %{type: "missing_workflow_id", message: "Sub-workflow node missing workflow_id"}}
    end
  end

  @doc """
  Execute a sub-workflow in fire-and-forget mode - parent continues immediately.

  Loads and triggers the sub-workflow execution but does not wait for completion.
  The parent workflow continues executing immediately.

  ## Parameters

  - `node` - Node requesting sub-workflow execution
  - `context` - Current execution context with workflow_loader

  ## Returns

  - `{:ok, context}` - Sub-workflow triggered successfully (not completed)
  - `{:error, reason}` - Sub-workflow failed to trigger or couldn't be loaded
  """
  @spec execute_sub_workflow_fire_and_forget(Node.t(), map()) :: {:ok, map()} | {:error, any()}
  def execute_sub_workflow_fire_and_forget(%Node{} = node, context) do
    workflow_id = Map.get(node.input_map, "workflow_id")

    if workflow_id do
      case load_sub_workflow(workflow_id, context) do
        {:ok, sub_execution_graph} ->
          # Prepare input data for sub-workflow
          sub_input_data = Map.get(node.input_map, "input_data", %{})

          # Trigger sub-workflow asynchronously (fire-and-forget)
          Task.start(fn ->
            case execute_graph(sub_execution_graph, sub_input_data, context) do
              {:ok, _sub_execution} ->
                Logger.info("Fire-and-forget sub-workflow #{workflow_id} completed successfully")

              {:error, reason} ->
                Logger.warning("Fire-and-forget sub-workflow #{workflow_id} failed: #{inspect(reason)}")
            end
          end)

          # Return immediately without waiting
          {:ok, context}

        {:error, _reason} = error ->
          error
      end
    else
      {:error, %{type: "missing_workflow_id", message: "Sub-workflow node missing workflow_id"}}
    end
  end

  # Load sub-workflow using the workflow_loader callback
  defp load_sub_workflow(workflow_id, context) do
    workflow_loader = Map.get(context, :workflow_loader)

    if workflow_loader && is_function(workflow_loader, 1) do
      try do
        workflow_loader.(workflow_id)
      rescue
        error ->
          {:error, %{type: "workflow_loader_error", message: Exception.message(error)}}
      end
    else
      {:error, %{type: "missing_workflow_loader", message: "Context missing workflow_loader callback"}}
    end
  end

  # Merge sub-workflow execution results into parent context
  defp merge_sub_workflow_results(parent_context, sub_execution) do
    # Extract results from sub-execution and merge into parent
    # This is a simplified implementation - real-world might be more sophisticated
    sub_results = %{
      status: sub_execution.status,
      output_data: extract_final_output(sub_execution),
      node_executions: length(sub_execution.node_executions)
    }

    # Store sub-workflow results in parent context
    Map.put(parent_context, "sub_workflow_result", sub_results)
  end

  # Extract final output from execution (simplified)
  defp extract_final_output(execution) do
    # In a real implementation, this might look for specific output nodes
    # For now, we'll return basic execution info
    %{
      completed_at: execution.completed_at,
      node_count: length(execution.node_executions)
    }
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
  and all reachable nodes have been processed.

  ## Parameters

  - `execution` - Current Execution struct
  - `execution_graph` - ExecutionGraph with nodes and dependencies

  ## Returns

  Boolean indicating if workflow execution is complete.
  """
  @spec workflow_complete?(Execution.t(), ExecutionGraph.t()) :: boolean()
  def workflow_complete?(%Execution{} = execution, %ExecutionGraph{} = execution_graph) do
    completed_node_ids = MapSet.new(execution.node_executions, & &1.node_id)
    reachable_node_ids = MapSet.new(execution_graph.workflow.nodes, & &1.id)

    # Workflow is complete if all reachable nodes have been executed
    MapSet.subset?(reachable_node_ids, completed_node_ids)
  end

  # Create initial execution context
  defp create_initial_context(input_data, context) do
    # Create a minimal context for expression evaluation
    # We'll use a simple map structure since ExecutionContext expects workflow/execution
    %{
      "input" => input_data,
      "variables" => Map.get(context, :variables, %{}),
      "metadata" => Map.get(context, :metadata, %{}),
      "nodes" => %{}
    }
  end
end
