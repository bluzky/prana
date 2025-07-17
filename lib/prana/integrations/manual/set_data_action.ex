defmodule Prana.Integrations.Manual.SetDataAction do
  @moduledoc """
  Set Data Action - Sets data for testing purposes
  """

  use Prana.Actions.SimpleAction

  alias Prana.Action

  def specification do
    %Action{
      name: "set_data",
      display_name: "Set Data",
      description: "Set data for testing",
      type: :action,
      module: __MODULE__,
      input_ports: ["main"],
      output_ports: ["main"]
    }
  end

  @impl true
  def execute(params, _context) do
    {:ok, params}
  end
end
