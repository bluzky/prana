defmodule Prana.WorkflowSettings do
  @moduledoc """
  Configuration settings for a workflow
  """

  @type execution_mode :: :sync | :async
  @type concurrency_mode :: :sequential | :parallel | :limited

  @type t :: %__MODULE__{
          execution_mode: execution_mode(),
          concurrency_mode: concurrency_mode(),
          max_concurrent_executions: integer(),
          timeout_seconds: integer() | nil,
          enable_step_debugging: boolean(),
          max_execution_history: integer(),
          continue_on_error: boolean()
        }

  defstruct execution_mode: :async,
            concurrency_mode: :parallel,
            max_concurrent_executions: 10,
            timeout_seconds: 3600,
            enable_step_debugging: false,
            max_execution_history: 100,
            continue_on_error: false
end
