defmodule Prana.ErrorTracker.Console do
  @moduledoc """
  Default error tracker that logs errors to the console using Elixir's Logger.

  This is the default implementation used when no custom error tracker is configured.
  It formats the exception and stacktrace in a readable format and logs them as errors.

  ## Example Output

      [error] Workflow error captured: %RuntimeError{message: "Something went wrong"}
      Stacktrace:
        (my_app 0.1.0) lib/my_app.ex:42: MyApp.do_something/1
        (prana 0.1.0) lib/prana/node_executor.ex:123: Prana.NodeExecutor.execute/2
  """

  @behaviour Prana.Behaviour.ErrorTracker

  require Logger

  @impl Prana.Behaviour.ErrorTracker
  def capture_error(exception, stacktrace) do
    formatted_exception = Exception.format(:error, exception, stacktrace)

    Logger.error("""
    Workflow error captured: #{inspect(exception)}
    #{formatted_exception}
    """)

    :ok
  end
end
