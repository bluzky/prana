defmodule Prana.Behaviour.Middleware do
  @moduledoc """
  Behavior for workflow middleware. Middleware can handle workflow lifecycle
  events, transform data, and perform side effects like persistence, notifications, etc.

  ## Example Implementation

      defmodule MyApp.DatabaseMiddleware do
        @behaviour Prana.Behaviour.Middleware

        def call(:execution_started, execution, next) do
          MyApp.Database.save_execution(execution)
          next.(execution)
        end

        def call(:execution_completed, execution, next) do
          MyApp.Database.update_execution(execution)
          MyApp.Notifications.send_completion_alert(execution)
          next.(execution)
        end

        def call(:execution_suspended, %{execution: execution, token: token}, next) do
          MyApp.Database.update_execution(execution)
          MyApp.SuspendedWorkflows.store(execution.id, token)
          next.(%{execution: execution, token: token})
        end

        # Pass through other events
        def call(_event, data, next), do: next.(data)
      end

  ## Configuration

      # config/config.exs
      config :prana, middleware: [
        MyApp.DatabaseMiddleware,
        MyApp.NotificationMiddleware,
        MyApp.AnalyticsMiddleware
      ]

  ## Workflow Events

  The middleware will receive these events during workflow execution:

  - `:execution_started` - When workflow execution begins
  - `:execution_completed` - When workflow execution completes successfully  
  - `:execution_failed` - When workflow execution fails
  - `:execution_suspended` - When workflow execution is suspended
  - `:node_started` - When individual node execution begins
  - `:node_completed` - When individual node execution completes
  - `:node_failed` - When individual node execution fails
  - `:sub_workflow_requested` - When a sub-workflow needs to be spawned

  """

  @type event :: atom()
  @type data :: any()
  @type next_function :: (data() -> data())

  @doc """
  Handle a workflow event with the given data.

  The middleware can:
  - Perform side effects (logging, persistence, notifications)
  - Transform the data before passing to next middleware
  - Short-circuit the pipeline by not calling next/1
  - Handle errors and continue or halt the pipeline

  ## Parameters

  - `event` - The workflow event being processed
  - `data` - The event data (execution, node, error info, etc.)
  - `next` - Function to call the next middleware in the pipeline

  ## Return Value

  Should return the data (potentially transformed) that will be passed
  to the next middleware or returned as the final result.
  """
  @callback call(event(), data(), next_function()) :: data()
end
