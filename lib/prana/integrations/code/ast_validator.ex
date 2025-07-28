defmodule Prana.Integrations.Code.AstValidator do
  @moduledoc """
  AST Validator for secure Elixir code execution in Prana workflows.

  This module implements Sequin's proven MiniElixir validation patterns adapted for Prana.
  It provides security-first AST validation using comprehensive whitelists to prevent
  dangerous operations while allowing safe Elixir code execution.

  ## Features

  - **Security-first validation**: Only explicitly whitelisted operations are allowed
  - **Sequin's proven patterns**: Uses check/unwrap/good validation flow from production
  - **Comprehensive error reporting**: Clear messages for validation failures
  - **Function signature validation**: Ensures proper `def run(input, context)` pattern

  ## Usage

      iex> code = "def run(input, _context), do: input[:name]"
      iex> AstValidator.validate_code(code)
      {:ok, parsed_body_ast}
      
      iex> bad_code = "def run(_input, _context), do: File.read!('/etc/passwd')"
      iex> AstValidator.validate_code(bad_code)
      {:error, "Function File.read!/1 is not allowed"}

  ## Security Model

  The validator blocks dangerous operations including:
  - File system access (File, Path modules)
  - Network operations (HTTP, GenServer, etc.)
  - Process spawning and message passing
  - Module definitions and code compilation
  - Import/require/use statements
  - Assignment operations for immutability

  Only safe operations are allowed such as:
  - Basic arithmetic and string operations
  - Data structure manipulation (Enum, Map, List)
  - Date/time functions
  - Pattern matching and control flow

  See `Prana.Integrations.Code.SecurityPolicy` for complete whitelists.
  """

  alias Prana.Integrations.Code.SecurityPolicy

  @allowed_funname [:run]
  @error_bad_toplevel "Expecting only `def run` at the top level"
  @error_bad_args "The parameter list `input, context` is required"

  @doc """
  Validates Elixir code string and returns the parsed function body AST.

  Takes a string containing Elixir code with a `def run(input, context)` function
  and validates it against security policies. Returns the function body AST on success.

  ## Parameters

  - `code` - String containing Elixir code with `def run(input, context)` function

  ## Returns

  - `{:ok, body_ast}` - Function body AST if validation passes
  - `{:error, reason}` - Error message if validation fails

  ## Examples

      iex> validate_code("def run(input, _ctx), do: input[:name]")
      {:ok, {{:., [], [Access, :get]}, [], [{:input, [], nil}, :name]}}
      
      iex> validate_code("def hello, do: :world")
      {:error, "Expecting only `def run` at the top level"}
  """
  def validate_code(code) when is_binary(code) do
    case Code.string_to_quoted(code) do
      {:ok, ast} ->
        case check(ast) do
          {:ok, expr} -> {:ok, expr}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, "Parse error: #{inspect(reason)}"}
    end
  end

  @doc """
  Validates parsed AST for security compliance.

  Takes an AST (Abstract Syntax Tree) and validates it against security policies.
  Used internally by `validate_code/1` and for direct AST validation.

  ## Parameters

  - `ast` - Parsed AST from `Code.string_to_quoted/1`

  ## Returns

  - `:ok` - AST passes validation
  - `{:error, reason}` - Error message if validation fails

  ## Examples

      iex> {:ok, ast} = Code.string_to_quoted("def run(input, _ctx), do: input[:name]")
      iex> validate_ast(ast)
      :ok
  """
  def validate_ast(ast) do
    case check(ast) do
      {:ok, _expr} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # Sequin's exact check implementation
  def check(code) do
    case unwrap(code) do
      {:def, _, [{funname, _, args}, [do: body]]} ->
        cond do
          funname not in @allowed_funname ->
            {:error, @error_bad_toplevel}

          not good_args?(args) ->
            {:error, @error_bad_args}

          true ->
            case good(body) do
              :ok -> create_expr(body, args)
              {:error, _} = error -> error
            end
        end

      _ ->
        {:error, @error_bad_toplevel}
    end
  end

  # Sequin's unwrap - handles __block__ and single expressions
  defp unwrap({:__block__, _, [expr]}), do: expr
  defp unwrap(expr), do: expr

  # Check if arguments match expected pattern
  defp good_args?(args) when is_list(args) do
    arg_names =
      Enum.map(args, fn
        {name, _, nil} -> name
        {name, _, _} -> name
        _ -> nil
      end)

    # Allow any two arguments for flexibility (input, context or input, _context, etc.)
    length(arg_names) == 2
  end

  defp good_args?(_), do: false

  # Create expression (Sequin's create_expr pattern)
  defp create_expr(body, _args) do
    {:ok, body}
  end

  # Sequin's good/1 - validates the function body
  defp good(ast) do
    validate_expression(ast)
  end

  # Block expressions
  defp validate_expression({:__block__, _, expressions}) do
    Enum.reduce_while(expressions, :ok, fn expr, _acc ->
      case validate_expression(expr) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  # Variables (allow any variable names for Prana context)
  defp validate_expression({var, _, nil}) when is_atom(var), do: :ok

  # Literals
  defp validate_expression(literal)
       when is_number(literal) or is_binary(literal) or is_boolean(literal) or is_nil(literal),
       do: :ok

  defp validate_expression(atom) when is_atom(atom), do: :ok

  # Lists
  defp validate_expression(list) when is_list(list) do
    Enum.reduce_while(list, :ok, fn item, _acc ->
      case validate_expression(item) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  # Tuples
  defp validate_expression({:{}, _, elements}) do
    Enum.reduce_while(elements, :ok, fn element, _acc ->
      case validate_expression(element) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  # 2-element tuples
  defp validate_expression({left, right}) do
    with :ok <- validate_expression(left),
         :ok <- validate_expression(right) do
      :ok
    else
      {:error, _} = error -> error
    end
  end

  # Maps
  defp validate_expression({:%{}, _, pairs}) do
    Enum.reduce_while(pairs, :ok, fn {key, value}, _acc ->
      with :ok <- validate_expression(key),
           :ok <- validate_expression(value) do
        {:cont, :ok}
      else
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  # Map access
  defp validate_expression({{:., _, [map, field]}, _, []}) do
    with :ok <- validate_expression(map) do
      if is_atom(field) do
        :ok
      else
        {:error, "Invalid map field access"}
      end
    end
  end

  # Map bracket access
  defp validate_expression({{:., _, [Access, :get]}, _, [map, key]}) do
    with :ok <- validate_expression(map) do
      validate_expression(key)
    end
  end

  # Binary operators - only match simple operators, not function calls
  defp validate_expression({op, _, [left, right]}) when is_atom(op) do
    if SecurityPolicy.operator_allowed?(op) do
      with :ok <- validate_expression(left),
           :ok <- validate_expression(right) do
        :ok
      else
        {:error, _} = error -> error
      end
    else
      {:error, "Operator #{op} is not allowed"}
    end
  end

  # Unary operators - only match simple operators, exclude fn and other special forms
  defp validate_expression({op, _, [operand]}) when is_atom(op) and op != :fn do
    if SecurityPolicy.unary_operator_allowed?(op) do
      validate_expression(operand)
    else
      {:error, "Unary operator #{op} is not allowed"}
    end
  end

  # Function calls - handle both direct module atoms and alias forms
  defp validate_expression({{:., _, [module, function]}, _, args}) do
    arity = length(args)

    # Convert alias form to atom if needed
    module_atom =
      case module do
        {:__aliases__, _, [mod]} -> mod
        mod when is_atom(mod) -> mod
        _ -> module
      end

    if SecurityPolicy.function_allowed?(module_atom, function, arity) do
      Enum.reduce_while(args, :ok, fn arg, _acc ->
        case validate_expression(arg) do
          :ok -> {:cont, :ok}
          {:error, _} = error -> {:halt, error}
        end
      end)
    else
      {:error, "Function #{inspect(module_atom)}.#{function}/#{arity} is not allowed"}
    end
  end

  # Local function calls (Kernel functions without module prefix) - but exclude anonymous functions
  defp validate_expression({function, _, args}) when is_atom(function) and is_list(args) and function != :fn do
    arity = length(args)

    if SecurityPolicy.function_allowed?(:Kernel, function, arity) do
      Enum.reduce_while(args, :ok, fn arg, _acc ->
        case validate_expression(arg) do
          :ok -> {:cont, :ok}
          {:error, _} = error -> {:halt, error}
        end
      end)
    else
      {:error, "Function #{function}/#{arity} is not allowed"}
    end
  end

  # Anonymous functions
  defp validate_expression({:fn, _, clauses}) do
    Enum.reduce_while(clauses, :ok, fn {:->, _, [_args, body]}, _acc ->
      # Note: We allow any parameters in anonymous functions for flexibility
      case validate_expression(body) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  # Case expressions
  defp validate_expression({:case, _, [expr, [do: clauses]]}) do
    with :ok <- validate_expression(expr) do
      Enum.reduce_while(clauses, :ok, fn {:->, _, [_patterns, body]}, _acc ->
        # Note: We allow any patterns for flexibility
        case validate_expression(body) do
          :ok -> {:cont, :ok}
          {:error, _} = error -> {:halt, error}
        end
      end)
    end
  end

  # Cond expressions
  defp validate_expression({:cond, _, [[do: clauses]]}) do
    Enum.reduce_while(clauses, :ok, fn {:->, _, [condition, body]}, _acc ->
      with :ok <- validate_expression(hd(condition)),
           :ok <- validate_expression(body) do
        {:cont, :ok}
      else
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  # If expressions
  defp validate_expression({:if, _, [condition, [do: do_clause, else: else_clause]]}) do
    with :ok <- validate_expression(condition),
         :ok <- validate_expression(do_clause) do
      validate_expression(else_clause)
    end
  end

  defp validate_expression({:if, _, [condition, [do: do_clause]]}) do
    with :ok <- validate_expression(condition) do
      validate_expression(do_clause)
    end
  end

  # Unless expressions
  defp validate_expression({:unless, _, [condition, [do: do_clause, else: else_clause]]}) do
    with :ok <- validate_expression(condition),
         :ok <- validate_expression(do_clause) do
      validate_expression(else_clause)
    end
  end

  defp validate_expression({:unless, _, [condition, [do: do_clause]]}) do
    with :ok <- validate_expression(condition) do
      validate_expression(do_clause)
    end
  end

  # Regex literals
  defp validate_expression({:sigil_r, _, [_pattern, _modifiers]}), do: :ok

  # String interpolation
  defp validate_expression({:<<>>, _, parts}) do
    Enum.reduce_while(parts, :ok, fn part, _acc ->
      case part do
        binary when is_binary(binary) ->
          {:cont, :ok}

        {:"::", _, [expr, {:binary, _, _}]} ->
          case validate_expression(expr) do
            :ok -> {:cont, :ok}
            {:error, _} = error -> {:halt, error}
          end

        _ ->
          {:halt, {:error, "Invalid string interpolation"}}
      end
    end)
  end

  # Pipe operator
  defp validate_expression({:|>, _, [left, right]}) do
    with :ok <- validate_expression(left) do
      validate_expression(right)
    end
  end

  # Assignment - BLOCKED for security
  defp validate_expression({:=, _, [_left, _right]}) do
    {:error, "Assignment operations are not allowed"}
  end

  # Module definition - BLOCKED for security
  defp validate_expression({:defmodule, _, _}) do
    {:error, "Module definitions are not allowed"}
  end

  # Function definitions are handled at top level by check/1
  # Block them here for security if they appear nested
  defp validate_expression({:def, _, _}) do
    {:error, "Nested function definitions are not allowed"}
  end

  defp validate_expression({:defp, _, _}) do
    {:error, "Private function definitions are not allowed"}
  end

  # Import/require/use - BLOCKED for security
  defp validate_expression({:import, _, _}) do
    {:error, "Import statements are not allowed"}
  end

  defp validate_expression({:require, _, _}) do
    {:error, "Require statements are not allowed"}
  end

  defp validate_expression({:use, _, _}) do
    {:error, "Use statements are not allowed"}
  end

  # Alias - BLOCKED for security
  defp validate_expression({:alias, _, _}) do
    {:error, "Alias statements are not allowed"}
  end

  # Catch-all for unknown expressions
  defp validate_expression(expr) do
    {:error, "Expression not allowed: #{inspect(expr)}"}
  end
end
