defmodule Prana.TestSupport.Integrations.TestActions.TriggerAction do
  @moduledoc """
  Trigger Action - Test trigger action for starting test workflows
  """

  use Prana.Actions.SimpleAction

  alias Prana.Action

  def definition do
    %Action{
      name: "test.trigger_action",
      display_name: "Test Trigger",
      description: @moduledoc,
      type: :trigger,
      input_ports: [],
      output_ports: ["main"]
    }
  end

  @impl true
  def execute(_params, _context) do
    output_data = %{
      "triggered" => true,
      "timestamp" => DateTime.utc_now()
    }

    {:ok, output_data, "main"}
  end

  @impl true
  def resume(_params, _context, _resume_data) do
    {:error, "Test trigger action does not support resume"}
  end
end