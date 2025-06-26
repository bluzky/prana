defmodule Prana.ExecutionGraph do
  @moduledoc """
  Execution graph containing workflow analysis and execution optimization.
  
  The compiled output of WorkflowCompiler containing:
  - Pruned workflow (only reachable nodes)
  - Pre-built lookup maps for O(1) performance
  - Dependency graph for execution ordering
  - Trigger node as execution entry point
  
  ## Example
  
      # Original workflow: 7 nodes, 2 unreachable
      workflow = %Workflow{
        nodes: [webhook, validate, save, email, log, orphan_a, orphan_b],
        connections: [webhook→validate, webhook→log, validate→save, save→email, orphan_a→orphan_b]
      }
      
      # Compiled execution graph: 5 nodes, optimized
      {:ok, graph} = WorkflowCompiler.compile(workflow)
      %ExecutionGraph{
        workflow: %Workflow{nodes: [webhook, validate, save, email, log]},  # Pruned
        trigger_node: webhook,
        dependency_graph: %{
          "validate" => ["webhook"],
          "log" => ["webhook"], 
          "save" => ["validate"],
          "email" => ["save"]
        },
        connection_map: %{
          {"webhook", "success"} => [conn_to_validate, conn_to_log],
          {"validate", "success"} => [conn_to_save],
          {"save", "success"} => [conn_to_email]
        },
        node_map: %{
          "webhook" => webhook_node,
          "validate" => validate_node,
          # ...
        },
        total_nodes: 5
      }
  """
  
  alias Prana.{Workflow, Node}
  
  defstruct [
    :workflow,            # Compiled workflow with only reachable nodes
    :trigger_node,        # The specific trigger node that started execution
    :dependency_graph,    # Map of node_id -> [prerequisite_node_ids]
    :connection_map,      # Map of {from_node, from_port} -> [connections]
    :reverse_connection_map, # Map of to_node_id -> [incoming_connections] for O(1) lookup
    :node_map,           # Map of node_id -> node for quick lookup
    :total_nodes         # Total number of nodes in compiled workflow
  ]
  
  @type t :: %__MODULE__{
    workflow: Workflow.t(),
    trigger_node: Node.t(),
    dependency_graph: map(),
    connection_map: map(),
    reverse_connection_map: map(),
    node_map: map(),
    total_nodes: integer()
  }
end
