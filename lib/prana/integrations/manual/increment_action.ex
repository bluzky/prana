defmodule Prana.Integrations.Manual.IncrementAction do
  @moduledoc """
  Increment Action - Increments a counter for testing loop patterns
  """

  use Prana.Actions.SimpleAction

  @impl true
  def execute(_params, context) do
    # Use loop context instead of input data
    current_run_index = get_in(context, ["$execution", "run_index"]) || 0
    # Simple fixed limit for testing
    max_count = 3

    # Determine if loop should continue
    continue_loop = current_run_index < max_count

    result = %{
      "counter" => current_run_index,
      "max_count" => max_count,
      "continue_loop" => continue_loop
    }

    {:ok, result}
  end
end
