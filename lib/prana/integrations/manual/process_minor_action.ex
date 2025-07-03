defmodule Prana.Integrations.Manual.ProcessMinorAction do
  @moduledoc """
  Manual Process Minor Action - Process minor data for testing
  """

  use Prana.Actions.SimpleAction

  @impl true
  def execute(input_data) do
    result = Map.merge(input_data, %{"processed_as" => "minor", "timestamp" => DateTime.utc_now()})
    {:ok, result}
  end
end