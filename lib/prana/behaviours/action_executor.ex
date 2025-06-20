defmodule Prana.Behaviour.ActionExecutor do
  @moduledoc """
  Behavior for individual action executors.
  This is used by integrations to define their action implementations.
  """

  @type input :: map()
  @type output :: map()
  @type config :: map()
  @type context :: map()

  @doc """
  Execute an action with the given input, configuration, and context.
  
  Returns:
  - {:ok, output} - Success with default success port
  - {:ok, output, port} - Success with explicit port
  - {:error, error} - Error with default error port  
  - {:error, error, port} - Error with explicit port
  """
  @callback execute(input(), config(), context()) :: 
    {:ok, output()} | 
    {:ok, output(), port :: String.t()} |
    {:error, error :: map()} |
    {:error, error :: map(), port :: String.t()}

  @doc """
  Validate action configuration
  """
  @callback validate_config(config()) :: :ok | {:error, reason :: any()}

  @doc """
  Get action metadata (ports, schema, etc.)
  """
  @callback metadata() :: map()

  @optional_callbacks [validate_config: 1, metadata: 0]
end
