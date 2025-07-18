defmodule Prana.Integrations.Manual.TriggerAction do
  @moduledoc """
  Manual Trigger Action - Simple trigger for testing workflows
  """

  use Prana.Actions.SimpleAction

  alias Prana.Action

  def specification do
    %Action{
      name: "manual.trigger",
      display_name: "Manual Trigger",
      description: "Simple trigger for testing",
      type: :trigger,
      module: __MODULE__,
      input_ports: [],
      output_ports: ["main"]
    }
  end

  @impl true
  def execute(params, _context) do
    {:ok, params}
  end
end
