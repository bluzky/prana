defmodule Prana.Integrations.Manual.TriggerAction do
  @moduledoc """
  Manual Trigger Action - Simple trigger for testing workflows

  This action is used to manually start workflow execution, typically for testing purposes.
  It doesn't require any parameters and simply passes through the input data.

  ## Parameters
  None required.

  ## Example Params JSON
  ```json
  {}
  ```

  ## Output
  Returns the input data unchanged through the "main" output port.
  """

  use Prana.Actions.SimpleAction

  alias Prana.Action

  def definition do
    %Action{
      name: "manual.trigger",
      display_name: "Manual Trigger",
      description: @moduledoc,
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
