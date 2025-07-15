defmodule Prana.Execution.V2 do
  @moduledoc """
  Execution instance with embedded ExecutionGraph for clean single-parameter APIs.
  
  CONTAINS: ExecutionGraph (loaded from application cache)
  RESPONSIBILITY: Runtime state, audit trail, execution coordination  
  PERSISTENCE: Only execution fields stored (execution_graph excluded)
  
  ## Embedded ExecutionGraph Architecture
  
  This version embeds ExecutionGraph as an attribute, enabling clean APIs:
  - `execute_workflow(execution)` instead of `execute_graph(graph, context)`
  - `resume_workflow(execution, data)` instead of `resume_workflow(exec, data, graph, context)`
  
  ## Storage Separation
  
  The ExecutionGraph is excluded from persistence and loaded from application cache:
  
      # Persistence (execution_graph excluded)
      stored_data = Execution.V2.to_storage_format(execution)
      
      # Loading (execution_graph loaded from cache)
      execution = Execution.V2.from_storage_format(stored_data, cached_graph)
  
  ## Suspension Consolidation
  
  Multiple suspension fields consolidated into single map for clean organization:
  
      execution.suspension = %{
        node_id: "webhook_123",
        type: :webhook,
        data: %{wait_till: ~U[2025-01-15 10:00:00Z]},
        suspended_at: ~U[2025-01-15 09:00:00Z]
      }
  """
  
  alias Prana.ExecutionGraph
  
  @type status :: :pending | :running | :suspended | :completed | :failed | :cancelled | :timeout
  @type execution_mode :: :sync | :async | :fire_and_forget
  
  @type t :: %__MODULE__{
          # 🏗️ EMBEDDED STATIC WORKFLOW (loaded by application from cache)
          execution_graph: ExecutionGraph.t(),
          
          # 📋 EXECUTION METADATA
          id: String.t(),
          status: status(),
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          parent_execution_id: String.t() | nil,
          execution_mode: execution_mode(),
          trigger_type: String.t(),
          trigger_data: map(),
          current_execution_index: integer(),
          
          # ⚡ RUNTIME EXECUTION STATE (ephemeral, rebuilt on load)
          active_nodes: MapSet.t(String.t()),
          node_depth: %{String.t() => integer()},
          completed_nodes: %{String.t() => map()},
          iteration_count: integer(),
          
          # 📝 PERSISTENT AUDIT TRAIL
          node_executions: %{String.t() => [Prana.NodeExecution.t()]},
          
          # 🔄 SUSPENSION STATE (transient coordination)
          suspension: %{
            node_id: String.t(),
            type: atom(),
            data: map(),
            suspended_at: DateTime.t()
          } | nil,
          
          # 🌍 EXECUTION CONTEXT
          variables: map(),
          environment: map(),
          preparation_data: map(),
          metadata: map()
        }
  
  defstruct [
    # Embedded ExecutionGraph
    :execution_graph,
    
    # Execution metadata
    :id,
    :status,
    :started_at,
    :completed_at,
    :parent_execution_id,
    :execution_mode,
    :trigger_type,
    :trigger_data,
    :current_execution_index,
    
    # Runtime state (ephemeral)
    :active_nodes,
    :node_depth,
    :completed_nodes,
    :iteration_count,
    
    # Persistent audit trail
    :node_executions,
    
    # Consolidated suspension state
    :suspension,
    
    # Context
    variables: %{},
    environment: %{},
    preparation_data: %{},
    metadata: %{}
  ]
  
  @doc """
  Creates a new execution with embedded ExecutionGraph.
  
  ## Parameters
  - `execution_graph` - Pre-compiled ExecutionGraph from application cache
  - `context` - Optional context with variables, environment, metadata
  
  ## Returns
  New execution ready for workflow execution
  """
  def new(%ExecutionGraph{} = execution_graph, context \\ %{}) do
    execution_id = generate_id()
    
    %__MODULE__{
      execution_graph: execution_graph,
      id: execution_id,
      status: :pending,
      started_at: nil,
      completed_at: nil,
      parent_execution_id: Map.get(context, :parent_execution_id),
      execution_mode: Map.get(context, :execution_mode, :async),
      trigger_type: "graph_executor",
      trigger_data: Map.get(context, :trigger_data, %{}),
      current_execution_index: 0,
      
      # Initialize runtime state
      active_nodes: MapSet.new([execution_graph.trigger_node_key]),
      node_depth: %{execution_graph.trigger_node_key => 0},
      completed_nodes: %{},
      iteration_count: 0,
      
      # Initialize audit trail
      node_executions: %{},
      
      # No suspension initially
      suspension: nil,
      
      # Context
      variables: Map.get(context, :variables, %{}),
      environment: Map.get(context, :environment, %{}),
      preparation_data: %{},
      metadata: Map.get(context, :metadata, %{})
    }
  end
  
  @doc """
  Marks execution as started.
  """
  def start(%__MODULE__{} = execution) do
    %{execution | status: :running, started_at: DateTime.utc_now()}
  end
  
  @doc """
  Marks execution as completed.
  """
  def complete(%__MODULE__{} = execution, output_data \\ %{}) do
    %{execution | 
      status: :completed, 
      completed_at: DateTime.utc_now(),
      metadata: Map.put(execution.metadata, "output_data", output_data)
    }
  end
  
  @doc """
  Marks execution as failed.
  """
  def fail(%__MODULE__{} = execution, error_data) do
    %{execution | 
      status: :failed, 
      completed_at: DateTime.utc_now(),
      metadata: Map.put(execution.metadata, "error_data", error_data)
    }
  end
  
  @doc """
  Suspends execution with consolidated suspension data.
  
  ## Parameters
  - `execution` - The execution to suspend
  - `node_id` - ID of the node that caused suspension
  - `suspension_type` - Type of suspension (:webhook, :interval, etc.)
  - `suspension_data` - Suspension-specific data
  
  ## Example
  
      suspension_data = %{wait_till: DateTime.add(DateTime.utc_now(), 3600, :second)}
      execution = suspend(execution, "webhook_node", :webhook, suspension_data)
  """
  def suspend(%__MODULE__{} = execution, node_id, suspension_type, suspension_data) do
    suspension = %{
      node_id: node_id,
      type: suspension_type,
      data: suspension_data,
      suspended_at: DateTime.utc_now()
    }
    
    %{execution | status: :suspended, suspension: suspension}
  end
  
  @doc """
  Resumes a suspended execution by clearing suspension state.
  """
  def resume_suspension(%__MODULE__{} = execution) do
    %{execution | suspension: nil}
  end
  
  @doc """
  Completes a node execution and updates runtime state.
  """
  def complete_node(%__MODULE__{} = execution, node_key, output_data, output_port) do
    execution
    |> update_completed_nodes(node_key, output_data)
    |> route_to_next_nodes(node_key, output_port)
    |> update_active_nodes_and_depths()
  end
  
  @doc """
  Gets ready nodes for execution based on dependencies and active nodes.
  """
  def get_ready_nodes(%__MODULE__{} = execution) do
    execution.active_nodes
    |> Enum.map(&ExecutionGraph.get_node(execution.execution_graph, &1))
    |> Enum.filter(& &1)  # Remove nil entries
    |> Enum.filter(&dependencies_satisfied?(&1, execution))
  end
  
  @doc """
  Gets multi-port input data for a node by routing from completed nodes.
  """
  def get_node_input(%__MODULE__{} = execution, node_key) do
    node = ExecutionGraph.get_node(execution.execution_graph, node_key)
    
    if node do
      resolve_multi_port_input(execution, node)
    else
      %{}
    end
  end
  
  @doc """
  Converts execution to storage format (excludes execution_graph).
  
  ## Returns
  Map suitable for persistence, with execution_graph excluded
  """
  def to_storage_format(%__MODULE__{} = execution) do
    execution
    |> Map.from_struct()
    |> Map.drop([:execution_graph])
  end
  
  @doc """
  Reconstructs execution from storage format with embedded ExecutionGraph.
  
  ## Parameters
  - `stored_execution` - Map from storage (without execution_graph)
  - `execution_graph` - ExecutionGraph loaded from application cache
  
  ## Returns
  Full execution with embedded ExecutionGraph
  """
  def from_storage_format(stored_execution, %ExecutionGraph{} = execution_graph) do
    struct(__MODULE__, Map.put(stored_execution, :execution_graph, execution_graph))
  end
  
  @doc """
  Checks if execution is in a terminal state.
  """
  def terminal?(%__MODULE__{status: status}) do
    status in [:completed, :failed, :cancelled]
  end
  
  @doc """
  Checks if execution is still running.
  """
  def running?(%__MODULE__{status: status}) do
    status in [:pending, :running, :suspended]
  end
  
  @doc """
  Checks if execution is suspended.
  """
  def suspended?(%__MODULE__{status: :suspended}), do: true
  def suspended?(%__MODULE__{}), do: false
  
  @doc """
  Gets suspension information if execution is suspended.
  
  ## Returns
  - `{:ok, suspension_info}` if suspended
  - `:not_suspended` if not suspended
  """
  def get_suspension_info(%__MODULE__{status: :suspended, suspension: suspension}) 
      when not is_nil(suspension) do
    {:ok, suspension}
  end
  
  def get_suspension_info(%__MODULE__{}), do: :not_suspended
  
  # Private helper functions
  
  defp generate_id do
    16 |> :crypto.strong_rand_bytes() |> Base.encode64() |> binary_part(0, 16)
  end
  
  defp update_completed_nodes(execution, node_key, output_data) do
    updated_completed_nodes = Map.put(execution.completed_nodes, node_key, output_data)
    %{execution | completed_nodes: updated_completed_nodes}
  end
  
  defp route_to_next_nodes(execution, node_key, output_port) do
    if output_port do
      connections = ExecutionGraph.get_outgoing_connections(execution.execution_graph, node_key, output_port)
      target_nodes = MapSet.new(connections, & &1.to)
      
      # Add target nodes to active_nodes
      updated_active_nodes = MapSet.union(execution.active_nodes, target_nodes)
      %{execution | active_nodes: updated_active_nodes}
    else
      execution
    end
  end
  
  defp update_active_nodes_and_depths(execution) do
    # Remove completed nodes from active_nodes and update depths
    # This is a simplified version - full implementation would handle depth calculation
    execution
  end
  
  defp dependencies_satisfied?(node, execution) do
    dependencies = ExecutionGraph.get_node_dependencies(execution.execution_graph, node.key)
    
    Enum.all?(dependencies, fn dep_node_key ->
      Map.has_key?(execution.completed_nodes, dep_node_key)
    end)
  end
  
  defp resolve_multi_port_input(_execution, _node) do
    # Simplified multi-port input resolution
    # Full implementation would route data based on connections and ports
    %{"input" => %{}}
  end
end