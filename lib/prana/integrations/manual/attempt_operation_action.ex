defmodule Prana.Integrations.Manual.AttemptOperationAction do
  @moduledoc """
  Attempt Operation Action - Simulates an operation that may fail for retry testing
  """

  use Prana.Actions.SimpleAction

  @impl true
  def execute(params, _context) do
    retry_count = Map.get(params, "retry_count", 0)
    max_retries = Map.get(params, "max_retries", 3)
    
    # Simulate success after 2 retries
    success = retry_count >= 2
    
    # Set should_retry flag based on success and retry count
    should_retry = !success and retry_count < max_retries
    
    result = params
    |> Map.put("success", success)
    |> Map.put("should_retry", should_retry)
    
    {:ok, result}
  end
end