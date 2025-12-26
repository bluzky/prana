defmodule Prana.Middleware do
  @moduledoc """
  Middleware pipeline for handling workflow lifecycle events.

  Executes configured middleware in order, allowing each to handle events
  and transform data before passing to the next middleware.
  """

  require Logger

  @doc """
  Execute the middleware pipeline for a given event and data.

  ## Examples

      # Execute middleware for execution started event
      Prana.Middleware.call(:execution_started, execution)
      
      # Execute middleware for node completion
      Prana.Middleware.call(:node_completed, %{
        execution_id: "exec_123",
        node_id: "node_456", 
        output_data: %{result: "success"}
      })
  """
  def call(event, data) do
    middleware_modules = get_middleware_modules()
    execute_pipeline(middleware_modules, event, data)
  end

  @doc """
  Get the list of configured middleware modules.
  """
  def get_middleware_modules do
    Application.get_env(:prana, :middleware, [])
  end

  @doc """
  Execute the middleware pipeline with the given modules.
  """
  def execute_pipeline([], _event, data), do: data

  def execute_pipeline([middleware | rest], event, data) do
    # Create the next function that continues the pipeline
    next_fn = fn next_data ->
      execute_pipeline(rest, event, next_data)
    end

    # Call the current middleware
    middleware.call(event, data, next_fn)
  rescue
    error ->
      Prana.ErrorTracker.capture_error(error, __STACKTRACE__)

      # Continue pipeline with original data on middleware error
      execute_pipeline(rest, event, data)
  end

  @doc """
  Add middleware to the runtime configuration (useful for testing).
  """
  def add_middleware(middleware_module) do
    current = get_middleware_modules()
    new_middleware = current ++ [middleware_module]
    Application.put_env(:prana, :middleware, new_middleware)
  end

  @doc """
  Remove middleware from the runtime configuration (useful for testing).
  """
  def remove_middleware(middleware_module) do
    current = get_middleware_modules()
    new_middleware = Enum.reject(current, &(&1 == middleware_module))
    Application.put_env(:prana, :middleware, new_middleware)
  end

  @doc """
  Clear all middleware (useful for testing).
  """
  def clear_middleware do
    Application.put_env(:prana, :middleware, [])
  end

  @doc """
  Get statistics about middleware execution (for monitoring).
  """
  def get_stats do
    middleware_modules = get_middleware_modules()

    %{
      total_middleware: length(middleware_modules),
      middleware_modules: middleware_modules
    }
  end
end
