defmodule Prana.Integrations.Manual.ProcessMinorAction do
  @moduledoc """
  Manual Process Minor Action - Process minor data for testing
  """

  use Prana.Actions.SimpleAction

  @impl true
  def execute(params, _context) do
    result = Map.merge(params, %{"processed_as" => "minor", "timestamp" => DateTime.utc_now()})
    {:ok, result}
  end
end