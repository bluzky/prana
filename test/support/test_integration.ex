defmodule Prana.TestSupport.TestIntegration do
  @moduledoc """
  A simple test integration for testing purposes.
  """

  @behaviour Prana.Behaviour.Integration

  alias Prana.Action
  alias Prana.Integration

  def definition do
    %Integration{
      name: "test",
      display_name: "Test Integration",
      description: "Simple test integration for unit tests",
      version: "1.0.0",
      category: "testing",
      actions: %{
        "simple_action" => %Action{
          name: "simple_action",
          display_name: "Simple Action",
          description: "A simple test action",
          module: __MODULE__,
          function: :simple_action,
          input_ports: ["input"],
          output_ports: ["success", "error"],
          default_success_port: "success",
          default_error_port: "error"
        }
      }
    }
  end

  @doc """
  Simple action implementation for testing
  """
  def simple_action(input) do
    {:ok, %{original_input: input, processed: true}}
  end
end
