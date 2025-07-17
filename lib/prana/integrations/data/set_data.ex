defmodule Prana.Integrations.Data.SetDataAction do
  @moduledoc """
  Set Data Action - Sets data for testing purposes
  """

  use Prana.Actions.SimpleAction

  @impl true
  def execute(params, _context) do
    {:ok, params}
  end
end
