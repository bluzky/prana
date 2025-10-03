defmodule Prana.TestSupport.Integrations.TestActions.SimpleAction do
  @moduledoc """
  Simple Action - Generic test action for various testing scenarios
  """

  use Prana.Actions.SimpleAction

  alias Prana.Action

  def definition do
    %Action{
      name: "test.simple_action",
      display_name: "Simple Test Action",
      description: @moduledoc,
      type: :action,
      input_ports: ["main"],
      output_ports: ["main"]
    }
  end

  @impl true
  def execute(_params, context) do
    input_data = get_in(context, ["$input", "main"]) || %{}

    output_data = Map.merge(input_data, %{
      "processed" => true,
      "processed_by" => "simple_action",
      "processed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    })

    {:ok, output_data, "main"}
  end

  @impl true
  def resume(_params, _context, _resume_data) do
    {:error, "Simple action does not support resume"}
  end
end