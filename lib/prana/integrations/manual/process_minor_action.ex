defmodule Prana.Integrations.Manual.ProcessMinorAction do
  @moduledoc """
  Manual Process Minor Action - Process minor data for testing
  """

  use Prana.Actions.SimpleAction

  alias Prana.Action

  def specification do
    %Action{
      name: "manual.process_minor",
      display_name: "Process Minor",
      description: "Process minor data",
      type: :action,
      module: __MODULE__,
      input_ports: ["main"],
      output_ports: ["main"]
    }
  end

  @impl true
  def execute(params, _context) do
    result = Map.merge(params, %{"processed_as" => "minor", "timestamp" => DateTime.utc_now()})
    {:ok, result}
  end
end
