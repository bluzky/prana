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
  alias Prana.IntegrationRegistry
  alias Prana.Node
  alias Prana.Workflow

  @doc """
  Compile workflow into an optimized execution graph.

  ## Parameters
  - `workflow` - Complete workflow definition
  - `trigger_node_key` - ID of the specific trigger node to start from

  ## Returns
  - `{:ok, execution_graph}` - Compiled execution graph
  - `{:error, reason}` - Compilation failed
  """
  @spec compile(Workflow.t(), String.t() | nil) :: {:ok, ExecutionGraph.t()} | {:error, term()}
  def compile(%Workflow{} = workflow, trigger_node_key \\ nil) do
    with {:ok, trigger_node} <- get_trigger_node(workflow, trigger_node_key),
         {:ok, reachable_nodes} <- find_reachable_nodes(workflow, trigger_node) do
      compiled_workflow = prune_workflow(workflow, reachable_nodes)
      dependency_graph = build_dependency_graph(compiled_workflow)
      connection_map = build_connection_map(compiled_workflow)
      reverse_connection_map = build_reverse_connection_map(compiled_workflow)
      node_map = build_node_map(compiled_workflow)

      execution_graph = %ExecutionGraph{
        workflow_id: workflow.id,
        trigger_node_key: trigger_node.key,
        dependency_graph: dependency_graph,
        connection_map: connection_map,
        reverse_connection_map: reverse_connection_map,
        node_map: node_map,
        variables: workflow.variables
      }

      {:ok, execution_graph}
    end
  end

  @doc """
  Find nodes that are ready for execution based on dependency satisfaction.
  """
  @spec find_ready_nodes(ExecutionGraph.t(), MapSet.t(), MapSet.t(), MapSet.t()) :: [Node.t()]
  def find_ready_nodes(%ExecutionGraph{} = graph, completed_nodes, failed_nodes, pending_nodes) do
    graph.node_map
    |> Map.values()
    |> Enum.reject(&node_executed?(&1.key, completed_nodes, failed_nodes))
    |> Enum.reject(&node_pending?(&1.key, pending_nodes))
    |> Enum.filter(&dependencies_satisfied?(graph, &1, completed_nodes))
  end

  # ============================================================================
  # Trigger Node Selection
  # ============================================================================

  # Get the trigger node to start execution from.
  # If trigger_node_key is provided, uses that specific node.
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

  defp get_trigger_node(%Workflow{} = workflow, trigger_node_key) when is_binary(trigger_node_key) do
    case Workflow.get_node_by_key(workflow, trigger_node_key) do
      nil ->
        {:error, {:trigger_node_not_found, trigger_node_key}}

      node ->
        case get_action_type(node) do
          {:ok, :trigger} -> {:ok, node}
          {:ok, other_type} -> {:error, {:node_not_trigger, trigger_node_key, other_type}}
          {:error, reason} -> {:error, {:action_lookup_failed, trigger_node_key, reason}}
        end
    end
  end

  @spec find_trigger_nodes(Workflow.t()) :: [Node.t()]
  defp find_trigger_nodes(%Workflow{nodes: nodes}) do
    Enum.filter(nodes, fn node ->
      case get_action_type(node) do
        {:ok, :trigger} -> true
        _ -> false
      end
    end)
  end

  # Helper function to get action type from node via integration registry
  @spec get_action_type(Node.t()) :: {:ok, atom()} | {:error, term()}
  defp get_action_type(%Node{integration_name: integration_name, action_name: action_name}) do
    case IntegrationRegistry.get_action(integration_name, action_name) do
      {:ok, %Prana.Action{type: action_type}} -> {:ok, action_type}
      {:error, reason} -> {:error, reason}
    end
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
    queue = [trigger_node.key]

    reachable_node_keys = traverse_graph(workflow, queue, visited)

    # Get actual node structs for reachable IDs
    reachable_nodes =
      Enum.filter(workflow.nodes, fn node -> MapSet.member?(reachable_node_keys, node.key) end)

    {:ok, reachable_nodes}
  end

  @spec traverse_graph(Workflow.t(), [String.t()], MapSet.t()) :: MapSet.t()
  defp traverse_graph(_workflow, [], visited), do: visited

  defp traverse_graph(%Workflow{} = workflow, [current_key | rest], visited) do
    if MapSet.member?(visited, current_key) do
      # Already visited this node
      traverse_graph(workflow, rest, visited)
    else
      # Mark as visited and find connected nodes
      new_visited = MapSet.put(visited, current_key)
      connected_nodes = find_connected_nodes(workflow, current_key)
      new_queue = rest ++ connected_nodes

      traverse_graph(workflow, new_queue, new_visited)
    end
  end

  @spec find_connected_nodes(Workflow.t(), String.t()) :: [String.t()]
  defp find_connected_nodes(%Workflow{connections: connections}, from_node_key) do
    connections
    |> Map.get(from_node_key, %{})
    |> Enum.flat_map(fn {_port, conns} ->
      Enum.map(conns, & &1.to)
    end)
    |> Enum.uniq()
  end

  # Create a compiled workflow containing only reachable nodes and their connections.
  @spec prune_workflow(Workflow.t(), [Node.t()]) :: Workflow.t()
  defp prune_workflow(%Workflow{} = workflow, reachable_nodes) do
    reachable_node_keys = MapSet.new(reachable_nodes, & &1.key)

    # Filter connections to only include those between reachable nodes
    reachable_connections =
      Map.new(reachable_node_keys, fn node_key ->
        node_connections = Map.get(workflow.connections, node_key, %{})

        filtered_ports =
          Map.new(node_connections, fn {port, conns} ->
            filtered_conns = Enum.filter(conns, fn conn -> MapSet.member?(reachable_node_keys, conn.to) end)
            {port, filtered_conns}
          end)

        {node_key, filtered_ports}
      end)

    # Filter connections to only include reachable targets

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
    connections
    |> Enum.flat_map(fn {_node, ports} ->
      Enum.flat_map(ports, fn {_port, conns} -> conns end)
    end)
    |> Enum.reduce(%{}, fn conn, acc ->
      Map.update(acc, conn.to, [conn.from], fn deps ->
        Enum.uniq([conn.from | deps])
      end)
    end)
  end

  # Build connection map for fast lookup of outgoing connections.
  @spec build_connection_map(Workflow.t()) :: map()
  defp build_connection_map(%Workflow{connections: connections}) do
    connections
    |> Enum.flat_map(fn {node_key, ports} ->
      Enum.map(ports, fn {port, conns} ->
        {{node_key, port}, conns}
      end)
    end)
    |> Map.new()
  end

  # Build reverse connection map for fast lookup of incoming connections.
  @spec build_reverse_connection_map(Workflow.t()) :: map()
  defp build_reverse_connection_map(%Workflow{connections: connections}) do
    connections
    |> Enum.flat_map(fn {_node, ports} ->
      Enum.flat_map(ports, fn {_port, conns} -> conns end)
    end)
    |> Enum.group_by(fn conn -> conn.to end)
  end

  # Build node map for fast lookup of nodes by ID.
  @spec build_node_map(Workflow.t()) :: map()
  defp build_node_map(%Workflow{nodes: nodes}) do
    Map.new(nodes, fn node -> {node.key, node} end)
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  @spec node_executed?(String.t(), MapSet.t(), MapSet.t()) :: boolean()
  defp node_executed?(node_key, completed_nodes, failed_nodes) do
    MapSet.member?(completed_nodes, node_key) or MapSet.member?(failed_nodes, node_key)
  end

  @spec node_pending?(String.t(), MapSet.t()) :: boolean()
  defp node_pending?(node_key, pending_nodes) do
    MapSet.member?(pending_nodes, node_key)
  end

  @spec dependencies_satisfied?(ExecutionGraph.t(), Node.t(), MapSet.t()) :: boolean()
  defp dependencies_satisfied?(%ExecutionGraph{} = graph, %Node{} = node, completed_nodes) do
    dependencies = Map.get(graph.dependency_graph, node.key, [])

    Enum.all?(dependencies, fn dep_node_key ->
      MapSet.member?(completed_nodes, dep_node_key)
    end)
  end
end
