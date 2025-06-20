defmodule Prana.Adapters.InMemory do
  @moduledoc """
  In-memory storage adapter using ETS tables.
  Suitable for development, testing, and single-node deployments.
  """
  
  @behaviour Prana.Behaviour.StorageAdapter

  use GenServer
  require Logger

  @tables [
    :workflows, 
    :executions, 
    :node_executions, 
    :suspended_executions
  ]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl Prana.Behaviour.StorageAdapter
  def validate_config(_config) do
    # In-memory adapter doesn't need external configuration
    :ok
  end

  @impl Prana.Behaviour.StorageAdapter
  def init_adapter(config) do
    GenServer.call(__MODULE__, {:init_adapter, config})
  end



  # Workflow operations
  @impl Prana.Behaviour.StorageAdapter
  def create_workflow(workflow) do
    :ets.insert(:workflows, {workflow.id, workflow})
    {:ok, workflow}
  end

  @impl Prana.Behaviour.StorageAdapter
  def get_workflow(id) do
    case :ets.lookup(:workflows, id) do
      [{^id, workflow}] -> {:ok, workflow}
      [] -> {:error, :not_found}
    end
  end

  @impl Prana.Behaviour.StorageAdapter
  def update_workflow(workflow) do
    :ets.insert(:workflows, {workflow.id, workflow})
    {:ok, workflow}
  end

  @impl Prana.Behaviour.StorageAdapter
  def delete_workflow(id) do
    :ets.delete(:workflows, id)
    :ok
  end

  @impl Prana.Behaviour.StorageAdapter
  def list_workflows(filters \\ %{}) do
    workflows = 
      :ets.tab2list(:workflows) 
      |> Enum.map(fn {_id, workflow} -> workflow end)
      |> apply_filters(filters)
    
    {:ok, workflows}
  end

  # Execution operations
  @impl Prana.Behaviour.StorageAdapter
  def create_execution(execution) do
    :ets.insert(:executions, {execution.id, execution})
    {:ok, execution}
  end

  @impl Prana.Behaviour.StorageAdapter
  def get_execution(id) do
    case :ets.lookup(:executions, id) do
      [{^id, execution}] -> {:ok, execution}
      [] -> {:error, :not_found}
    end
  end

  @impl Prana.Behaviour.StorageAdapter
  def update_execution(execution) do
    :ets.insert(:executions, {execution.id, execution})
    {:ok, execution}
  end

  @impl Prana.Behaviour.StorageAdapter
  def list_executions(workflow_id) do
    executions = 
      :ets.tab2list(:executions)
      |> Enum.map(fn {_id, execution} -> execution end)
      |> Enum.filter(&(&1.workflow_id == workflow_id))
      |> Enum.sort_by(& &1.created_at, {:desc, DateTime})
    
    {:ok, executions}
  end

  # Node execution operations
  @impl Prana.Behaviour.StorageAdapter
  def create_node_execution(node_execution) do
    :ets.insert(:node_executions, {node_execution.id, node_execution})
    {:ok, node_execution}
  end

  @impl Prana.Behaviour.StorageAdapter
  def update_node_execution(node_execution) do
    :ets.insert(:node_executions, {node_execution.id, node_execution})
    {:ok, node_execution}
  end

  @impl Prana.Behaviour.StorageAdapter
  def get_node_executions(execution_id) do
    node_executions = 
      :ets.tab2list(:node_executions)
      |> Enum.map(fn {_id, node_execution} -> node_execution end)
      |> Enum.filter(&(&1.execution_id == execution_id))
      |> Enum.sort_by(& &1.started_at, {:asc, DateTime})
    
    {:ok, node_executions}
  end

  # State management
  @impl Prana.Behaviour.StorageAdapter
  def suspend_execution(execution_id, resume_token) do
    :ets.insert(:suspended_executions, {execution_id, resume_token})
    :ok
  end

  @impl Prana.Behaviour.StorageAdapter
  def resume_execution(execution_id) do
    case :ets.lookup(:suspended_executions, execution_id) do
      [{^execution_id, _resume_token}] ->
        :ets.delete(:suspended_executions, execution_id)
        get_execution(execution_id)
      [] ->
        {:error, :not_found}
    end
  end

  @impl Prana.Behaviour.StorageAdapter
  def get_suspended_executions do
    suspended = 
      :ets.tab2list(:suspended_executions)
      |> Enum.map(fn {execution_id, _token} -> execution_id end)
      |> Enum.map(fn execution_id ->
        {:ok, execution} = get_execution(execution_id)
        execution
      end)
    
    {:ok, suspended}
  end

  @impl Prana.Behaviour.StorageAdapter
  def health_check do
    try do
      # Check if all tables exist and are accessible
      Enum.each(@tables, fn table ->
        info = :ets.info(table)
        if is_nil(info), do: throw({:error, "Table #{table} not found"})
      end)
      
      :ok
    catch
      {:error, reason} -> {:error, reason}
      _ -> {:error, "Unknown health check error"}
    end
  end

  # GenServer callbacks

  @impl GenServer
  def init(_opts) do
    tables = 
      Enum.map(@tables, fn table ->
        table_id = :ets.new(table, [:set, :public, :named_table])
        {table, table_id}
      end)
      |> Map.new()
    
    Logger.info("Initialized Prana in-memory storage adapter with tables: #{inspect(Map.keys(tables))}")
    {:ok, %{tables: tables, config: %{}}}
  end

  @impl GenServer
  def handle_call({:init_adapter, config}, _from, state) do
    new_state = %{state | config: config}
    Logger.info("Prana in-memory adapter initialized with config: #{inspect(config)}")
    {:reply, {:ok, new_state}, new_state}
  end

  @impl GenServer
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  # Helper functions

  defp apply_filters(workflows, filters) when map_size(filters) == 0, do: workflows
  defp apply_filters(workflows, filters) do
    Enum.filter(workflows, fn workflow ->
      Enum.all?(filters, fn {key, value} ->
        case key do
          :status -> workflow.status == value
          :tags -> value in workflow.tags
          :created_after -> DateTime.compare(workflow.created_at, value) != :lt
          :created_before -> DateTime.compare(workflow.created_at, value) != :gt
          :name_contains -> String.contains?(String.downcase(workflow.name), String.downcase(value))
          _ -> true
        end
      end)
    end)
  end

  # Public helper functions for testing/debugging

  @doc """
  Get current adapter state (for debugging)
  """
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  @doc """
  Clear all data from tables (for testing)
  """
  def clear_all_data do
    Enum.each(@tables, fn table ->
      :ets.delete_all_objects(table)
    end)
    
    Logger.info("Cleared all data from Prana in-memory storage")
    :ok
  end

  @doc """
  Get statistics about stored data
  """
  def get_statistics do
    stats = 
      Enum.map(@tables, fn table ->
        size = :ets.info(table, :size)
        {table, size}
      end)
      |> Map.new()
    
    {:ok, stats}
  end

  @doc """
  Export all data (for backup/testing)
  """
  def export_data do
    data = 
      Enum.map(@tables, fn table ->
        records = :ets.tab2list(table)
        {table, records}
      end)
      |> Map.new()
    
    {:ok, data}
  end

  @doc """
  Import data (for restore/testing)
  """
  def import_data(data) when is_map(data) do
    Enum.each(data, fn {table, records} ->
      if table in @tables do
        :ets.delete_all_objects(table)
        :ets.insert(table, records)
      end
    end)
    
    Logger.info("Imported data to Prana in-memory storage")
    :ok
  end
end
