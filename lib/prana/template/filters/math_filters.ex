defmodule Prana.Template.Filters.MathFilters do
  @moduledoc """
  Math filters for mathematical operations and calculations.
  """

  @doc """
  Filter module specification for registry integration.
  """
  def spec do
    %{
      name: "math_filters",
      description: "Mathematical operations and calculations",
      filters: [
        %{name: "abs", function: {__MODULE__, :abs}, description: "Absolute value"},
        %{name: "ceil", function: {__MODULE__, :ceil}, description: "Round up to nearest integer"},
        %{name: "floor", function: {__MODULE__, :floor}, description: "Round down to nearest integer"},
        %{name: "max", function: {__MODULE__, :max}, description: "Maximum of two values"},
        %{name: "min", function: {__MODULE__, :min}, description: "Minimum of two values"},
        %{name: "power", function: {__MODULE__, :power}, description: "Raise to power"},
        %{name: "sqrt", function: {__MODULE__, :sqrt}, description: "Square root"},
        %{name: "mod", function: {__MODULE__, :mod}, description: "Modulo operation"},
        %{name: "clamp", function: {__MODULE__, :clamp}, description: "Clamp value between min and max"}
      ]
    }
  end

  @doc """
  Absolute value filter.

  ## Examples
      {{ -42 | abs }}          # => 42
      {{ 3.14 | abs }}         # => 3.14
      {{ -3.14 | abs }}        # => 3.14
  """
  def abs(value, []) when is_number(value) do
    {:ok, Kernel.abs(value)}
  end

  def abs(value, []) when is_binary(value) do
    case Float.parse(value) do
      {num, ""} -> {:ok, Kernel.abs(num)}
      {num, _} -> {:ok, Kernel.abs(num)}
      :error -> {:error, "abs filter requires a numeric value"}
    end
  end

  def abs(_value, _args) do
    {:error, "abs filter takes no arguments"}
  end

  @doc """
  Ceiling filter - rounds up to nearest integer.

  ## Examples
      {{ 3.14 | ceil }}        # => 4
      {{ 3.0 | ceil }}         # => 3
      {{ -2.5 | ceil }}        # => -2
  """
  def ceil(value, []) when is_number(value) do
    {:ok, (value / 1) |> Float.ceil() |> trunc()}
  end

  def ceil(value, []) when is_binary(value) do
    case Float.parse(value) do
      {num, _} -> {:ok, (num / 1) |> Float.ceil() |> trunc()}
      :error -> {:error, "ceil filter requires a numeric value"}
    end
  end

  def ceil(_value, _args) do
    {:error, "ceil filter takes no arguments"}
  end

  @doc """
  Floor filter - rounds down to nearest integer.

  ## Examples
      {{ 3.14 | floor }}       # => 3
      {{ 3.9 | floor }}        # => 3
      {{ -2.5 | floor }}       # => -3
  """
  def floor(value, []) when is_number(value) do
    {:ok, (value / 1) |> Float.floor() |> trunc()}
  end

  def floor(value, []) when is_binary(value) do
    case Float.parse(value) do
      {num, _} -> {:ok, (num / 1) |> Float.floor() |> trunc()}
      :error -> {:error, "floor filter requires a numeric value"}
    end
  end

  def floor(_value, _args) do
    {:error, "floor filter takes no arguments"}
  end

  @doc """
  Maximum value filter.

  ## Examples
      {{ 5 | max(10) }}        # => 10
      {{ 15 | max(10) }}       # => 15
  """
  def max(value, [other]) when is_number(value) and is_number(other) do
    {:ok, Kernel.max(value, other)}
  end

  def max(value, [other]) when is_binary(value) do
    case Float.parse(value) do
      {num, _} when is_number(other) -> {:ok, Kernel.max(num, other)}
      :error -> {:error, "max filter requires numeric values"}
    end
  end

  def max(value, [other]) when is_number(value) and is_binary(other) do
    case Float.parse(other) do
      {num, _} -> {:ok, Kernel.max(value, num)}
      :error -> {:error, "max filter requires numeric values"}
    end
  end

  def max(_value, _args) do
    {:error, "max filter requires exactly one numeric argument"}
  end

  @doc """
  Minimum value filter.

  ## Examples
      {{ 5 | min(10) }}        # => 5
      {{ 15 | min(10) }}       # => 10
  """
  def min(value, [other]) when is_number(value) and is_number(other) do
    {:ok, Kernel.min(value, other)}
  end

  def min(value, [other]) when is_binary(value) do
    case Float.parse(value) do
      {num, _} when is_number(other) -> {:ok, Kernel.min(num, other)}
      :error -> {:error, "min filter requires numeric values"}
    end
  end

  def min(value, [other]) when is_number(value) and is_binary(other) do
    case Float.parse(other) do
      {num, _} -> {:ok, Kernel.min(value, num)}
      :error -> {:error, "min filter requires numeric values"}
    end
  end

  def min(_value, _args) do
    {:error, "min filter requires exactly one numeric argument"}
  end

  @doc """
  Power filter - raises value to the power of exponent.

  ## Examples
      {{ 2 | power(3) }}       # => 8.0
      {{ 5 | power(2) }}       # => 25.0
  """
  def power(value, [exponent]) when is_number(value) and is_number(exponent) do
    {:ok, :math.pow(value, exponent)}
  end

  def power(value, [exponent]) when is_binary(value) do
    case Float.parse(value) do
      {num, _} when is_number(exponent) -> {:ok, :math.pow(num, exponent)}
      :error -> {:error, "power filter requires numeric values"}
    end
  end

  def power(value, [exponent]) when is_number(value) and is_binary(exponent) do
    case Float.parse(exponent) do
      {num, _} -> {:ok, :math.pow(value, num)}
      :error -> {:error, "power filter requires numeric values"}
    end
  end

  def power(_value, _args) do
    {:error, "power filter requires exactly one numeric argument"}
  end

  @doc """
  Square root filter.

  ## Examples
      {{ 16 | sqrt }}          # => 4.0
      {{ 2 | sqrt }}           # => 1.4142135623730951
  """
  def sqrt(value, []) when is_number(value) and value >= 0 do
    {:ok, :math.sqrt(value)}
  end

  def sqrt(value, []) when is_number(value) and value < 0 do
    {:error, "sqrt filter cannot calculate square root of negative number"}
  end

  def sqrt(value, []) when is_binary(value) do
    case Float.parse(value) do
      {num, _} when num >= 0 -> {:ok, :math.sqrt(num)}
      {num, _} when num < 0 -> {:error, "sqrt filter cannot calculate square root of negative number"}
      :error -> {:error, "sqrt filter requires a numeric value"}
    end
  end

  def sqrt(_value, _args) do
    {:error, "sqrt filter takes no arguments"}
  end

  @doc """
  Modulo filter - returns remainder of division.

  ## Examples
      {{ 17 | mod(5) }}     # => 2
      {{ 20 | mod(3) }}     # => 2
  """
  def mod(value, [divisor]) when is_number(value) and is_number(divisor) and divisor != 0 do
    {:ok, rem(trunc(value), trunc(divisor))}
  end

  def mod(_value, [0]) do
    {:error, "mod filter cannot divide by zero"}
  end

  def mod(value, [divisor]) when is_binary(value) do
    case Float.parse(value) do
      {num, _} when is_number(divisor) and divisor != 0 ->
        {:ok, rem(trunc(num), trunc(divisor))}

      :error ->
        {:error, "mod filter requires numeric values"}
    end
  end

  def mod(value, [divisor]) when is_number(value) and is_binary(divisor) do
    case Float.parse(divisor) do
      {num, _} when num != 0.0 -> {:ok, rem(trunc(value), trunc(num))}
      {num, _} when num == 0.0 -> {:error, "mod filter cannot divide by zero"}
      :error -> {:error, "mod filter requires numeric values"}
    end
  end

  def mod(_value, _args) do
    {:error, "mod filter requires exactly one numeric argument"}
  end

  @doc """
  Clamp filter - constrains value between min and max.

  ## Examples
      {{ 5 | clamp(0, 10) }}   # => 5
      {{ -5 | clamp(0, 10) }}  # => 0
      {{ 15 | clamp(0, 10) }}  # => 10
  """
  def clamp(value, [min_val, max_val]) when is_number(value) and is_number(min_val) and is_number(max_val) do
    if min_val <= max_val do
      clamped = value |> Kernel.max(min_val) |> Kernel.min(max_val)
      {:ok, clamped}
    else
      {:error, "clamp filter requires min_val (#{min_val}) to be <= max_val (#{max_val})"}
    end
  end

  def clamp(_value, _args) do
    {:error, "clamp filter requires exactly two numeric arguments (min, max)"}
  end
end
