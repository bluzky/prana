defmodule Prana.Integrations.Manual.TriggerAction do
  @moduledoc """
  Manual Trigger Action - Simple trigger for testing workflows
  """

  use Prana.Actions.SimpleAction

  @impl true
  def execute(params, _context) do
    {:ok, params}
  end
end