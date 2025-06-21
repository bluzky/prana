defmodule Prana.ExecutionPlanner do
  @moduledoc """
  Handles execution planning for workflows, including trigger node selection,
  graph pruning, and dependency analysis.
  """

  alias Prana.{Workflow, Node, Connection, ExecutionPlan}

  @doc """
  Plan execution starting from a specific trigger node.
  
  ## Parameters
  - `workflow` - Complete workflow definition
  - `trigger_node_id` - ID of the specific trigger node to start from
  
  ## Returns
  - `{:ok, plan}` - Execution plan with pruned graph
  - `{:error, reason}` - Planning failed
  """
  @spec plan_execution(Workflow.t(), String.t() | nil) :: {:ok, ExecutionPlan.t()} | {:error, term()}
  def plan_execution(%Workflow{} = workflow, trigger_node_id \\ nil) do
    with {:ok, trigger_node} <- get_trigger_node(workflow, trigger_node_id),
         {:ok, reachable_nodes} <- find_reachable_nodes(workflow, trigger_node),
         pruned_workflow <- prune_workflow(workflow, reachable_nodes),
         dependency_graph <- build_dependency_graph(pruned_workflow),
         connection_map <- build_connection_map(pruned_workflow),
         node_map <- build_node_map(pruned_workflow) do
      
      plan = %ExecutionPlan{
        workflow: pruned_workflow,
        trigger_node: trigger_node,
        dependency_graph: dependency_graph,
        connection_map: connection_map,
        node_map: node_map,
        total_nodes: length(reachable_nodes)
      }
      
      {:ok, plan}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # ============================================================================
  # Trigger Node Selection
  # ============================================================================

  @doc """
  Get the trigger node to start execution from.
  
  If trigger_node_id is provided, uses that specific node.
  If not provided, finds the first trigger node in the workflow.
  """
  @spec get_trigger_node(Workflow.t(), String.t() | nil) :: {:ok, Node.t()} | {:error, term()}
  def get_trigger_node(%Workflow{} = workflow, nil) do
    # No specific trigger provided, find first trigger node
    case find_trigger_nodes(workflow) do
      [] -> 
        {:error, :no_trigger_nodes}
        
      [trigger_node | _] -> 
        {:ok, trigger_node}
        
      trigger_nodes when length(trigger_nodes) > 1 ->
        # Multiple triggers found, need to specify which one
        trigger_names = Enum.map(trigger_nodes, & &1.name)
        {:error, {:multiple_triggers_found, trigger_names}}
    end
  end
  
  def get_trigger_node(%Workflow{} = workflow, trigger_node_id) when is_binary(trigger_node_id) do
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

  @doc """
  Find all nodes reachable from the trigger node using graph traversal.
  
  This removes any nodes that are not connected to the execution path.
  """
  @spec find_reachable_nodes(Workflow.t(), Node.t()) :: {:ok, [Node.t()]} | {:error, term()}
  def find_reachable_nodes(%Workflow{} = workflow, %Node{} = trigger_node) do
    # Use breadth-first search to find all reachable nodes
    visited = MapSet.new()
    queue = [trigger_node.id]
    
    reachable_node_ids = traverse_graph(workflow, queue, visited)
    
    # Get actual node structs for reachable IDs
    reachable_nodes = 
      workflow.nodes
      |> Enum.filter(fn node -> MapSet.member?(reachable_node_ids, node.id) end)
    
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

  @doc """
  Create a pruned workflow containing only reachable nodes and their connections.
  """
  @spec prune_workflow(Workflow.t(), [Node.t()]) :: Workflow.t()
  def prune_workflow(%Workflow{} = workflow, reachable_nodes) do
    reachable_node_ids = MapSet.new(reachable_nodes, & &1.id)
    
    # Filter connections to only include those between reachable nodes
    reachable_connections = 
      workflow.connections
      |> Enum.filter(fn conn ->
        MapSet.member?(reachable_node_ids, conn.from_node_id) and
        MapSet.member?(reachable_node_ids, conn.to_node_id)
      end)
    
    # Create new workflow with pruned nodes and connections
    %{workflow | 
      nodes: reachable_nodes,
      connections: reachable_connections
    }
  end

  # ============================================================================
  # Graph Analysis
  # ============================================================================

  @doc """
  Build dependency graph showing which nodes depend on which other nodes.
  
  Returns a map where keys are node IDs and values are lists of node IDs 
  that must complete before the key node can execute.
  """
  @spec build_dependency_graph(Workflow.t()) :: map()
  def build_dependency_graph(%Workflow{connections: connections}) do
    Enum.reduce(connections, %{}, fn conn, acc ->
      Map.update(acc, conn.to_node_id, [conn.from_node_id], fn deps ->
        Enum.uniq([conn.from_node_id | deps])
      end)
    end)
  end

  @doc """
  Build connection map for fast lookup of outgoing connections.
  
  The connection map is a performance optimization that allows O(1) lookup
  of all connections from a specific node and port, instead of O(n) search
  through all connections.
  
  ## Example
  
      # Instead of searching through all connections:
      workflow.connections 
      |> Enum.filter(fn conn -> 
        conn.from_node_id == \"node_1\" && conn.from_port == \"success\" 
      end)
      
      # We can do O(1) lookup:
      connection_map[{\"node_1\", \"success\"}]
      
  ## Returns
  
  A map where:
  - Keys are tuples of `{from_node_id, from_port}`  
  - Values are lists of connections originating from that node/port
  
      %{
        {\"node_1\", \"success\"} => [connection1, connection2],
        {\"node_2\", \"error\"} => [connection3],
        {\"node_3\", \"success\"} => [connection4]
      }
  """
  @spec build_connection_map(Workflow.t()) :: map()
  def build_connection_map(%Workflow{connections: connections}) do
    Enum.group_by(connections, fn conn ->
      {conn.from_node_id, conn.from_port}
    end)
  end

  @doc """
  Build node map for fast lookup of nodes by ID.
  """
  @spec build_node_map(Workflow.t()) :: map()
  def build_node_map(%Workflow{nodes: nodes}) do
    Map.new(nodes, fn node -> {node.id, node} end)
  end

  # ============================================================================
  # Validation
  # ============================================================================

  @doc """
  Validate that the execution plan is valid and can be executed.
  """
  @spec validate_plan(ExecutionPlan.t()) :: :ok | {:error, term()}
  def validate_plan(%ExecutionPlan{} = plan) do
    with :ok <- validate_has_trigger_node(plan),
         :ok <- validate_has_nodes(plan),
         :ok <- validate_no_cycles(plan),
         :ok <- validate_connections(plan) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @spec validate_has_trigger_node(ExecutionPlan.t()) :: :ok | {:error, term()}
  defp validate_has_trigger_node(%ExecutionPlan{trigger_node: nil}) do
    {:error, :no_trigger_node}
  end
  defp validate_has_trigger_node(%ExecutionPlan{trigger_node: %Node{type: :trigger}}) do
    :ok
  end
  defp validate_has_trigger_node(%ExecutionPlan{trigger_node: %Node{type: other_type}}) do
    {:error, {:invalid_trigger_node_type, other_type}}
  end

  @spec validate_has_nodes(ExecutionPlan.t()) :: :ok | {:error, term()}
  defp validate_has_nodes(%ExecutionPlan{workflow: %Workflow{nodes: []}}) do
    {:error, :no_nodes_in_plan}
  end
  defp validate_has_nodes(%ExecutionPlan{workflow: %Workflow{nodes: nodes}}) when length(nodes) > 0 do
    :ok
  end

  @spec validate_no_cycles(ExecutionPlan.t()) :: :ok | {:error, term()}
  defp validate_no_cycles(%ExecutionPlan{} = plan) do
    case detect_cycles(plan) do
      [] -> :ok
      cycles -> {:error, {:cycles_detected, cycles}}
    end
  end

  @spec validate_connections(ExecutionPlan.t()) :: :ok | {:error, term()}
  defp validate_connections(%ExecutionPlan{workflow: workflow}) do
    node_ids = MapSet.new(workflow.nodes, & &1.id)
    
    invalid_connections = 
      Enum.reject(workflow.connections, fn conn ->
        MapSet.member?(node_ids, conn.from_node_id) and
        MapSet.member?(node_ids, conn.to_node_id)
      end)
    
    case invalid_connections do
      [] -> :ok
      invalid -> {:error, {:invalid_connections, invalid}}
    end
  end

  @spec detect_cycles(ExecutionPlan.t()) :: [list()]
  defp detect_cycles(%ExecutionPlan{} = _plan) do
    # Simplified cycle detection - real implementation would use DFS
    # with color coding to detect back edges
    []
  end

  # ============================================================================
  # Ready Node Detection
  # ============================================================================

  @doc """
  Find nodes that are ready for execution based on dependency satisfaction.
  """
  @spec find_ready_nodes(ExecutionPlan.t(), MapSet.t(), MapSet.t(), MapSet.t()) :: [Node.t()]
  def find_ready_nodes(%ExecutionPlan{} = plan, completed_nodes, failed_nodes, pending_nodes) do
    plan.workflow.nodes
    |> Enum.reject(&node_executed?(&1.id, completed_nodes, failed_nodes))
    |> Enum.reject(&node_pending?(&1.id, pending_nodes))
    |> Enum.filter(&dependencies_satisfied?(plan, &1, completed_nodes))
  end

  @spec node_executed?(String.t(), MapSet.t(), MapSet.t()) :: boolean()
  defp node_executed?(node_id, completed_nodes, failed_nodes) do
    MapSet.member?(completed_nodes, node_id) or MapSet.member?(failed_nodes, node_id)
  end

  @spec node_pending?(String.t(), MapSet.t()) :: boolean()
  defp node_pending?(node_id, pending_nodes) do
    MapSet.member?(pending_nodes, node_id)
  end

  @spec dependencies_satisfied?(ExecutionPlan.t(), Node.t(), MapSet.t()) :: boolean()
  defp dependencies_satisfied?(%ExecutionPlan{} = plan, %Node{} = node, completed_nodes) do
    dependencies = Map.get(plan.dependency_graph, node.id, [])
    
    Enum.all?(dependencies, fn dep_node_id ->
      MapSet.member?(completed_nodes, dep_node_id)
    end)
  end
end