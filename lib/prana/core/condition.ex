defmodule Prana.Condition do
  @moduledoc """
  Represents a condition for connection routing
  """
  
  @type operator :: :eq | :ne | :gt | :lt | :gte | :lte | :in | :not_in | :regex | :exists
  @type t :: %__MODULE__{
    expression: String.t(),
    operator: operator(),
    value: any(),
    logical_operator: :and | :or | nil
  }

  defstruct [:expression, :operator, :value, :logical_operator]
end
