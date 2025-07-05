defmodule Prana.Integrations.Manual.ProcessAdultAction do
  @moduledoc """
  Manual Process Adult Action - Process adult data for testing
  """

  use Prana.Actions.SimpleAction

  @impl true
  def execute(params, _context) do
    result = Map.merge(params, %{"processed_as" => "adult", "timestamp" => DateTime.utc_now()})
    {:ok, result}
  end
end