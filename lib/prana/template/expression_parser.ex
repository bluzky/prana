defmodule Prana.Template.ExpressionParser do
  @moduledoc """
  NimbleParsec-based expression parser with full operator precedence support.

  Supports complex nested expressions with proper operator precedence.
  For now, we'll implement a simple version that can be extended.
  """

  import NimbleParsec

  # Basic tokens
  whitespace = ignore(repeat(ascii_char([?\s, ?\t, ?\n, ?\r])))

  # Literals
  integer =
    [?-]
    |> ascii_char()
    |> optional()
    |> ascii_string([?0..?9], min: 1)
    |> reduce({__MODULE__, :parse_integer, []})
    |> unwrap_and_tag(:literal)

  float =
    [?-]
    |> ascii_char()
    |> optional()
    |> ascii_string([?0..?9], min: 1)
    |> ascii_char([?.])
    |> ascii_string([?0..?9], min: 1)
    |> reduce({__MODULE__, :parse_float, []})
    |> unwrap_and_tag(:literal)

  # String literals (both double and single quoted)
  double_string_char =
    choice([
      "\\\"" |> string() |> replace(?"),
      "\\\\" |> string() |> replace(?\\),
      utf8_char(not: ?")
    ])

  single_string_char =
    choice([
      "\\'" |> string() |> replace(?'),
      "\\\\" |> string() |> replace(?\\),
      utf8_char(not: ?')
    ])

  double_quoted_string =
    [?"]
    |> ascii_char()
    |> ignore()
    |> repeat(double_string_char)
    |> ignore(ascii_char([?"]))
    |> reduce({List, :to_string, []})
    |> unwrap_and_tag(:literal)

  single_quoted_string =
    [?']
    |> ascii_char()
    |> ignore()
    |> repeat(single_string_char)
    |> ignore(ascii_char([?']))
    |> reduce({List, :to_string, []})
    |> unwrap_and_tag(:literal)

  # Boolean literals
  boolean =
    [
      "true" |> string() |> replace(true),
      "false" |> string() |> replace(false)
    ]
    |> choice()
    |> unwrap_and_tag(:literal)

  # Basic identifier (no dots or brackets)
  identifier =
    [?a..?z, ?A..?Z]
    |> ascii_char()
    |> repeat(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_]))
    |> reduce({List, :to_string, []})

  # Base variable (with optional $ prefix)
  base_variable =
    optional(ascii_char([?$]))
    |> concat(identifier)
    |> reduce({List, :to_string, []})
    |> unwrap_and_tag(:variable)

  # Dot access: .field
  dot_access =
    [?.]
    |> ascii_char()
    |> ignore()
    |> concat(identifier)
    |> unwrap_and_tag(:dot_access)

  # Atom literal for bracket access
  atom_literal =
    ignore(ascii_char([?:]))
    |> concat(identifier)
    |> reduce({__MODULE__, :create_atom, []})
    |> unwrap_and_tag(:literal)

  # Bracket access: [key] where key can be integer, string, or atom
  bracket_access =
    [?[]
    |> ascii_char()
    |> ignore()
    |> concat(whitespace)
    |> choice([
      integer,
      double_quoted_string,
      single_quoted_string,
      atom_literal
    ])
    |> concat(whitespace)
    |> ignore(ascii_char([?]]))
    |> unwrap_and_tag(:bracket_access)

  # Access chain: variable followed by zero or more dot/bracket accessors
  access_chain =
    base_variable
    |> repeat(choice([dot_access, bracket_access]))
    |> reduce({__MODULE__, :build_access_chain, []})

  # Unified variable identifier that supports access chains
  variable_identifier = access_chain

  # For backward compatibility, keep the old variable_name reference
  variable_name = variable_identifier

  # Function names
  function_name =
    [?a..?z, ?A..?Z]
    |> ascii_char()
    |> repeat(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_]))
    |> reduce({List, :to_string, []})

  # Forward declaration will be defined after pipe_expression

  # Parenthesized expression with full recursive support
  parenthesized_expression =
    [?(]
    |> ascii_char()
    |> ignore()
    |> concat(whitespace)
    |> parsec(:pipe_expr_parser)
    |> concat(whitespace)
    |> ignore(ascii_char([?)]))
    |> unwrap_and_tag(:grouped)

  # Simple expression for basic functionality
  simple_value =
    choice([
      parenthesized_expression,
      variable_name,
      float,
      integer,
      double_quoted_string,
      single_quoted_string,
      boolean
    ])

  # Function argument can include variable identifiers
  function_argument =
    choice([
      parenthesized_expression,
      variable_identifier,
      float,
      integer,
      double_quoted_string,
      single_quoted_string,
      boolean
    ])

  # Simple binary operations
  binary_op =
    choice([
      ">=" |> string() |> replace(:gte),
      "<=" |> string() |> replace(:lte),
      "==" |> string() |> replace(:eq),
      "!=" |> string() |> replace(:neq),
      "&&" |> string() |> replace(:and),
      "||" |> string() |> replace(:or),
      ">" |> string() |> replace(:gt),
      "<" |> string() |> replace(:lt),
      "+" |> string() |> replace(:add),
      "-" |> string() |> replace(:sub),
      "*" |> string() |> replace(:mul),
      "/" |> string() |> replace(:div)
    ])

  # Simple expression with binary operations
  simple_expression =
    simple_value
    |> repeat(
      whitespace
      |> concat(binary_op)
      |> concat(whitespace)
      |> concat(simple_value)
    )
    |> reduce({__MODULE__, :build_binary_ops, []})

  # Function call
  function_call =
    function_name
    |> ignore(ascii_char([?(]))
    |> concat(whitespace)
    |> optional(
      repeat(simple_expression, [?,] |> ascii_char() |> ignore() |> concat(whitespace) |> concat(simple_expression))
    )
    |> concat(whitespace)
    |> ignore(ascii_char([?)]))
    |> tag(:call)

  # Function call with arguments
  function_with_args =
    function_name
    |> ignore(ascii_char([?(]))
    |> concat(whitespace)
    |> optional(
      repeat(function_argument, whitespace |> ignore(ascii_char([?,])) |> concat(whitespace) |> concat(function_argument))
    )
    |> concat(whitespace)
    |> ignore(ascii_char([?)]))
    |> reduce({__MODULE__, :build_function_call, []})

  # Pipe operation (simple version)
  pipe_expression =
    simple_expression
    |> repeat(
      whitespace
      |> ignore(ascii_char([?|]))
      |> concat(whitespace)
      |> choice([function_with_args, function_name])
    )
    |> reduce({__MODULE__, :build_pipe_chain, []})

  # Main expression parser
  expression =
    choice([
      pipe_expression,
      function_call,
      simple_expression
    ])

  # Define recursive parser for parentheses
  defparsec(:pipe_expr_parser, pipe_expression)

  defparsec(
    :parse_expression,
    whitespace
    |> concat(expression)
    |> concat(whitespace)
  )

  @spec parse(String.t()) :: {:ok, any()} | {:error, String.t()}
  def parse(expression_string) when is_binary(expression_string) do
    case parse_expression(expression_string) do
      {:ok, [ast], "", _, _, _} ->
        {:ok, ast}

      {:ok, _ast, remainder, _, _, _} ->
        {:error, "Unexpected input after expression: #{inspect(remainder)}"}

      {:error, reason, _remainder, _context, line, column} ->
        {:error, "Expression parsing failed at line #{inspect(line)}, column #{inspect(column)}: #{inspect(reason)}"}
    end
  end

  # Helper functions for parse-time transformations
  def parse_integer([sign | digits_list]) when is_list(digits_list) do
    digits = List.to_string(digits_list)

    case sign do
      ?- -> -String.to_integer(digits)
      _ -> ([sign] ++ digits_list) |> List.to_string() |> String.to_integer()
    end
  end

  def parse_integer(digits_list) when is_list(digits_list) do
    digits_list |> List.to_string() |> String.to_integer()
  end

  def parse_float([sign | rest]) when sign in [?-, ?+] do
    rest |> List.to_string() |> String.to_float() |> then(fn f -> if sign == ?-, do: -f, else: f end)
  end

  def parse_float(float_chars) when is_list(float_chars) do
    float_chars |> List.to_string() |> String.to_float()
  end

  def build_binary_ops([left | rest]) do
    rest
    |> Enum.chunk_every(2)
    |> build_with_precedence([left], [])
  end

  # Build AST with proper operator precedence using a simplified approach
  defp build_with_precedence([], [result], []), do: result

  defp build_with_precedence([], operands, operators) do
    # Process remaining operators
    apply_remaining_operators(operands, operators)
  end

  defp build_with_precedence([[op, operand] | rest], operands, operators) do
    # Check if we should process operators on the stack first
    if should_process_stack?(op, operators) do
      # Process one operator from stack and continue
      {new_operands, new_operators} = process_one_operator(operands, operators)
      build_with_precedence([[op, operand] | rest], new_operands, new_operators)
    else
      # Push current operator and operand to stacks
      build_with_precedence(rest, [operand | operands], [op | operators])
    end
  end

  defp should_process_stack?(current_op, [stack_op | _]) do
    precedence(stack_op) >= precedence(current_op)
  end

  defp should_process_stack?(_, []), do: false

  defp precedence(:or), do: 1
  defp precedence(:and), do: 2
  defp precedence(:eq), do: 3
  defp precedence(:neq), do: 3
  defp precedence(:gt), do: 3
  defp precedence(:lt), do: 3
  defp precedence(:gte), do: 3
  defp precedence(:lte), do: 3
  defp precedence(:add), do: 4
  defp precedence(:sub), do: 4
  defp precedence(:mul), do: 5
  defp precedence(:div), do: 5

  defp process_one_operator([right, left | operands], [op | operators]) do
    result = {:binary_op, op, left, right}
    {[result | operands], operators}
  end

  defp apply_remaining_operators([result], []), do: result

  defp apply_remaining_operators([right, left | operands], [op | operators]) do
    result = {:binary_op, op, left, right}
    apply_remaining_operators([result | operands], operators)
  end

  def build_function_call([func_name | args]) do
    {:call, func_name, args || []}
  end

  def build_parenthesized_expression(parsed_elements) do
    # Handle parenthesized expressions with optional pipes and binary operations
    case parsed_elements do
      [single_element] -> single_element
      elements -> build_pipe_chain_and_binary_ops(elements)
    end
  end

  defp build_pipe_chain_and_binary_ops(elements) do
    # First handle pipe operations, then binary operations
    {base, rest} = extract_base_and_operations(elements)

    # Apply pipe operations first
    piped_result = apply_pipe_operations(base, rest)

    # Then apply binary operations if any
    apply_binary_operations(piped_result, rest)
  end

  defp extract_base_and_operations([base | rest]), do: {base, rest}

  defp apply_pipe_operations(base, operations) do
    operations
    |> Enum.filter(&is_pipe_operation?/1)
    |> Enum.reduce(base, fn func_name, acc ->
      {:call, func_name, [acc]}
    end)
  end

  defp apply_binary_operations(base, operations) do
    binary_ops = Enum.filter(operations, &is_binary_operation?/1)

    case binary_ops do
      [] -> base
      ops -> build_binary_ops([base | ops])
    end
  end

  defp is_pipe_operation?(element) when is_binary(element), do: true
  defp is_pipe_operation?(_), do: false

  defp is_binary_operation?(element) when element in [:add, :sub, :mul, :div], do: true
  defp is_binary_operation?(_), do: false

  def build_pipe_chain([base | pipe_parts]) do
    # Transform pipe chain into nested function calls
    # a | f | g(x) becomes g(f(a), x)
    Enum.reduce(pipe_parts, base, fn pipe_part, acc ->
      case pipe_part do
        # Simple function name without arguments
        func_name when is_binary(func_name) ->
          {:call, func_name, [acc]}

        # Function call with arguments
        {:call, func_name, args} ->
          {:call, func_name, [acc | args]}

        # Handle unsupported pipe_part types with clear error
        other ->
          raise ArgumentError,
                "Unsupported pipe operation: #{inspect(other)}. Expected function name (string) or function call tuple."
      end
    end)
  end

  def build_access_chain([{:variable, base_var} | accessors]) do
    case accessors do
      [] ->
        # Simple variable with no accessors
        {:variable, base_var}

      _ ->
        # Variable with access chain
        {:access_chain, base_var, accessors}
    end
  end

  def create_atom([atom_name]) when is_binary(atom_name) do
    String.to_atom(atom_name)
  end
end
