defmodule Prana.GraphExecutor do
  @moduledoc """
  GraphExecutor: Branch-Following Workflow Execution Engine

  Orchestrates workflow execution using pre-compiled ExecutionGraphs from WorkflowCompiler.
  Implements branch-following execution strategy that prioritizes completing active execution
  paths before starting new branches, providing predictable and efficient workflow execution.

  ## Primary API

      initialize_execution(execution_graph, context \\ %{})
        :: {:ok, WorkflowExecution.t()} | {:error, reason}

      execute_workflow(execution)
        :: {:ok, WorkflowExecution.t()} | {:suspend, WorkflowExecution.t()} | {:error, WorkflowExecution.t()}

      resume_workflow(suspended_execution, resume_data, execution_graph, execution_context)
        :: {:ok, WorkflowExecution.t()} | {:suspend, WorkflowExecution.t()} | {:error, any()}

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
  %WorkflowExecution{
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

  alias Prana.ExecutionGraph
  alias Prana.Middleware
  alias Prana.Node
  alias Prana.NodeExecution
  alias Prana.NodeExecutor
  alias Prana.WorkflowExecution
  alias Prana.Core.Error

  require Logger

  # Note: Orchestration context type removed - using unified Execution struct only

  @doc """
  Initialize a new execution context for a workflow.

  This allows applications to persist the execution before starting execution,
  providing consistency with resume_workflow which also takes a pre-initialized execution.
  """
  @spec initialize_execution(ExecutionGraph.t(), map()) ::
          {:ok, WorkflowExecution.t()} | {:error, reason :: any()}
  def initialize_execution(execution_graph, context \\ %{}) do
    execution =
      execution_graph
      |> WorkflowExecution.new("graph_executor", execution_graph.variables)
      |> WorkflowExecution.start()
      |> WorkflowExecution.rebuild_runtime(Map.get(context, :env, %{}))

    Middleware.call(:execution_started, %{execution: execution})
    {:ok, execution}
  rescue
    error ->
      {:error, Error.new("initialization_error", Exception.message(error), %{exception: error})}
  end

  @doc """
  Execute a workflow with a pre-initialized execution context.

  This is now consistent with resume_workflow which also takes a pre-initialized execution.
  Applications should call initialize_execution/2 first, persist the execution, then call this function.
  """
  @spec execute_workflow(Execution.t()) ::
          {:ok, WorkflowExecution.t()} | {:suspend, WorkflowExecution.t()} | {:error, WorkflowExecution.t()}
  def execute_workflow(%WorkflowExecution{} = execution) do
    case WorkflowExecution.prepare_workflow_actions(execution) do
      {:ok, prepared_execution} ->
        execute_workflow_with_error_handling(prepared_execution)

      {:error, reason} ->
        handle_preparation_failure(execution.execution_graph, reason)
    end
  rescue
    error ->
      handle_execution_exception(execution.execution_graph, error)
  end

  @doc """
  Legacy function for backward compatibility.

  This function initializes execution internally and should be deprecated in favor of
  initialize_execution/2 followed by execute_workflow/1.
  """
  @spec execute_workflow(ExecutionGraph.t(), map()) ::
          {:ok, WorkflowExecution.t()} | {:suspend, WorkflowExecution.t()} | {:error, WorkflowExecution.t()}
  def execute_workflow(%ExecutionGraph{} = execution_graph, context \\ %{}) do
    with {:ok, execution} <- initialize_execution(execution_graph, context) do
      execute_workflow(execution)
    end
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
        Middleware.call(:execution_failed, %{execution: failed_execution, reason: failed_execution.error})
        {:error, failed_execution}
    end
  end

  # Handle workflow preparation failure
  defp handle_preparation_failure(execution_graph, reason) do
    execution =
      execution_graph
      |> WorkflowExecution.new("graph_executor", execution_graph.variables)
      |> WorkflowExecution.start()
      |> WorkflowExecution.fail(reason)

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
      |> WorkflowExecution.new("graph_executor", execution_graph.variables)
      |> WorkflowExecution.start()
      |> WorkflowExecution.fail(reason)

    Middleware.call(:execution_failed, %{execution: execution, reason: reason})
    {:error, execution}
  end

  # Main workflow execution loop - continues until workflow is complete or error occurs.
  # Uses WorkflowExecution.__runtime for all workflow-level coordination.
  defp execute_workflow_loop(execution) do
    # Check for infinite loop protection
    iteration_count = WorkflowExecution.get_iteration_count(execution)
    max_iterations = WorkflowExecution.get_max_iterations(execution)

    if iteration_count >= max_iterations do
      error_reason = %{
        type: "infinite_loop_protection",
        message: "Workflow execution exceeded maximum iterations (#{max_iterations})",
        iteration_count: iteration_count,
        max_iterations: max_iterations
      }
      {:error, WorkflowExecution.fail(execution, error_reason)}
    else
      # Increment iteration counter in both runtime and persistent metadata
      execution = WorkflowExecution.increment_iteration_count(execution)

      # Get active nodes from runtime state
      active_nodes = WorkflowExecution.get_active_nodes(execution)

      if MapSet.size(active_nodes) == 0 do
        {:ok, WorkflowExecution.complete(execution)}
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
  # Uses WorkflowExecution.__runtime for tracking active paths and executed nodes.
  defp find_and_execute_ready_nodes(execution) do
    ready_nodes = WorkflowExecution.find_ready_nodes(execution)

    if Enum.empty?(ready_nodes) do
      # No ready nodes but workflow not complete - likely an error condition
      error_reason = %{
        type: "no_ready_nodes",
        message: "No ready nodes found but workflow is not complete",
        current_status: execution.status,
        completed_nodes: Map.keys(execution.node_executions)
      }
      {:error, WorkflowExecution.fail(execution, error_reason)}
    else
      # Select single node to execute, prioritizing branch completion
      selected_node = select_node_for_branch_following(ready_nodes, execution.__runtime)

      case execute_single_node_with_events(selected_node, execution) do
        {%NodeExecution{status: :completed}, updated_execution} ->
          # Output routing and context updates are handled internally by NodeExecutor
          # and the WorkflowExecution.complete_node/2 function (which also updates active_nodes)
          {:ok, updated_execution}

        {%NodeExecution{status: :suspended} = node_execution, updated_execution} ->
          # Extract suspension information from NodeExecution fields
          suspension_type = node_execution.suspension_type || :sub_workflow
          suspend_data = node_execution.suspension_data || %{}

          # Suspend the entire execution with structured suspension data
          suspended_execution =
            WorkflowExecution.suspend(updated_execution, selected_node.key, suspension_type, suspend_data)

          Middleware.call(:execution_suspended, %{
            execution: suspended_execution,
            suspended_node: selected_node,
            node_execution: node_execution
          })

          {:suspend, suspended_execution}

        {%NodeExecution{status: :failed} = node_execution, updated_execution} ->
          # Update execution with failed node and mark execution as failed
          error_reason = %{
            type: "node_execution_failed",
            message: "Node execution failed: #{selected_node.key}",
            node_key: selected_node.key,
            node_error: node_execution.error_data
          }
          
          failed_execution =
            updated_execution
            |> WorkflowExecution.fail_node(node_execution)
            |> WorkflowExecution.fail(error_reason)

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

  # Execute a single node with middleware events using unified execution architecture
  defp execute_single_node_with_events(node, execution) do
    # Extract multi-port input data for this node from execution graph and runtime state
    routed_input = WorkflowExecution.extract_multi_port_input(node, execution)

    # Get execution tracking indices
    execution_index = execution.current_execution_index
    run_index = WorkflowExecution.get_next_run_index(execution, node.key)

    # Emit node starting event
    Middleware.call(:node_starting, %{node: node, execution: execution})

    # Execute the node using the tracking interface
    case NodeExecutor.execute_node(node, execution, routed_input, execution_index, run_index) do
      {:ok, result_node_execution} ->
        # Complete the node execution at workflow level
        updated_execution = Prana.WorkflowExecution.complete_node(execution, result_node_execution)
        # Increment execution index for next node
        final_execution = %{updated_execution | current_execution_index: execution_index + 1}
        Middleware.call(:node_completed, %{node: node, node_execution: result_node_execution})
        {result_node_execution, final_execution}

      {:ok, result_node_execution, shared_state_updates} ->
        # Complete the node execution at workflow level
        updated_execution =
          execution
          |> Prana.WorkflowExecution.complete_node(result_node_execution)
          |> Prana.WorkflowExecution.update_shared_state(shared_state_updates)

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
        updated_execution = WorkflowExecution.add_node_execution_to_map(final_execution, suspended_node_execution)
        {suspended_node_execution, updated_execution}

      {:error, {_reason, error_node_execution}} ->
        Middleware.call(:node_failed, %{node: node, node_execution: error_node_execution})
        # Increment execution index and add failed node to execution
        final_execution = %{execution | current_execution_index: execution_index + 1}
        updated_execution = WorkflowExecution.add_node_execution_to_map(final_execution, error_node_execution)
        {error_node_execution, updated_execution}
    end
  end

  @doc """
  Resume a suspended workflow execution with sub-workflow results.

  ## Parameters

  - `suspended_execution` - The suspended Execution struct (contains execution_graph and execution data)
  - `resume_data` - Data to resume with (sub-workflow results, external event data, etc.)
  - `options` - Optional configuration (env data, middleware overrides, etc.)

  ## Returns

  - `{:ok, execution}` - Successful completion after resume
  - `{:suspend, execution}` - Execution suspended again (for nested async operations)
  - `{:error, reason}` - Resume failed with error details
  """
  @spec resume_workflow(Execution.t(), map(), map()) ::
          {:ok, WorkflowExecution.t()} | {:suspend, WorkflowExecution.t()} | {:error, any()}
  def resume_workflow(suspended_execution, resume_data, options \\ %{})

  def resume_workflow(%WorkflowExecution{status: :suspended} = suspended_execution, resume_data, options) do
    with {:ok, prepared_execution} <-
           prepare_execution_for_resume(suspended_execution, options),
         {:ok, suspended_node_id} <- validate_suspended_node_id(prepared_execution),
         {:ok, updated_execution} <-
           resume_suspended_node(prepared_execution, suspended_node_id, resume_data) do
      execute_workflow_loop(updated_execution)
    end
  end

  def resume_workflow(%WorkflowExecution{status: status}, _resume_data, _options) do
    {:error, %{type: "invalid_execution_status", message: "Can only resume suspended executions", status: status}}
  end

  # Prepare execution for resume by rebuilding runtime state
  defp prepare_execution_for_resume(suspended_execution, options) do
    env_data = Map.get(options, :env, %{})
    prepared_execution = WorkflowExecution.rebuild_runtime(suspended_execution, env_data)
    {:ok, prepared_execution}
  end

  # Validate that the suspended execution has a valid suspended node ID
  defp validate_suspended_node_id(prepared_execution) do
    case prepared_execution.suspended_node_id do
      nil -> {:error, %{type: "invalid_suspended_execution", message: "Cannot find suspended node ID"}}
      suspended_node_id -> {:ok, suspended_node_id}
    end
  end

  # Complete a suspended node execution with resume data
  defp resume_suspended_node(suspended_execution, suspended_node_id, resume_data) do
    # Find the suspended node definition and execution from execution's own execution_graph
    suspended_node = Map.get(suspended_execution.execution_graph.node_map, suspended_node_id)
    suspended_node_executions = Map.get(suspended_execution.node_executions, suspended_node_id, [])
    suspended_node_execution = Enum.find(suspended_node_executions, &(&1.status == :suspended))

    if suspended_node && suspended_node_execution do
      # Clear suspension state for resume (runtime state already initialized in resume_workflow)
      resume_ready_execution = WorkflowExecution.resume_suspension(suspended_execution)

      # Call NodeExecutor with unified interface
      case NodeExecutor.resume_node(suspended_node, resume_ready_execution, suspended_node_execution, resume_data) do
        {:ok, completed_node_execution} ->
          # Complete the node execution at workflow level
          updated_execution = Prana.WorkflowExecution.complete_node(resume_ready_execution, completed_node_execution)
          {:ok, updated_execution}

        {:error, {reason, _failed_node_execution}} ->
          {:error, reason}
      end
    else
      {:error, %{type: "suspended_node_not_found", node_key: suspended_node_id}}
    end
  end
end
