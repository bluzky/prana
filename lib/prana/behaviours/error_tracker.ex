defmodule Prana.Behaviour.ErrorTracker do
  @moduledoc """
  Behavior for error tracking integrations. Error trackers capture and report
  errors that occur during workflow execution.

  ## Example Implementation

      defmodule MyApp.SentryTracker do
        @behaviour Prana.Behaviour.ErrorTracker

        @impl Prana.Behaviour.ErrorTracker
        def capture_error(exception, stacktrace) do
          Sentry.capture_exception(exception, stacktrace: stacktrace)
          :ok
        end
      end

  ## Configuration

      # config/config.exs
      config :prana, error_tracker: MyApp.SentryTracker

  If no error tracker is configured, Prana will use the default console logger.

  ## Default Behavior

  By default, errors are logged to the console using Elixir's Logger module.
  This is handled by `Prana.ErrorTracker.Console`.
  """

  @doc """
  Capture an error with its stacktrace.

  This function should send the error to an error tracking service or
  perform appropriate error logging/handling.

  ## Parameters

  - `exception` - The exception that was raised
  - `stacktrace` - The stacktrace from the exception

  ## Return Value

  Should return `:ok` on success. If the error tracker itself fails,
  it should handle the error gracefully and still return `:ok` to avoid
  cascading failures.
  """
  @callback capture_error(exception :: Exception.t(), stacktrace :: Exception.stacktrace()) :: :ok
end
