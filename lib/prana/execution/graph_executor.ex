defmodule Prana.GraphExecutor do
  @moduledoc """
  GraphExecutor: Branch-Following Workflow Execution Engine

  Orchestrates workflow execution using pre-compiled ExecutionGraphs from WorkflowCompiler.
  Implements branch-following execution strategy that prioritizes completing active execution
  paths before starting new branches, providing predictable and efficient workflow execution.

  ## Primary API

      execute_graph(execution_graph, context \\ %{})
        :: {:ok, Execution.t()} | {:suspend, Execution.t()} | {:error, Execution.t()}

      resume_workflow(suspended_execution, resume_data, execution_graph, execution_context)
        :: {:ok, Execution.t()} | {:suspend, Execution.t()} | {:error, any()}

  ## Required Context Structure

      context = %{
        workflow_loader: (workflow_id -> {:ok, ExecutionGraph.t()} | {:error, reason}),
        variables: %{},     # optional
        metadata: %{},      # optional
        env: %{}            # optional environment data
      }

  ## Execution Model

  **Branch-Following Strategy**: Executes one node at a time, prioritizing nodes that continue
  active execution branches before starting new branches. This provides:

  - **Predictable execution order**: Branches complete fully before others start
  - **Efficient resource utilization**: Reduced contention between competing nodes
  - **Enhanced conditional branching**: Proper IF/ELSE and switch/case behavior
  - **Improved debuggability**: Clear execution flow for complex workflows

  ## Core Features

  - **Branch-following execution**: Intelligent node selection with depth-based prioritization
  - **O(1) connection lookups**: Pre-built optimization maps for fast routing
  - **Port-based data routing**: Multi-port input handling with immediate output processing
  - **Unified execution architecture**: Single Execution struct with runtime state management
  - **Sub-workflow orchestration**: Sync, async, and fire-and-forget execution modes
  - **Conditional path tracking**: IF/ELSE and switch/case pattern support
  - **Suspension/resume support**: Structured suspension data with type safety
  - **Middleware integration**: Comprehensive event emission for lifecycle management
  - **Error handling**: Fail-fast behavior with complete error propagation
  - **Loop protection**: Iteration limits to prevent infinite execution cycles

  ## Execution Flow

  1. **Initialization**: Creates execution context and rebuilds runtime state
  2. **Preparation**: Pre-processes all workflow actions for optimal execution
  3. **Main Loop**: Iterative execution with branch-following node selection
  4. **Completion**: Finalizes execution or handles suspension/errors

  ## Integration Points

  - **WorkflowCompiler**: Uses compiled ExecutionGraphs with optimization maps
  - **NodeExecutor**: Delegates individual node execution with unified interface
  - **Execution**: Manages persistent and runtime state with active node tracking
  - **Middleware**: Emits lifecycle events for application-level handling
  - **ExpressionEngine**: Processes dynamic data routing (via NodeExecutor)

  ## Unified Execution Architecture

  Uses a single, unified execution context structure:

  ### Execution with Runtime State
  ```elixir
  %Execution{
    # Persistent metadata and audit trail
    id: String.t(),
    workflow_id: String.t(),
    node_executions: %{String.t() => [NodeExecution.t()]},
    vars: map(),

    # Ephemeral runtime state (rebuilt on load)
    __runtime: %{
      "nodes" => %{node_key => output_data},     # completed node outputs
      "env" => map(),                           # environment data
      "active_nodes" => MapSet.t(String.t()),   # nodes ready for execution
      "node_depth" => %{node_key => integer()}   # depth tracking for branch following
    }
  }
  ```

  ### Multi-Port Input Routing

  Data flow uses multi-port input routing for flexible node connections:
  `Execution.extract_multi_port_input/2` → `%{"port_name" => data}` → `NodeExecutor.execute_node/5`

  ## Suspension and Resume

  Supports structured suspension for:
  - **Sub-workflow coordination**: Sync and async sub-workflow execution
  - **External events**: Webhook and timer-based resumption
  - **Complex orchestration**: Multi-step workflow coordination

  Suspension data is type-safe and includes all necessary context for resumption.
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
    with {:ok, prepared_execution} <-
           prepare_execution_for_resume(suspended_execution, execution_graph, execution_context),
         {:ok, suspended_node_id} <- validate_suspended_node_id(prepared_execution),
         {:ok, updated_execution} <-
           resume_suspended_node(execution_graph, prepared_execution, suspended_node_id, resume_data) do
      execute_workflow_loop(updated_execution)
    end
  end

  def resume_workflow(%Execution{status: status}, _resume_data, _execution_graph, _execution_context) do
    {:error, %{type: "invalid_execution_status", message: "Can only resume suspended executions", status: status}}
  end

  # Prepare execution for resume by rebuilding runtime state
  defp prepare_execution_for_resume(suspended_execution, execution_graph, execution_context) do
    env_data = Map.get(execution_context, :env, %{})
    prepared_execution = Execution.rebuild_runtime(%{suspended_execution | execution_graph: execution_graph}, env_data)
    {:ok, prepared_execution}
  end

  # Validate that the suspended execution has a valid suspended node ID
  defp validate_suspended_node_id(prepared_execution) do
    case prepared_execution.suspended_node_id do
      nil -> {:error, %{type: "invalid_suspended_execution", message: "Cannot find suspended node ID"}}
      suspended_node_id -> {:ok, suspended_node_id}
    end
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
    with {:ok, execution} <- initialize_execution(execution_graph, context),
         {:ok, prepared_execution} <- Execution.prepare_workflow_actions(execution) do
      execute_workflow_with_error_handling(prepared_execution)
    else
      {:error, reason} ->
        handle_preparation_failure(execution_graph, reason)
    end
  rescue
    error ->
      handle_execution_exception(execution_graph, error)
  end

  # Initialize a new execution with runtime state
  defp initialize_execution(execution_graph, context) do
    execution =
      execution_graph
      |> Execution.new("graph_executor", execution_graph.variables)
      |> Execution.start()
      |> Execution.rebuild_runtime(Map.get(context, :env, %{}))

    Middleware.call(:execution_started, %{execution: execution})
    {:ok, execution}
  end

  # Execute workflow loop with proper error handling
  defp execute_workflow_with_error_handling(execution) do
    case execute_workflow_loop(execution) do
      {:ok, final_execution} ->
        Middleware.call(:execution_completed, %{execution: final_execution})
        {:ok, final_execution}

      {:suspend, suspended_execution} ->
        {:suspend, suspended_execution}

      {:error, failed_execution} ->
        Middleware.call(:execution_failed, %{execution: failed_execution, reason: failed_execution.error_data})
        {:error, failed_execution}
    end
  end

  # Handle workflow preparation failure
  defp handle_preparation_failure(execution_graph, reason) do
    execution =
      execution_graph
      |> Execution.new("graph_executor", execution_graph.variables)
      |> Execution.start()
      |> Execution.fail()

    Middleware.call(:execution_failed, %{execution: execution, reason: reason})
    {:error, execution}
  end

  # Handle unexpected execution exceptions
  defp handle_execution_exception(execution_graph, error) do
    reason = %{
      type: "execution_exception",
      message: Exception.message(error),
      details: %{}
    }

    execution =
      execution_graph
      |> Execution.new("graph_executor", execution_graph.variables)
      |> Execution.start()
      |> Execution.fail()

    Middleware.call(:execution_failed, %{execution: execution, reason: reason})
    {:error, execution}
  end

  # Main workflow execution loop - continues until workflow is complete or error occurs.
  # Uses Execution.__runtime for all workflow-level coordination.
  defp execute_workflow_loop(execution) do
    # Check for infinite loop protection
    iteration_count = Execution.get_iteration_count(execution)
    max_iterations = Execution.get_max_iterations(execution)

    if iteration_count >= max_iterations do
      {:error, Execution.fail(execution)}
    else
      # Increment iteration counter in both runtime and persistent metadata
      execution = Execution.increment_iteration_count(execution)
      
      # Get active nodes from runtime state
      active_nodes = Execution.get_active_nodes(execution)

      if MapSet.size(active_nodes) == 0 do
        {:ok, Execution.complete(execution)}
      else
        case find_and_execute_ready_nodes(execution) do
          {:ok, updated_execution} ->
            execute_workflow_loop(updated_execution)

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
  defp find_and_execute_ready_nodes(execution) do
    ready_nodes = Execution.find_ready_nodes(execution)

    if Enum.empty?(ready_nodes) do
      # No ready nodes but workflow not complete - likely an error condition
      {:error, Execution.fail(execution)}
    else
      # Select single node to execute, prioritizing branch completion
      selected_node = select_node_for_branch_following(ready_nodes, execution.__runtime)

      case execute_single_node_with_events(selected_node, execution) do
        {%NodeExecution{status: :completed}, updated_execution} ->
          # Output routing and context updates are handled internally by NodeExecutor
          # and the Execution.complete_node/2 function (which also updates active_nodes)
          {:ok, updated_execution}

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

        {%NodeExecution{}, updated_execution} ->
          # Node finished with other status - no additional handling needed
          # All context updates are handled by NodeExecutor and Execution functions
          {:ok, updated_execution}
      end
    end
  rescue
    error ->
      # Unexpected error during node execution
      {:error, %{
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

  # Execute a single node with middleware events using unified execution architecture
  defp execute_single_node_with_events(node, execution) do
    # Extract multi-port input data for this node from execution graph and runtime state
    routed_input = Execution.extract_multi_port_input(node, execution)

    # Get execution tracking indices
    execution_index = execution.current_execution_index
    run_index = Execution.get_next_run_index(execution, node.key)

    # Emit node starting event
    Middleware.call(:node_starting, %{node: node, execution: execution})

    # Execute the node using the tracking interface
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
    suspended_node_executions = Map.get(suspended_execution.node_executions, suspended_node_id, [])
    suspended_node_execution = Enum.find(suspended_node_executions, &(&1.status == :suspended))

    if suspended_node && suspended_node_execution do
      # Clear suspension state for resume (runtime state already initialized in resume_workflow)
      resume_ready_execution = Execution.resume_suspension(suspended_execution)

      # Call NodeExecutor with unified interface
      case NodeExecutor.resume_node(suspended_node, resume_ready_execution, suspended_node_execution, resume_data) do
        {:ok, _completed_node_execution, updated_execution} ->
          # Active nodes are updated automatically by NodeExecutor via Execution.complete_node/2
          {:ok, updated_execution}

        {:error, {reason, _failed_node_execution}} ->
          {:error, reason}
      end
    else
      {:error, %{type: "suspended_node_not_found", node_key: suspended_node_id}}
    end
  end
end
