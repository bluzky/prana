defmodule Prana.NodeSettings do
  @moduledoc """
  Node execution settings that apply to individual nodes in a workflow.
  
  Contains configuration options for retry behavior and future extensible settings.
  """
  
  use Skema

  defschema do
    # Retry configuration
    field(:retry_on_failed, :boolean, default: false)
    field(:max_retries, :integer, default: 1, number: [min: 1, max: 10])
    field(:retry_delay_ms, :integer, default: 1000, number: [min: 0, max: 60_000])
    
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