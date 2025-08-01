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

  # Variable identifiers (handling dotted paths like $input.name.field)
  context_variable =
    [?$]
    |> ascii_char()
    |> ascii_char([?a..?z, ?A..?Z])
    |> repeat(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_, ?.]))
    |> reduce({List, :to_string, []})
    |> unwrap_and_tag(:variable)

  # Local variables (like loop variables: user.name)
  local_variable =
    [?a..?z, ?A..?Z]
    |> ascii_char()
    |> repeat(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_, ?.]))
    |> reduce({List, :to_string, []})
    |> unwrap_and_tag(:local_variable)

  # Combined variable matching (context first, then local)
  variable_name = choice([context_variable, local_variable])

  # Unquoted identifier (for function arguments - treated as variable reference)
  unquoted_identifier =
    [?a..?z, ?A..?Z]
    |> ascii_char()
    |> repeat(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_, ?.]))
    |> reduce({List, :to_string, []})
    |> unwrap_and_tag(:unquoted_identifier)

  # Function names
  function_name =
    [?a..?z, ?A..?Z]
    |> ascii_char()
    |> repeat(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_]))
    |> reduce({List, :to_string, []})

  # Simple parenthesized expression with basic binary operations
  parenthesized_expression =
    [?(]
    |> ascii_char()
    |> ignore()
    |> concat(whitespace)
    |> choice([variable_name, float, integer, double_quoted_string, single_quoted_string, boolean])
    |> repeat(
      whitespace
      |> concat(
        choice([
          "+" |> string() |> replace(:add),
          "-" |> string() |> replace(:sub),
          "*" |> string() |> replace(:mul),
          "/" |> string() |> replace(:div)
        ])
      )
      |> concat(whitespace)
      |> choice([variable_name, float, integer, double_quoted_string, single_quoted_string, boolean])
    )
    |> concat(whitespace)
    |> ignore(ascii_char([?)]))
    |> reduce({__MODULE__, :build_binary_ops, []})
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

  # Function argument can include unquoted identifiers (treated as variables)
  function_argument =
    choice([
      parenthesized_expression,
      variable_name,
      unquoted_identifier,
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
    |> Enum.reduce(left, fn [op, right], acc ->
      {:binary_op, op, acc, right}
    end)
  end

  def build_function_call([func_name | args]) do
    {:call, func_name, args || []}
  end

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

        # Handle other patterns
        other ->
          {:call, inspect(other), [acc]}
      end
    end)
  end
end
