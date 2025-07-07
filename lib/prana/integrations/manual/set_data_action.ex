defmodule Prana.Integrations.Manual.SetDataAction do
  @moduledoc """
  Set Data Action - Sets data for testing purposes
  """

  use Prana.Actions.SimpleAction

  @impl true
  def execute(params, _context) do
    # Merge params with any incoming data
    result = Map.merge(params, %{})

    # If this is initializing a counter, set continue_loop flag
    result =
      if Map.has_key?(result, "counter") and Map.has_key?(result, "max_count") do
        counter = Map.get(result, "counter", 0)
        max_count = Map.get(result, "max_count", 10)
        continue_loop = counter < max_count
        Map.put(result, "continue_loop", continue_loop)
      else
        result
      end

    # If this is initializing retry state, set should_retry flag
    result =
      if Map.has_key?(result, "retry_count") and Map.has_key?(result, "max_retries") do
        retry_count = Map.get(result, "retry_count", 0)
        max_retries = Map.get(result, "max_retries", 3)
        success = Map.get(result, "success", false)
        should_retry = !success and retry_count < max_retries
        Map.put(result, "should_retry", should_retry)
      else
        result
      end

    {:ok, result}
  end
end
