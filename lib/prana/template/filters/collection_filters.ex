defmodule Prana.Template.Filters.CollectionFilters do
  @moduledoc """
  Collection manipulation filters for the template engine.
  """

  @doc """
  Returns the filter specification for this module.
  """
  def spec do
    %{
      name: "collection_filters",
      description: "Collection manipulation filters",
      filters: [
        %{name: "length", function: {__MODULE__, :length}, description: "Get length/count of a collection"},
        %{name: "first", function: {__MODULE__, :first}, description: "Get first item from a collection"},
        %{name: "last", function: {__MODULE__, :last}, description: "Get last item from a collection"},
        %{name: "join", function: {__MODULE__, :join}, description: "Join array elements with separator"}
      ]
    }
  end

  @doc """
  Get length/count of a collection.

  ## Examples

      {:ok, 3} = length([1, 2, 3], [])
      {:ok, 5} = length("hello", [])
      {:ok, 2} = length(%{a: 1, b: 2}, [])
  """
  @spec length(any(), list()) :: {:ok, integer()} | {:error, String.t()}
  def length(value, []) when is_list(value) do
    {:ok, Enum.count(value)}
  end

  def length(value, []) when is_binary(value) do
    {:ok, String.length(value)}
  end

  def length(value, []) when is_map(value) do
    {:ok, map_size(value)}
  end

  def length(_value, []) do
    {:error, "length filter only works on lists, strings, and maps"}
  end

  def length(_value, _args) do
    {:error, "length filter takes no arguments"}
  end

  @doc """
  Get first item from a collection.

  ## Examples

      {:ok, 1} = first([1, 2, 3], [])
      {:ok, "h"} = first("hello", [])
      {:ok, nil} = first([], [])
  """
  @spec first(any(), list()) :: {:ok, any()} | {:error, String.t()}
  def first(value, []) when is_list(value) do
    {:ok, List.first(value)}
  end

  def first(value, []) when is_binary(value) do
    case String.first(value) do
      nil -> {:ok, nil}
      char -> {:ok, char}
    end
  end

  def first(_value, []) do
    {:error, "first filter only works on lists and strings"}
  end

  def first(_value, _args) do
    {:error, "first filter takes no arguments"}
  end

  @doc """
  Get last item from a collection.

  ## Examples

      {:ok, 3} = last([1, 2, 3], [])
      {:ok, "o"} = last("hello", [])
      {:ok, nil} = last([], [])
  """
  @spec last(any(), list()) :: {:ok, any()} | {:error, String.t()}
  def last(value, []) when is_list(value) do
    {:ok, List.last(value)}
  end

  def last(value, []) when is_binary(value) do
    case String.last(value) do
      nil -> {:ok, nil}
      char -> {:ok, char}
    end
  end

  def last(_value, []) do
    {:error, "last filter only works on lists and strings"}
  end

  def last(_value, _args) do
    {:error, "last filter takes no arguments"}
  end

  @doc """
  Join array elements with separator.

  ## Examples

      {:ok, "1,2,3"} = join([1, 2, 3], [","])
      {:ok, "a-b-c"} = join(["a", "b", "c"], ["-"])
      {:ok, "abc"} = join(["a", "b", "c"], [""])
  """
  @spec join(list(), list()) :: {:ok, String.t()} | {:error, String.t()}
  def join(value, [separator]) when is_list(value) and is_binary(separator) do
    string_values = Enum.map(value, &to_string/1)
    {:ok, Enum.join(string_values, separator)}
  end

  def join(_value, [_separator]) do
    {:error, "join filter only works on lists"}
  end

  def join(_value, _args) do
    {:error, "join filter requires exactly one separator argument"}
  end
end
