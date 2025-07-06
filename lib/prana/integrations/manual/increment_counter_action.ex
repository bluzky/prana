defmodule Prana.Integrations.Manual.IncrementCounterAction do
  @moduledoc """
  Increment Counter Action - Increments a counter for loop testing
  """

  use Prana.Actions.SimpleAction

  @impl true
  def execute(params, _context) do
    current_counter = Map.get(params, "counter", 0)
    max_count = Map.get(params, "max_count", 10)
    new_counter = current_counter + 1
    
    # Set continue_loop flag based on counter comparison
    continue_loop = new_counter < max_count
    
    result = params
    |> Map.put("counter", new_counter)
    |> Map.put("continue_loop", continue_loop)
    
    {:ok, result}
  end
end