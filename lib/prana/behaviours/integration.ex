defmodule Prana.Behaviour.Integration do
  @moduledoc """
  Behavior for integrations. Each integration can provide multiple actions
  and manages its own configuration and lifecycle.
  """

  @type config :: map()
  @type integration_definition :: map()
  @type action_definition :: map()

  @doc """
  Return the integration definition including all actions
  """
  @callback definition() :: integration_definition()

  @doc """
  Initialize the integration with its configuration.
  Called once when the integration is registered.
  """
  @callback init_integration(config()) :: {:ok, state :: any()} | {:error, reason :: any()}

  @doc """
  Validate the integration's configuration.
  Called before init to ensure configuration is valid.
  """
  @callback validate_config(config()) :: :ok | {:error, reason :: any()}

  @doc """
  Get all action definitions provided by this integration
  """
  @callback list_actions() :: [action_definition()]

  @doc """
  Get a specific action definition by name
  """
  @callback get_action(String.t()) :: {:ok, action_definition()} | {:error, :not_found}

  @doc """
  Health check for the integration
  """
  @callback health_check() :: :ok | {:error, reason :: any()}

  @optional_callbacks [init_integration: 1, validate_config: 1, list_actions: 0, get_action: 1, health_check: 0]
end
