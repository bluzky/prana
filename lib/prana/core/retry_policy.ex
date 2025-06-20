defmodule Prana.RetryPolicy do
  @moduledoc """
  Retry policy configuration for nodes
  """
  
  @type backoff_strategy :: :fixed | :exponential | :linear
  
  @type t :: %__MODULE__{
    max_attempts: integer(),
    backoff_strategy: backoff_strategy(),
    initial_delay_ms: integer(),
    max_delay_ms: integer(),
    backoff_multiplier: float(),
    retry_on_errors: [String.t()],
    jitter: boolean()
  }

  defstruct [
    max_attempts: 3,
    backoff_strategy: :exponential,
    initial_delay_ms: 1000,
    max_delay_ms: 30000,
    backoff_multiplier: 2.0,
    retry_on_errors: [],
    jitter: true
  ]
end
