defmodule Prana.Behaviour.StorageAdapter do
  @moduledoc """
  Behavior for storage adapters. Each adapter manages its own configuration
  and provides storage operations for workflows, executions, and logs.
  """

  @type config :: map()
  @type workflow :: Prana.Workflow.t()
  @type execution :: Prana.Execution.t()
  @type node_execution :: Prana.NodeExecution.t()

  @doc """
  Initialize the storage adapter with its configuration.
  Called once when the adapter is registered.
  """
  @callback init_adapter(config()) :: {:ok, state :: any()} | {:error, reason :: any()}

  @doc """
  Validate the adapter's configuration.
  Called before init to ensure configuration is valid.
  """
  @callback validate_config(config()) :: :ok | {:error, reason :: any()}

  # Workflow operations
  @callback create_workflow(workflow()) :: {:ok, workflow()} | {:error, any()}
  @callback get_workflow(String.t()) :: {:ok, workflow()} | {:error, :not_found}
  @callback update_workflow(workflow()) :: {:ok, workflow()} | {:error, any()}
  @callback delete_workflow(String.t()) :: :ok | {:error, any()}
  @callback list_workflows(map()) :: {:ok, [workflow()]} | {:error, any()}

  # Execution operations
  @callback create_execution(execution()) :: {:ok, execution()} | {:error, any()}
  @callback get_execution(String.t()) :: {:ok, execution()} | {:error, :not_found}
  @callback update_execution(execution()) :: {:ok, execution()} | {:error, any()}
  @callback list_executions(String.t()) :: {:ok, [execution()]} | {:error, any()}

  # Node execution operations
  @callback create_node_execution(node_execution()) :: {:ok, node_execution()} | {:error, any()}
  @callback update_node_execution(node_execution()) :: {:ok, node_execution()} | {:error, any()}
  @callback get_node_executions(String.t()) :: {:ok, [node_execution()]} | {:error, any()}

  # State management for suspended executions
  @callback suspend_execution(String.t(), String.t()) :: :ok | {:error, any()}
  @callback resume_execution(String.t()) :: {:ok, execution()} | {:error, any()}
  @callback get_suspended_executions() :: {:ok, [execution()]} | {:error, any()}

  @doc """
  Health check for the storage adapter
  """
  @callback health_check() :: :ok | {:error, reason :: any()}
end
