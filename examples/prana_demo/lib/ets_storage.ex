defmodule PranaDemo.ETSStorage do
  @moduledoc """
  ETS-based storage implementation for workflow runner demo.
  
  This module provides in-memory storage for executions and workflows
  using ETS tables for demonstration purposes.
  """
  
  use GenServer
  require Logger
  
  @executions_table :prana_executions
  @workflows_table :prana_workflows
  
  ## Client API
  
  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end
  
  @doc """
  Store a workflow execution.
  """
  def store_execution(execution) do
    GenServer.call(__MODULE__, {:store_execution, execution})
  end
  
  @doc """
  Get an execution by ID.
  """
  def get_execution(execution_id) do
    GenServer.call(__MODULE__, {:get_execution, execution_id})
  end
  
  @doc """
  Update an execution.
  """
  def update_execution(execution) do
    GenServer.call(__MODULE__, {:update_execution, execution})
  end
  
  @doc """
  Store a workflow.
  """
  def store_workflow(workflow) do
    GenServer.call(__MODULE__, {:store_workflow, workflow})
  end
  
  @doc """
  Get a workflow by ID.
  """
  def get_workflow(workflow_id) do
    GenServer.call(__MODULE__, {:get_workflow, workflow_id})
  end
  
  @doc """
  List all executions.
  """
  def list_executions do
    GenServer.call(__MODULE__, :list_executions)
  end
  
  @doc """
  List all workflows.
  """
  def list_workflows do
    GenServer.call(__MODULE__, :list_workflows)
  end
  
  @doc """
  Clear all data (for testing).
  """
  def clear_all do
    GenServer.call(__MODULE__, :clear_all)
  end
  
  ## GenServer Implementation
  
  @impl true
  def init(_opts) do
    Logger.info("Starting ETS storage for workflow runner demo")
    
    # Create ETS tables
    :ets.new(@executions_table, [:set, :public, :named_table])
    :ets.new(@workflows_table, [:set, :public, :named_table])
    
    {:ok, %{}}
  end
  
  @impl true
  def handle_call({:store_execution, execution}, _from, state) do
    :ets.insert(@executions_table, {execution.id, execution})
    Logger.debug("Stored execution: #{execution.id}")
    {:reply, {:ok, execution}, state}
  end
  
  @impl true
  def handle_call({:get_execution, execution_id}, _from, state) do
    case :ets.lookup(@executions_table, execution_id) do
      [{^execution_id, execution}] ->
        {:reply, {:ok, execution}, state}
      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end
  
  @impl true
  def handle_call({:update_execution, execution}, _from, state) do
    :ets.insert(@executions_table, {execution.id, execution})
    Logger.debug("Updated execution: #{execution.id}")
    {:reply, {:ok, execution}, state}
  end
  
  @impl true
  def handle_call({:store_workflow, workflow}, _from, state) do
    :ets.insert(@workflows_table, {workflow.id, workflow})
    Logger.debug("Stored workflow: #{workflow.id}")
    {:reply, {:ok, workflow}, state}
  end
  
  @impl true
  def handle_call({:get_workflow, workflow_id}, _from, state) do
    case :ets.lookup(@workflows_table, workflow_id) do
      [{^workflow_id, workflow}] ->
        {:reply, {:ok, workflow}, state}
      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end
  
  @impl true
  def handle_call(:list_executions, _from, state) do
    executions = :ets.tab2list(@executions_table) |> Enum.map(fn {_, exec} -> exec end)
    {:reply, executions, state}
  end
  
  @impl true
  def handle_call(:list_workflows, _from, state) do
    workflows = :ets.tab2list(@workflows_table) |> Enum.map(fn {_, workflow} -> workflow end)
    {:reply, workflows, state}
  end
  
  @impl true
  def handle_call(:clear_all, _from, state) do
    :ets.delete_all_objects(@executions_table)
    :ets.delete_all_objects(@workflows_table)
    Logger.info("Cleared all data from ETS storage")
    {:reply, :ok, state}
  end
end