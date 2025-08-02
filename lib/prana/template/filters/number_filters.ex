defmodule Prana.Template.Filters.NumberFilters do
  @moduledoc """
  Number formatting filters for the template engine.
  """

  @doc """
  Returns the filter specification for this module.
  """
  def spec do
    %{
      name: "number_filters",
      description: "Number formatting filters",
      filters: [
        %{name: "round", function: {__MODULE__, :round}, description: "Round number to specified decimal places"},
        %{name: "format_currency", function: {__MODULE__, :format_currency}, description: "Format number as currency"}
      ]
    }
  end

  @doc """
  Round number to specified decimal places.

  ## Examples

      {:ok, 3.14} = round(3.14159, [2])
      {:ok, 3} = round(3.14159, [0])
  """
  @spec round(number(), list()) :: {:ok, number()} | {:error, String.t()}
  def round(value, []) when is_number(value) do
    {:ok, Kernel.round(value)}
  end

  def round(value, [decimals]) when is_number(value) and is_integer(decimals) and decimals >= 0 do
    multiplier = :math.pow(10, decimals)
    {:ok, Kernel.round(value * multiplier) / multiplier}
  end

  def round(value, args) when is_binary(value) do
    case Float.parse(value) do
      {num, ""} ->
        round(num, args)

      _ ->
        case Integer.parse(value) do
          {num, ""} -> round(num, args)
          _ -> {:error, "Cannot parse number: #{value}"}
        end
    end
  end

  def round(_value, _args) do
    {:error, "round filter requires a number and optional decimal places"}
  end

  @doc """
  Format number as currency.

  ## Examples

      {:ok, "$42.00"} = format_currency(42, ["USD"])
      {:ok, "€42.00"} = format_currency(42, ["EUR"])
  """
  @spec format_currency(number(), list()) :: {:ok, String.t()} | {:error, String.t()}
  def format_currency(value, []) when is_number(value) do
    # Default to USD when no currency code is provided
    format_currency(value, ["USD"])
  end

  def format_currency(value, [currency_code]) when is_number(value) and is_binary(currency_code) do
    # Simple currency formatting - in production you might use a proper i18n library
    symbol = get_currency_symbol(currency_code)
    formatted_amount = format_decimal(value, 2)
    {:ok, "#{symbol}#{formatted_amount}"}
  end

  def format_currency(value, []) when is_binary(value) do
    # Default to USD when no currency code is provided
    format_currency(value, ["USD"])
  end

  def format_currency(value, [currency_code]) when is_binary(value) do
    case Float.parse(value) do
      {num, ""} ->
        format_currency(num, [currency_code])

      _ ->
        case Integer.parse(value) do
          {num, ""} -> format_currency(num, [currency_code])
          _ -> {:error, "Cannot parse number: #{value}"}
        end
    end
  end

  def format_currency(_value, _args) do
    {:error, "format_currency filter requires a number and optional currency code"}
  end

  # Private helper functions

  defp get_currency_symbol("USD"), do: "$"
  defp get_currency_symbol("EUR"), do: "€"
  defp get_currency_symbol("GBP"), do: "£"
  defp get_currency_symbol("JPY"), do: "¥"
  defp get_currency_symbol(code), do: code <> " "

  defp format_decimal(value, decimals) do
    :erlang.float_to_binary(value / 1, decimals: decimals)
  rescue
    _ ->
      # Fallback for integers
      "~.#{decimals}f"
      |> :io_lib.format([value / 1])
      |> to_string()
  end
end
