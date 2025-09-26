defmodule Prana.TestSupport.Integrations.TestActions.ProcessMinorAction do
  @moduledoc """
  Process Minor Action - Test action for minor processing workflows
  """

  use Prana.Actions.SimpleAction

  alias Prana.Action

  def definition do
    %Action{
      name: "manual.process_minor",
      display_name: "Process Minor (Test)",
      description: @moduledoc,
      type: :action,
      input_ports: ["main", "input"],
      output_ports: ["main", "error"]
    }
  end

  @impl true
  def execute(_params, context) do
    input_data = get_in(context, ["$input", "main"]) || get_in(context, ["$input", "input"]) || %{}

    output_data = Map.merge(input_data, %{
      "processed" => true,
      "processed_by" => "process_minor",
      "category" => "minor",
      "processed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    })

    {:ok, output_data, "main"}
  end

  @impl true
  def resume(_params, _context, _resume_data) do
    {:error, "Process minor action does not support resume"}
  end
end