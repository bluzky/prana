defmodule Prana.TestSupport.Integrations.TestActions.ProcessAdultAction do
  @moduledoc """
  Process Adult Action - Test action for adult processing workflows
  """

  use Prana.Actions.SimpleAction

  alias Prana.Action

  def definition do
    %Action{
      name: "manual.process_adult",
      display_name: "Process Adult (Test)",
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
      "processed_by" => "process_adult",
      "category" => "adult",
      "processed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    })

    {:ok, output_data, "main"}
  end

  @impl true
  def resume(_params, _context, _resume_data) do
    {:error, "Process adult action does not support resume"}
  end
end