defmodule Prana.Template.Filters.StringFilters do
  @moduledoc """
  String manipulation filters for the template engine.
  """

  @doc """
  Returns the filter specification for this module.
  """
  def spec do
    %{
      name: "string_filters",
      description: "String manipulation filters",
      filters: [
        %{name: "upper_case", function: {__MODULE__, :upper_case}, description: "Convert string to uppercase"},
        %{name: "lower_case", function: {__MODULE__, :lower_case}, description: "Convert string to lowercase"},
        %{
          name: "capitalize",
          function: {__MODULE__, :capitalize},
          description: "Capitalize the first letter of a string"
        },
        %{name: "truncate", function: {__MODULE__, :truncate}, description: "Truncate string to specified length"},
        %{name: "default", function: {__MODULE__, :default}, description: "Provide default value for nil/empty values"}
      ]
    }
  end

  @doc """
  Convert string to uppercase.

  ## Examples

      {:ok, "HELLO"} = upper_case("hello", [])
  """
  @spec upper_case(String.t(), list()) :: {:ok, String.t()} | {:error, String.t()}
  def upper_case(value, []) when is_binary(value) do
    {:ok, String.upcase(value)}
  end

  def upper_case(value, []) do
    {:ok, value |> to_string() |> String.upcase()}
  end

  def upper_case(_value, _args) do
    {:error, "upper_case filter takes no arguments"}
  end

  @doc """
  Convert string to lowercase.

  ## Examples

      {:ok, "hello"} = lower_case("HELLO", [])
  """
  @spec lower_case(String.t(), list()) :: {:ok, String.t()} | {:error, String.t()}
  def lower_case(value, []) when is_binary(value) do
    {:ok, String.downcase(value)}
  end

  def lower_case(value, []) do
    {:ok, value |> to_string() |> String.downcase()}
  end

  def lower_case(_value, _args) do
    {:error, "lower_case filter takes no arguments"}
  end

  @doc """
  Capitalize the first letter of a string.

  ## Examples

      {:ok, "Hello world"} = capitalize("hello world", [])
  """
  @spec capitalize(String.t(), list()) :: {:ok, String.t()} | {:error, String.t()}
  def capitalize(value, []) when is_binary(value) do
    {:ok, String.capitalize(value)}
  end

  def capitalize(value, []) do
    {:ok, value |> to_string() |> String.capitalize()}
  end

  def capitalize(_value, _args) do
    {:error, "capitalize filter takes no arguments"}
  end

  @doc """
  Truncate string to specified length.

  ## Examples

      {:ok, "Hello..."} = truncate("Hello world", [8])
      {:ok, "Hello--"} = truncate("Hello world", [7, "--"])
  """
  @spec truncate(String.t(), list()) :: {:ok, String.t()} | {:error, String.t()}
  def truncate(value, [length]) when is_binary(value) and is_integer(length) do
    if String.length(value) <= length do
      {:ok, value}
    else
      {:ok, String.slice(value, 0, length - 3) <> "..."}
    end
  end

  def truncate(value, [length, suffix]) when is_binary(value) and is_integer(length) and is_binary(suffix) do
    if String.length(value) <= length do
      {:ok, value}
    else
      suffix_length = String.length(suffix)

      if length > suffix_length do
        truncate_length = length - suffix_length
        {:ok, String.slice(value, 0, truncate_length) <> suffix}
      else
        {:ok, String.slice(suffix, 0, length)}
      end
    end
  end

  def truncate(value, [length]) when is_integer(length) do
    truncate(to_string(value), [length])
  end

  def truncate(value, [length, suffix]) when is_integer(length) and is_binary(suffix) do
    truncate(to_string(value), [length, suffix])
  end

  def truncate(_value, _args) do
    {:error, "truncate filter requires length and optional suffix arguments"}
  end

  @doc """
  Provide default value for nil/empty values.

  ## Examples

      {:ok, "fallback"} = default(nil, ["fallback"])
      {:ok, "value"} = default("value", ["fallback"])
  """
  @spec default(any(), list()) :: {:ok, any()} | {:error, String.t()}
  def default(nil, [default_value]) do
    {:ok, default_value}
  end

  def default(value, [_default_value]) do
    {:ok, value}
  end

  def default(_value, _args) do
    {:error, "default filter requires exactly one argument"}
  end
end
