defmodule Prana.Execution.Adapter do
  @moduledoc """
  Adapter for converting between ExecutionV2 and legacy Execution structs.
  
  This module provides compatibility functions for working with NodeExecutor
  and other components that expect the legacy Execution format while
  using the new embedded ExecutionGraph architecture internally.
  """
  
  alias Prana.Execution
  alias Prana.Execution.V2, as: ExecutionV2
  
  @doc """
  Convert ExecutionV2 to legacy Execution format for NodeExecutor compatibility.
  
  ## Parameters
  - `execution_v2` - ExecutionV2 with embedded ExecutionGraph
  
  ## Returns
  Legacy Execution struct compatible with NodeExecutor
  """
  def to_legacy_execution(%ExecutionV2{} = execution_v2) do
    # Create minimal legacy execution with required fields for NodeExecutor
    %Execution{
      id: execution_v2.id,
      workflow_id: execution_v2.execution_graph.workflow_id,
      workflow_version: execution_v2.execution_graph.workflow_version,
      status: execution_v2.status,
      started_at: execution_v2.started_at,
      completed_at: execution_v2.completed_at,
      parent_execution_id: execution_v2.parent_execution_id,
      execution_mode: execution_v2.execution_mode,
      trigger_type: execution_v2.trigger_type,
      trigger_data: execution_v2.trigger_data,
      current_execution_index: execution_v2.current_execution_index,
      
      # Map ExecutionV2 fields to legacy format
      node_executions: execution_v2.node_executions,
      vars: execution_v2.variables,
      metadata: execution_v2.metadata,
      preparation_data: execution_v2.preparation_data,
      
      # Build __runtime from ExecutionV2 state
      __runtime: build_legacy_runtime(execution_v2),
      
      # Handle suspension fields
      suspended_node_id: get_suspended_node_id(execution_v2),
      suspension_type: get_suspension_type(execution_v2),
      suspension_data: get_suspension_data(execution_v2),
      suspended_at: get_suspended_at(execution_v2),
      
      # Default values for unused legacy fields
      error_data: Map.get(execution_v2.metadata, "error_data"),
      output_data: Map.get(execution_v2.metadata, "output_data"),
      context_data: %{},
      resume_token: nil,
      root_execution_id: execution_v2.id
    }
  end
  
  @doc """
  Update ExecutionV2 with changes from legacy Execution after NodeExecutor operations.
  
  ## Parameters
  - `execution_v2` - Original ExecutionV2 struct
  - `legacy_execution` - Updated legacy Execution from NodeExecutor
  
  ## Returns
  Updated ExecutionV2 with changes merged
  """
  def from_legacy_execution(%ExecutionV2{} = execution_v2, %Execution{} = legacy_execution) do
    # Update ExecutionV2 with changes from legacy execution
    %{execution_v2 |
      status: legacy_execution.status,
      completed_at: legacy_execution.completed_at,
      current_execution_index: legacy_execution.current_execution_index,
      node_executions: legacy_execution.node_executions,
      variables: legacy_execution.vars,
      metadata: merge_metadata(execution_v2.metadata, legacy_execution),
      preparation_data: legacy_execution.preparation_data,
      
      # Update runtime state from legacy __runtime
      completed_nodes: Map.get(legacy_execution.__runtime, "nodes", execution_v2.completed_nodes),
      
      # Update suspension state if changed
      suspension: build_suspension_from_legacy(legacy_execution)
    }
  end
  
  # Private helper functions
  
  defp build_legacy_runtime(%ExecutionV2{} = execution_v2) do
    %{
      "nodes" => execution_v2.completed_nodes,
      "env" => execution_v2.environment,
      "active_nodes" => execution_v2.active_nodes,
      "executed_nodes" => get_executed_nodes_list(execution_v2),
      "iteration_count" => execution_v2.iteration_count,
      "node_depth" => execution_v2.node_depth
    }
  end
  
  defp get_executed_nodes_list(%ExecutionV2{} = execution_v2) do
    # Extract executed nodes from node_executions in execution order
    execution_v2.node_executions
    |> Enum.flat_map(fn {_node_key, executions} -> executions end)
    |> Enum.sort_by(& &1.execution_index)
    |> Enum.map(& &1.node_key)
  end
  
  defp get_suspended_node_id(%ExecutionV2{suspension: nil}), do: nil
  defp get_suspended_node_id(%ExecutionV2{suspension: %{node_id: node_id}}), do: node_id
  
  defp get_suspension_type(%ExecutionV2{suspension: nil}), do: nil
  defp get_suspension_type(%ExecutionV2{suspension: %{type: type}}), do: type
  
  defp get_suspension_data(%ExecutionV2{suspension: nil}), do: nil
  defp get_suspension_data(%ExecutionV2{suspension: %{data: data}}), do: data
  
  defp get_suspended_at(%ExecutionV2{suspension: nil}), do: nil
  defp get_suspended_at(%ExecutionV2{suspension: %{suspended_at: suspended_at}}), do: suspended_at
  
  defp merge_metadata(v2_metadata, %Execution{} = legacy_execution) do
    v2_metadata
    |> Map.put("error_data", legacy_execution.error_data)
    |> Map.put("output_data", legacy_execution.output_data)
    |> Map.merge(legacy_execution.metadata)
  end
  
  defp build_suspension_from_legacy(%Execution{suspended_node_id: nil}), do: nil
  defp build_suspension_from_legacy(%Execution{} = legacy_execution) do
    if legacy_execution.suspended_node_id do
      %{
        node_id: legacy_execution.suspended_node_id,
        type: legacy_execution.suspension_type || :unknown,
        data: legacy_execution.suspension_data || %{},
        suspended_at: legacy_execution.suspended_at || DateTime.utc_now()
      }
    else
      nil
    end
  end
end