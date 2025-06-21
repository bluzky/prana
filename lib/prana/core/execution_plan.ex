defmodule Prana.ExecutionPlan do
  @moduledoc """
  Execution plan containing workflow analysis and execution strategy.
  """
  
  alias Prana.{Workflow, Node}
  
  defstruct [
    :workflow,            # Pruned workflow with only reachable nodes
    :trigger_node,        # The specific trigger node that started execution
    :dependency_graph,    # Map of node_id -> [dependent_node_ids]
    :connection_map,      # Map of {from_node, from_port} -> [connections]
    :node_map,           # Map of node_id -> node for quick lookup
    :total_nodes         # Total number of nodes in pruned workflow
  ]
  
  @type t :: %__MODULE__{
    workflow: Workflow.t(),
    trigger_node: Node.t(),
    dependency_graph: map(),
    connection_map: map(),
    node_map: map(),
    total_nodes: integer()
  }
end
