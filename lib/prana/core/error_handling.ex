defmodule Prana.ErrorHandling do
  @moduledoc """
  Error handling configuration for nodes
  """

  @type on_error :: :stop | :continue | :retry | :skip

  @type t :: %__MODULE__{
          on_error: on_error(),
          continue_on_error: boolean(),
          error_workflow_id: String.t() | nil,
          notification_channels: [String.t()],
          custom_error_handler: String.t() | nil
        }

  defstruct on_error: :stop,
            continue_on_error: false,
            error_workflow_id: nil,
            notification_channels: [],
            custom_error_handler: nil
end
