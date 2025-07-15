defmodule Prana.ExecutionGraph.Migration do
  @moduledoc """
  Migration utilities for converting between legacy and new ExecutionGraph formats.
  
  This module provides conversion functions to enable gradual migration from the 
  current ExecutionGraph structure to the new embedded architecture format.
  
  ## Usage
  
      # Convert legacy ExecutionGraph to new format
      new_graph = Migration.from_legacy(old_execution_graph)
      
      # Convert new format back to legacy (for compatibility)
      {execution, execution_graph} = Migration.to_legacy_execution_format(new_execution)
  """
  
  alias Prana.Execution.V2, as: ExecutionV2
  alias Prana.ExecutionGraph
  
  @doc """
  Convert legacy ExecutionGraph structure to new embedded format.
  
  ## Parameters
  - `legacy_execution_graph` - The old ExecutionGraph struct with workflow field
  
  ## Returns
  New ExecutionGraph struct with optimized fields and removed redundancy
  """
  def from_legacy(%{workflow: workflow, trigger_node: trigger_node} = legacy_graph) do
    ExecutionGraph.new(
      workflow.id,
      workflow.version || 1,
      trigger_node.key,
      Map.get(legacy_graph, :node_map, build_node_map_from_workflow(workflow)),
      Map.get(legacy_graph, :connection_map, %{}),
      Map.get(legacy_graph, :reverse_connection_map, %{}),
      Map.get(legacy_graph, :dependency_graph, %{})
    )
  end
  
  @doc """
  Convert new ExecutionGraph back to legacy format for compatibility.
  
  This should only be used during the migration period to maintain 
  backward compatibility with existing code.
  
  ## Parameters
  - `execution_graph` - The new ExecutionGraph struct
  
  ## Returns
  Legacy ExecutionGraph struct with workflow field populated
  """
  def to_legacy(%ExecutionGraph{} = graph) do
    # Reconstruct workflow from graph data
    workflow = %Prana.Workflow{
      id: graph.workflow_id,
      version: graph.workflow_version,
      nodes: Map.values(graph.nodes),
      connections: reconstruct_connections_from_map(graph.connection_map)
    }
    
    trigger_node = ExecutionGraph.get_trigger_node(graph)
    
    # Build legacy ExecutionGraph struct
    %{
      workflow: workflow,
      trigger_node: trigger_node,
      dependency_graph: graph.dependency_graph,
      connection_map: graph.connection_map,
      reverse_connection_map: graph.reverse_connection_map,
      node_map: graph.nodes,
      total_nodes: ExecutionGraph.node_count(graph)
    }
  end
  
  @doc """
  Convert execution with embedded ExecutionGraph to legacy format.
  
  This creates separate Execution and ExecutionGraph structs as used
  in the current system, for backward compatibility.
  
  ## Parameters
  - `execution` - Execution with embedded execution_graph
  
  ## Returns
  Tuple of {legacy_execution, legacy_execution_graph}
  """
  def to_legacy_execution_format(%ExecutionV2{execution_graph: graph} = execution) do
    # Create legacy ExecutionGraph
    legacy_execution_graph = to_legacy(graph)
    
    # Create legacy Execution (without execution_graph field)
    legacy_execution = Map.drop(execution, [:execution_graph])
    
    {legacy_execution, legacy_execution_graph}
  end
  
  @doc """
  Create execution with embedded ExecutionGraph from legacy format.
  
  ## Parameters
  - `legacy_execution` - Legacy Execution struct
  - `legacy_execution_graph` - Legacy ExecutionGraph struct  
  
  ## Returns
  New Execution struct with embedded ExecutionGraph
  """
  def from_legacy_execution_format(%Prana.Execution{} = legacy_execution, legacy_execution_graph) do
    # Convert ExecutionGraph to new format
    new_execution_graph = from_legacy(legacy_execution_graph)
    
    # Embed in execution
    Map.put(legacy_execution, :execution_graph, new_execution_graph)
  end
  
  # Helper function to build node_map from workflow nodes
  defp build_node_map_from_workflow(%{nodes: nodes}) do
    Enum.reduce(nodes, %{}, fn node, acc ->
      Map.put(acc, node.key, node)
    end)
  end
  
  # Helper function to reconstruct connections from connection_map
  defp reconstruct_connections_from_map(connection_map) do
    connection_map
    |> Enum.group_by(fn {{from_node, _port}, _connections} -> from_node end)
    |> Enum.reduce(%{}, fn {node_key, entries}, acc ->
      ports_map = 
        entries
        |> Enum.reduce(%{}, fn {{_node, port}, connections}, port_acc ->
          Map.put(port_acc, port, connections)
        end)
      
      Map.put(acc, node_key, ports_map)
    end)
  end
end