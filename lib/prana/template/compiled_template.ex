defmodule Prana.Template.CompiledTemplate do
  @moduledoc """
  Represents a compiled template with pre-parsed AST and compilation options.

  This struct encapsulates a template that has been compiled for efficient reuse.
  The AST is the parsed representation of the template, and the options contain
  the compilation settings that were used when creating this compiled template.
  """

  @type t :: %__MODULE__{
          ast: list(),
          options: map()
        }

  defstruct [:ast, :options]

  @doc """
  Create a new compiled template.

  ## Parameters
  - `ast` - The parsed abstract syntax tree of the template
  - `options` - Map of compilation options used

  ## Returns
  - `%CompiledTemplate{}` - A new compiled template struct
  """
  @spec new(list(), map()) :: t()
  def new(ast, options) when is_list(ast) and is_map(options) do
    %__MODULE__{
      ast: ast,
      options: options
    }
  end
end
