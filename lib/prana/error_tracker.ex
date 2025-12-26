defmodule Prana.ErrorTracker do
  @moduledoc """
  Main error tracking module that delegates to the configured error tracker.

  This module provides a unified interface for error tracking throughout the
  Prana workflow execution system. It reads the configured error tracker from
  application config and delegates error capture to that module.

  ## Configuration

      # config/config.exs
      config :prana, error_tracker: MyApp.CustomErrorTracker

  If no error tracker is configured, it defaults to `Prana.ErrorTracker.Console`
  which logs errors to the console.

  ## Usage

      try do
        # Some workflow execution code
      rescue
        exception ->
          Prana.ErrorTracker.capture_error(exception, __STACKTRACE__)
          reraise exception, __STACKTRACE__
      end
  """

  alias Prana.ErrorTracker.Console

  @doc """
  Capture an error using the configured error tracker.

  Reads the error tracker module from application configuration and delegates
  to its `capture_error/2` callback.

  ## Parameters

  - `exception` - The exception that was raised
  - `stacktrace` - The stacktrace from the exception

  ## Return Value

  Returns `:ok` on success. Raises if the configured error tracker fails,
  allowing the user to fix their error tracker configuration.
  """
  @spec capture_error(exception :: Exception.t(), stacktrace :: Exception.stacktrace()) :: :ok
  def capture_error(exception, stacktrace) do
    tracker_module = get_error_tracker()
    tracker_module.capture_error(exception, stacktrace)
  end

  @doc """
  Get the configured error tracker module.

  Returns the module configured via `config :prana, error_tracker: ModuleName`,
  or defaults to `Prana.ErrorTracker.Console` if not configured.

  ## Examples

      iex> Prana.ErrorTracker.get_error_tracker()
      Prana.ErrorTracker.Console
  """
  @spec get_error_tracker() :: module()
  def get_error_tracker do
    Application.get_env(:prana, :error_tracker, Console)
  end
end
