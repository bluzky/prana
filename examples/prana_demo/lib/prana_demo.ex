defmodule PranaDemo do
  @moduledoc """
  Prana workflow execution demo.
  
  This demo showcases how to use the Prana workflow engine to create and execute
  workflows with various integrations and patterns.
  """
  
  alias PranaDemo.DemoWorkflow
  alias PranaDemo.WorkflowRunner
  alias Prana.IntegrationRegistry
  
  require Logger
  
  @doc """
  Start the demo by initializing the integration registry.
  """
  def start do
    Logger.info("Starting Prana Demo")
    
    # Start the integration registry
    case IntegrationRegistry.start_link([]) do
      {:ok, _pid} -> 
        Logger.info("Integration registry started successfully")
        register_integrations()
      {:error, {:already_started, _pid}} ->
        Logger.info("Integration registry already started")
        register_integrations()
      error ->
        Logger.error("Failed to start integration registry: #{inspect(error)}")
        error
    end
  end
  
  defp register_integrations do
    Logger.info("Registering built-in integrations")
    
    # Register all the built-in integrations
    integrations = [
      Prana.Integrations.Manual,
      Prana.Integrations.Logic,
      Prana.Integrations.Data,
      Prana.Integrations.Workflow,
      Prana.Integrations.Wait,
      Prana.Integrations.HTTP
    ]
    
    Enum.each(integrations, fn integration_module ->
      # Ensure the module is loaded
      case Code.ensure_loaded(integration_module) do
        {:module, ^integration_module} ->
          case IntegrationRegistry.register_integration(integration_module) do
            :ok ->
              Logger.debug("Registered integration: #{integration_module}")
            {:error, reason} ->
              Logger.warning("Failed to register integration #{integration_module}: #{inspect(reason)}")
          end
        {:error, reason} ->
          Logger.warning("Failed to load integration module #{integration_module}: #{inspect(reason)}")
      end
    end)
    
    :ok
  end
  
  @doc """
  Run the simple workflow demo.
  """
  def run_simple_demo do
    start()
    DemoWorkflow.run_simple_demo()
  end
  
  @doc """
  Run the conditional workflow demo.
  """
  def run_conditional_demo do
    start()
    DemoWorkflow.run_conditional_demo()
  end
  
  @doc """
  Run the loop workflow demo.
  """
  def run_loop_demo do
    start()
    DemoWorkflow.run_loop_demo()
  end
  
  @doc """
  Run the sub workflow demo (fire-and-forget mode).
  """
  def run_sub_workflow_demo do
    start()
    DemoWorkflow.run_sub_workflow_demo()
  end
  
  @doc """
  Run all sub workflow execution modes.
  """
  def run_all_sub_workflow_demos do
    start()
    DemoWorkflow.run_all_sub_workflow_demos()
  end
  
  @doc """
  Run the wait workflow demo.
  """
  def run_wait_demo do
    start()
    DemoWorkflow.run_wait_demo()
  end
  
  @doc """
  Run all demos.
  """
  def run_all_demos do
    start()
    DemoWorkflow.run_all_demos()
  end
  
  @doc """
  Stop the demo and clean up resources.
  """
  def stop do
    Logger.info("Stopping Prana Demo")
    
    # Stop the ETS storage
    try do
      WorkflowRunner.stop_storage()
    rescue
      e -> Logger.debug("Error stopping storage: #{inspect(e)}")
    end
    
    # Stop the integration registry
    try do
      GenServer.stop(IntegrationRegistry)
    rescue
      e -> Logger.debug("Error stopping integration registry: #{inspect(e)}")
    end
    
    :ok
  end
end
