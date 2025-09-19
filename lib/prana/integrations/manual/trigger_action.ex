defmodule Prana.Integrations.Manual.TriggerAction do
  @moduledoc """
  Manual Trigger Action - Simple trigger for testing workflows
  """

  use Prana.Actions.SimpleAction

  alias Prana.Action

  def definition do
    %Action{
      name: "manual.trigger",
      display_name: "Manual Trigger",
      description: "Simple trigger for testing",
      type: :trigger,
      input_ports: [],
      output_ports: ["main"]
    }
  end

  @impl true
  def execute(_params, context) do
    input = context["$input"]["main"] || %{}
    {:ok, input}
  end
end
