defmodule Prana.Integrations.Data.SetDataAction do
  @moduledoc """
  Set Data Action - Sets data for testing purposes
  """

  use Prana.Actions.SimpleAction

  alias Prana.Action

  def specification do
    %Action{
      name: "data.set_data",
      display_name: "Set Data",
      description: "Set data",
      type: :action,
      module: __MODULE__,
      input_ports: ["main"],
      output_ports: ["main", "error"]
    }
  end

  @impl true
  def execute(params, _context) do
    {:ok, params}
  end
end
