defmodule Prana.Integrations.Manual.IncrementRetryAction do
  @moduledoc """
  Increment Retry Action - Increments retry counter for retry testing
  """

  use Prana.Actions.SimpleAction

  @impl true
  def execute(params, _context) do
    current_retry = Map.get(params, "retry_count", 0)
    max_retries = Map.get(params, "max_retries", 3)
    new_retry = current_retry + 1
    
    # Update should_retry flag based on new retry count
    should_retry = new_retry < max_retries
    
    result = params
    |> Map.put("retry_count", new_retry)
    |> Map.put("should_retry", should_retry)
    
    {:ok, result}
  end
end