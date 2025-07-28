defmodule Prana.Integrations.Code.SecurityPolicy do
  @moduledoc """
  Security Policy for Elixir Code Execution

  Defines whitelisted operators, functions, and validation rules based on Sequin's
  MiniElixir security model. This policy ensures safe execution of user code
  by explicitly allowing only trusted operations.
  """

  @doc """
  Returns list of allowed binary and unary operators.
  Based on Sequin's whitelist for mathematical, logical, and string operations.
  """
  def allowed_operators do
    [
      # Arithmetic operators
      :+,
      :-,
      :*,
      :/,
      :rem,
      :div,

      # Comparison operators  
      :==,
      :!=,
      :<,
      :>,
      :<=,
      :>=,

      # Logical operators
      :and,
      :or,
      :not,
      :&&,
      :||,
      :!,

      # List operators
      :++,
      :--,

      # String/pipeline operators
      :|>,
      :<>,
      :=~,

      # Membership operator
      :in
    ]
  end

  @doc """
  Returns list of allowed function calls in {Module, function, arity} format.
  Based on Sequin's comprehensive whitelist for safe operations.
  """
  def allowed_functions do
    string_functions() ++
      enum_functions() ++
      map_functions() ++
      list_functions() ++
      kernel_functions() ++
      datetime_functions() ++
      numeric_functions() ++
      regex_functions()
  end

  @doc """
  Returns list of allowed unary operators.
  """
  def allowed_unary_operators do
    [:!, :not, :-]
  end

  @doc """
  Checks if an operator is allowed.
  """
  def operator_allowed?(op) do
    op in allowed_operators()
  end

  @doc """
  Checks if a function call is allowed.
  """
  def function_allowed?(module, function, arity) do
    {module, function, arity} in allowed_functions()
  end

  @doc """
  Checks if a unary operator is allowed.
  """
  def unary_operator_allowed?(op) do
    op in allowed_unary_operators()
  end

  # Private functions to organize the whitelist

  defp string_functions do
    [
      {:String, :length, 1},
      {:String, :trim, 1},
      {:String, :upcase, 1},
      {:String, :downcase, 1},
      {:String, :capitalize, 1},
      {:String, :contains?, 2},
      {:String, :starts_with?, 2},
      {:String, :ends_with?, 2},
      {:String, :slice, 2},
      {:String, :slice, 3},
      {:String, :split, 2},
      {:String, :replace, 3},
      {:String, :replace, 4},
      {:String, :to_integer, 1},
      {:String, :to_float, 1},
      {:String, :to_atom, 1}
    ]
  end

  defp enum_functions do
    [
      {:Enum, :map, 2},
      {:Enum, :filter, 2},
      {:Enum, :reduce, 3},
      {:Enum, :find, 2},
      {:Enum, :any?, 2},
      {:Enum, :all?, 2},
      {:Enum, :count, 1},
      {:Enum, :count, 2},
      {:Enum, :empty?, 1},
      {:Enum, :member?, 2},
      {:Enum, :at, 2},
      {:Enum, :first, 1},
      {:Enum, :last, 1},
      {:Enum, :take, 2},
      {:Enum, :drop, 2},
      {:Enum, :reverse, 1},
      {:Enum, :sort, 1},
      {:Enum, :sort, 2},
      {:Enum, :uniq, 1},
      {:Enum, :join, 2},
      {:Enum, :concat, 2},
      {:Enum, :flat_map, 2}
    ]
  end

  defp map_functions do
    [
      {:Map, :get, 2},
      {:Map, :get, 3},
      {:Map, :put, 3},
      {:Map, :delete, 2},
      {:Map, :has_key?, 2},
      {:Map, :keys, 1},
      {:Map, :values, 1},
      {:Map, :merge, 2},
      {:Map, :new, 0},
      {:Map, :size, 1}
    ]
  end

  defp list_functions do
    [
      {:List, :first, 1},
      {:List, :last, 1},
      {:List, :wrap, 1},
      {:List, :flatten, 1}
    ]
  end

  defp kernel_functions do
    [
      {:Kernel, :length, 1},
      {:Kernel, :hd, 1},
      {:Kernel, :tl, 1},
      {:Kernel, :is_atom, 1},
      {:Kernel, :is_binary, 1},
      {:Kernel, :is_boolean, 1},
      {:Kernel, :is_float, 1},
      {:Kernel, :is_integer, 1},
      {:Kernel, :is_list, 1},
      {:Kernel, :is_map, 1},
      {:Kernel, :is_nil, 1},
      {:Kernel, :is_number, 1},
      {:Kernel, :is_tuple, 1},
      {:Kernel, :max, 2},
      {:Kernel, :min, 2},
      {:Kernel, :abs, 1},
      {:Kernel, :round, 1},
      {:Kernel, :trunc, 1},
      {:Kernel, :floor, 1},
      {:Kernel, :ceil, 1},
      {:Kernel, :elem, 2},
      {:Kernel, :tuple_size, 1}
    ]
  end

  defp datetime_functions do
    [
      {:DateTime, :utc_now, 0},
      {:DateTime, :to_string, 1},
      {:DateTime, :to_date, 1},
      {:DateTime, :to_time, 1},
      {:DateTime, :add, 3},
      {:DateTime, :diff, 2},
      {:DateTime, :compare, 2},
      {:Date, :utc_today, 0},
      {:Date, :to_string, 1},
      {:Date, :add, 2},
      {:Date, :diff, 2},
      {:Date, :compare, 2},
      {:Time, :utc_now, 0},
      {:Time, :to_string, 1},
      {:Time, :add, 2},
      {:Time, :diff, 2},
      {:Time, :compare, 2}
    ]
  end

  defp numeric_functions do
    [
      {:Integer, :to_string, 1},
      {:Integer, :parse, 1},
      {:Float, :to_string, 1},
      {:Float, :parse, 1},
      {:Float, :round, 1},
      {:Float, :round, 2},
      {:Float, :ceil, 1},
      {:Float, :floor, 1}
    ]
  end

  defp regex_functions do
    [
      {:Regex, :match?, 2},
      {:Regex, :run, 2},
      {:Regex, :scan, 2},
      {:Regex, :replace, 3},
      {:Regex, :replace, 4}
    ]
  end
end
