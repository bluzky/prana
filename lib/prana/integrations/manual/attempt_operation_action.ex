defmodule Prana.Integrations.Manual.AttemptOperationAction do
  @moduledoc """
  Attempt Operation Action - Simulates an operation that may fail for retry testing
  """

  use Prana.Actions.SimpleAction

  alias Prana.Action

  def specification do
    %Action{
      name: "attempt_operation",
      display_name: "Attempt Operation",
      description: "Simulate operation that may fail for retry testing",
      type: :action,
      module: __MODULE__,
      input_ports: ["main"],
      output_ports: ["main"]
    }
  end

  @impl true
  def execute(_params, context) do
    # Get values directly from input context
    retry_count = get_in(context, ["$input", "main", "retry_count"]) || 0
    max_retries = get_in(context, ["$input", "main", "max_retries"]) || 3

    # Simulate success after 2 retries
    success = retry_count >= 2

    # Set should_retry flag based on success and retry count
    should_retry = !success and retry_count < max_retries

    result = %{
      "retry_count" => retry_count,
      "max_retries" => max_retries,
      "success" => success,
      "should_retry" => should_retry
    }

    {:ok, result}
  end
end
