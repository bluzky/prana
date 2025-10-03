defmodule Prana.NodeSettings do
  @moduledoc """
  Node execution settings that apply to individual nodes in a workflow.

  Contains configuration options for retry behavior, error handling, and future extensible settings.

  ## Error Handling Options

  The `on_error` field determines how node execution errors are handled:

  - **`"stop_workflow"`** (default): Fail the entire workflow when the node encounters an error
  - **`"continue"`**: Treat the error as a successful result and route error data through the default output port
  - **`"continue_error_output"`**: Treat the error as a successful result and route error data through a virtual "error" port

  ## Retry Integration

  Error handling behavior is applied only after all retry attempts have been exhausted (if `retry_on_failed` is true).
  """

  use Skema

  defschema do
    # Retry configuration
    field(:retry_on_failed, :boolean, default: false)
    field(:max_retries, :integer, default: 1, number: [min: 1, max: 10])
    field(:retry_delay_ms, :integer, default: 1000, number: [min: 0, max: 60_000])

    # Error handling configuration
    field(:on_error, :string, default: "stop_workflow",
          in: ["stop_workflow", "continue", "continue_error_output"])

    # Future extensible settings can be added here
    # field(:timeout_ms, :integer, default: 30_000)
    # field(:priority, :integer, default: 0)
  end

  @doc "Creates default node settings"
  def default, do: new(%{})

  @doc "Load settings from a map with string keys"
  def from_map(data) when is_map(data) do
    {:ok, settings} = Skema.load(data, __MODULE__)
    settings
  end

  @doc "Convert settings to a JSON-compatible map"
  def to_map(%__MODULE__{} = settings), do: Map.from_struct(settings)
end
