defmodule Prana.Integrations.Manual.ProcessAdultAction do
  @moduledoc """
  Manual Process Adult Action - Process adult data for testing
  """

  use Prana.Actions.SimpleAction

  alias Prana.Action

  def specification do
    %Action{
      name: "manual.process_adult",
      display_name: "Process Adult",
      description: "Process adult data",
      type: :action,
      module: __MODULE__,
      input_ports: ["main"],
      output_ports: ["main"]
    }
  end

  @impl true
  def execute(params, _context) do
    result = Map.merge(params, %{"processed_as" => "adult", "timestamp" => DateTime.utc_now()})
    {:ok, result}
  end
end
