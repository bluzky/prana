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
    with {:ok, trigger_node} <- get_trigger_node(workflow, trigger_node_key) do
      dependency_graph = build_dependency_graph(workflow)
      connection_map = build_connection_map(workflow)
      reverse_connection_map = build_reverse_connection_map(workflow)
      node_map = build_node_map(workflow)

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
  defp get_action_type(%Node{} = node) do
    case IntegrationRegistry.get_action_by_type(node.type) do
      {:ok, %Prana.Action{type: action_type}} -> {:ok, action_type}
      {:error, reason} -> {:error, reason}
    end
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
end
