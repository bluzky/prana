defmodule Prana.Integrations.Manual.IncrementRetryAction do
  @moduledoc """
  Increment Retry Action - Increments retry counter for retry testing
  """

  use Prana.Actions.SimpleAction

  alias Prana.Action

  def specification do
    %Action{
      name: "increment_retry",
      display_name: "Increment Retry",
      description: "Increment retry counter for retry testing",
      type: :action,
      module: __MODULE__,
      input_ports: ["main"],
      output_ports: ["main"]
    }
  end

  @impl true
  def execute(_params, context) do
    # Get values directly from input context
    current_retry = get_in(context, ["$input", "main", "retry_count"]) || 0
    max_retries = get_in(context, ["$input", "main", "max_retries"]) || 3

    new_retry = current_retry + 1

    # Update should_retry flag based on new retry count
    should_retry = new_retry < max_retries

    result = %{
      "retry_count" => new_retry,
      "max_retries" => max_retries,
      "should_retry" => should_retry
    }

    {:ok, result}
  end
end
