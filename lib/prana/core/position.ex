defmodule Prana.Position do
  @moduledoc """
  UI positioning information for nodes
  """
  
  @type t :: %__MODULE__{
    x: float(),
    y: float(),
    width: float() | nil,
    height: float() | nil
  }

  defstruct [:x, :y, :width, :height]
end
