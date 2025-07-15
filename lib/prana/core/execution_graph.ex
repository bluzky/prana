defmodule Prana.ExecutionGraph do
  @moduledoc """
  Compiled workflow definition with optimization maps for embedded execution architecture.
  
  STATIC: Never changes after compilation
  CACHEABLE: Shared across multiple executions via immutable data sharing
  RESPONSIBILITY: Workflow structure and routing optimization
  
  This structure is designed to be embedded as an attribute in Execution structs,
  enabling clean single-parameter APIs while maintaining separation of concerns.

  ## Example

      # Original workflow: 7 nodes, 2 unreachable
      workflow = %Workflow{
        nodes: [webhook, validate, save, email, log, orphan_a, orphan_b],
        connections: %{
          "webhook" => %{"success" => [conn_to_validate, conn_to_log]},
          "validate" => %{"success" => [conn_to_save]},
          "save" => %{"success" => [conn_to_email]},
          "orphan_a" => %{"success" => [conn_to_orphan_b]}
        }
      }

      # Compiled execution graph: 5 nodes, optimized
      {:ok, graph} = WorkflowCompiler.compile(workflow)
      %ExecutionGraph{
        workflow_id: "wf_123",
        workflow_version: 1,
        trigger_node_key: "webhook",
        nodes: %{
          "webhook" => webhook_node,
          "validate" => validate_node,
          "save" => save_node,
          "email" => email_node,
          "log" => log_node
        },
        connection_map: %{
          {"webhook", "success"} => [conn_to_validate, conn_to_log],
          {"validate", "success"} => [conn_to_save],
          {"save", "success"} => [conn_to_email]
        },
        reverse_connection_map: %{
          "validate" => [conn_from_webhook],
          "log" => [conn_from_webhook],
          "save" => [conn_from_validate],
          "email" => [conn_from_save]
        },
        dependency_graph: %{
          "validate" => ["webhook"],
          "log" => ["webhook"],
          "save" => ["validate"],
          "email" => ["save"]
        }
      }

      # Usage in embedded architecture
      execution = %Execution{
        execution_graph: graph,  # Embedded from application cache
        id: "exec_456",
        status: :running,
        # ... other execution fields
      }
      
      # Clean single-parameter APIs
      GraphExecutor.execute_workflow(execution)
      GraphExecutor.resume_workflow(execution, resume_data)
  """

  alias Prana.Node

  defstruct [
    # 📊 STATIC WORKFLOW DATA (immutable after compilation)
    :workflow_id,
    :workflow_version,
    :trigger_node_key,
    
    # 🗺️ OPTIMIZED LOOKUP MAPS (for performance)
    :nodes,                    # %{node_key => Node.t()} - compiled nodes (replaces node_map)
    :connection_map,           # %{{from, port} => [Connection.t()]} - O(1) lookups
    :reverse_connection_map,   # %{node_key => [Connection.t()]} - incoming connections
    :dependency_graph          # map() - dependency resolution optimization
  ]

  @type t :: %__MODULE__{
          workflow_id: String.t(),
          workflow_version: integer(),
          trigger_node_key: String.t(),
          nodes: %{String.t() => Node.t()},
          connection_map: map(),
          reverse_connection_map: map(),
          dependency_graph: map()
        }
        
  @doc """
  Creates a new ExecutionGraph from workflow compilation.
  
  This function should typically be called by WorkflowCompiler, not directly.
  """
  def new(workflow_id, workflow_version, trigger_node_key, nodes, connection_map, reverse_connection_map, dependency_graph) do
    %__MODULE__{
      workflow_id: workflow_id,
      workflow_version: workflow_version,
      trigger_node_key: trigger_node_key,
      nodes: nodes,
      connection_map: connection_map,
      reverse_connection_map: reverse_connection_map,
      dependency_graph: dependency_graph
    }
  end
  
  @doc """
  Gets the trigger node from the execution graph.
  """
  def get_trigger_node(%__MODULE__{} = graph) do
    Map.get(graph.nodes, graph.trigger_node_key)
  end
  
  @doc """
  Gets a node by its key.
  """
  def get_node(%__MODULE__{} = graph, node_key) do
    Map.get(graph.nodes, node_key)
  end
  
  @doc """
  Gets all outgoing connections from a node's output port.
  """
  def get_outgoing_connections(%__MODULE__{} = graph, node_key, output_port) do
    Map.get(graph.connection_map, {node_key, output_port}, [])
  end
  
  @doc """
  Gets all incoming connections to a node.
  """
  def get_incoming_connections(%__MODULE__{} = graph, node_key) do
    Map.get(graph.reverse_connection_map, node_key, [])
  end
  
  @doc """
  Gets node dependencies (prerequisite nodes that must complete first).
  """
  def get_node_dependencies(%__MODULE__{} = graph, node_key) do
    Map.get(graph.dependency_graph, node_key, [])
  end
  
  @doc """
  Returns total number of nodes in the compiled workflow.
  """
  def node_count(%__MODULE__{} = graph) do
    map_size(graph.nodes)
  end
end
