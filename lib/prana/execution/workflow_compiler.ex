defmodule Prana.WorkflowCompiler do
  @moduledoc """
  Compiles raw workflows into optimized execution graphs.

  Transforms workflow definitions by:
  - Selecting trigger nodes and validating structure
  - Pruning unreachable nodes via graph traversal
  - Building dependency graphs for execution ordering
  - Creating O(1) lookup maps for performance

  The output ExecutionGraph is ready for efficient execution by GraphExecutor.
  """

  alias Prana.ExecutionGraph
  alias Prana.Node
  alias Prana.Workflow

  @doc """
  Compile workflow into an optimized execution graph.

  ## Parameters
  - `workflow` - Complete workflow definition
  - `trigger_node_id` - ID of the specific trigger node to start from

  ## Returns
  - `{:ok, execution_graph}` - Compiled execution graph
  - `{:error, reason}` - Compilation failed
  """
  @spec compile(Workflow.t(), String.t() | nil) :: {:ok, ExecutionGraph.t()} | {:error, term()}
  def compile(%Workflow{} = workflow, trigger_node_id \\ nil) do
    with {:ok, trigger_node} <- get_trigger_node(workflow, trigger_node_id),
         {:ok, reachable_nodes} <- find_reachable_nodes(workflow, trigger_node) do
      compiled_workflow = prune_workflow(workflow, reachable_nodes)
      dependency_graph = build_dependency_graph(compiled_workflow)
      connection_map = build_connection_map(compiled_workflow)
      node_map = build_node_map(compiled_workflow)

      execution_graph = %ExecutionGraph{
        workflow: compiled_workflow,
        trigger_node: trigger_node,
        dependency_graph: dependency_graph,
        connection_map: connection_map,
        node_map: node_map,
        total_nodes: length(reachable_nodes)
      }

      {:ok, execution_graph}
    end
  end

  @doc """
  Find nodes that are ready for execution based on dependency satisfaction.
  """
  @spec find_ready_nodes(ExecutionGraph.t(), MapSet.t(), MapSet.t(), MapSet.t()) :: [Node.t()]
  def find_ready_nodes(%ExecutionGraph{} = graph, completed_nodes, failed_nodes, pending_nodes) do
    graph.workflow.nodes
    |> Enum.reject(&node_executed?(&1.id, completed_nodes, failed_nodes))
    |> Enum.reject(&node_pending?(&1.id, pending_nodes))
    |> Enum.filter(&dependencies_satisfied?(graph, &1, completed_nodes))
  end

  # ============================================================================
  # Trigger Node Selection
  # ============================================================================

  # Get the trigger node to start execution from.
  # If trigger_node_id is provided, uses that specific node.
  # If not provided, finds the first trigger node in the workflow.
  @spec get_trigger_node(Workflow.t(), String.t() | nil) :: {:ok, Node.t()} | {:error, term()}
  defp get_trigger_node(%Workflow{} = workflow, nil) do
    # No specific trigger provided, find first trigger node
    case find_trigger_nodes(workflow) do
      [] ->
        {:error, :no_trigger_nodes}

      [trigger_node] ->
        {:ok, trigger_node}

      trigger_nodes when length(trigger_nodes) > 1 ->
        # Multiple triggers found, need to specify which one
        trigger_names = Enum.map(trigger_nodes, & &1.name)
        {:error, {:multiple_triggers_found, trigger_names}}
    end
  end

  defp get_trigger_node(%Workflow{} = workflow, trigger_node_id) when is_binary(trigger_node_id) do
    case Workflow.get_node_by_id(workflow, trigger_node_id) do
      nil ->
        {:error, {:trigger_node_not_found, trigger_node_id}}

      %Node{type: :trigger} = node ->
        {:ok, node}

      %Node{type: other_type} ->
        {:error, {:node_not_trigger, trigger_node_id, other_type}}
    end
  end

  @spec find_trigger_nodes(Workflow.t()) :: [Node.t()]
  defp find_trigger_nodes(%Workflow{nodes: nodes}) do
    Enum.filter(nodes, fn node -> node.type == :trigger end)
  end

  # ============================================================================
  # Graph Traversal & Pruning
  # ============================================================================

  # Find all nodes reachable from the trigger node using graph traversal.
  # This removes any nodes that are not connected to the execution path.
  @spec find_reachable_nodes(Workflow.t(), Node.t()) :: {:ok, [Node.t()]} | {:error, term()}
  defp find_reachable_nodes(%Workflow{} = workflow, %Node{} = trigger_node) do
    # Use breadth-first search to find all reachable nodes
    visited = MapSet.new()
    queue = [trigger_node.id]

    reachable_node_ids = traverse_graph(workflow, queue, visited)

    # Get actual node structs for reachable IDs
    reachable_nodes =
      Enum.filter(workflow.nodes, fn node -> MapSet.member?(reachable_node_ids, node.id) end)

    {:ok, reachable_nodes}
  end

  @spec traverse_graph(Workflow.t(), [String.t()], MapSet.t()) :: MapSet.t()
  defp traverse_graph(_workflow, [], visited), do: visited

  defp traverse_graph(%Workflow{} = workflow, [current_id | rest], visited) do
    if MapSet.member?(visited, current_id) do
      # Already visited this node
      traverse_graph(workflow, rest, visited)
    else
      # Mark as visited and find connected nodes
      new_visited = MapSet.put(visited, current_id)
      connected_nodes = find_connected_nodes(workflow, current_id)
      new_queue = rest ++ connected_nodes

      traverse_graph(workflow, new_queue, new_visited)
    end
  end

  @spec find_connected_nodes(Workflow.t(), String.t()) :: [String.t()]
  defp find_connected_nodes(%Workflow{connections: connections}, from_node_id) do
    connections
    |> Enum.filter(fn conn -> conn.from_node_id == from_node_id end)
    |> Enum.map(fn conn -> conn.to_node_id end)
    |> Enum.uniq()
  end

  # Create a compiled workflow containing only reachable nodes and their connections.
  @spec prune_workflow(Workflow.t(), [Node.t()]) :: Workflow.t()
  defp prune_workflow(%Workflow{} = workflow, reachable_nodes) do
    reachable_node_ids = MapSet.new(reachable_nodes, & &1.id)

    # Filter connections to only include those between reachable nodes
    reachable_connections =
      Enum.filter(workflow.connections, fn conn ->
        MapSet.member?(reachable_node_ids, conn.from_node_id) and MapSet.member?(reachable_node_ids, conn.to_node_id)
      end)

    # Create new workflow with compiled nodes and connections
    %{workflow | nodes: reachable_nodes, connections: reachable_connections}
  end

  # ============================================================================
  # Graph Analysis
  # ============================================================================

  # Build dependency graph showing which nodes depend on which other nodes.
  # Returns a map where keys are node IDs and values are lists of node IDs
  # that must complete before the key node can execute.
  @spec build_dependency_graph(Workflow.t()) :: map()
  defp build_dependency_graph(%Workflow{connections: connections}) do
    Enum.reduce(connections, %{}, fn conn, acc ->
      Map.update(acc, conn.to_node_id, [conn.from_node_id], fn deps ->
        Enum.uniq([conn.from_node_id | deps])
      end)
    end)
  end

  # Build connection map for fast lookup of outgoing connections.
  @spec build_connection_map(Workflow.t()) :: map()
  defp build_connection_map(%Workflow{connections: connections}) do
    Enum.group_by(connections, fn conn ->
      {conn.from_node_id, conn.from_port}
    end)
  end

  # Build node map for fast lookup of nodes by ID.
  @spec build_node_map(Workflow.t()) :: map()
  defp build_node_map(%Workflow{nodes: nodes}) do
    Map.new(nodes, fn node -> {node.id, node} end)
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  @spec node_executed?(String.t(), MapSet.t(), MapSet.t()) :: boolean()
  defp node_executed?(node_id, completed_nodes, failed_nodes) do
    MapSet.member?(completed_nodes, node_id) or MapSet.member?(failed_nodes, node_id)
  end

  @spec node_pending?(String.t(), MapSet.t()) :: boolean()
  defp node_pending?(node_id, pending_nodes) do
    MapSet.member?(pending_nodes, node_id)
  end

  @spec dependencies_satisfied?(ExecutionGraph.t(), Node.t(), MapSet.t()) :: boolean()
  defp dependencies_satisfied?(%ExecutionGraph{} = graph, %Node{} = node, completed_nodes) do
    dependencies = Map.get(graph.dependency_graph, node.id, [])

    Enum.all?(dependencies, fn dep_node_id ->
      MapSet.member?(completed_nodes, dep_node_id)
    end)
  end
end
