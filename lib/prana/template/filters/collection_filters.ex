defmodule Prana.Template.Filters.CollectionFilters do
  @moduledoc """
  Collection manipulation filters for the template engine.
  Handles lists, strings, and maps with comprehensive data operations.
  """

  @doc """
  Returns the filter specification for this module.
  """
  def spec do
    %{
      name: "collection_filters",
      description: "Collection manipulation and data operations",
      filters: [
        # Basic collection operations
        %{name: "length", function: {__MODULE__, :length}, description: "Get length/count of a collection"},
        %{name: "first", function: {__MODULE__, :first}, description: "Get first item from a collection"},
        %{name: "last", function: {__MODULE__, :last}, description: "Get last item from a collection"},
        %{name: "join", function: {__MODULE__, :join}, description: "Join array elements with separator"},
        
        # List operations
        %{name: "sort", function: {__MODULE__, :sort}, description: "Sort a list"},
        %{name: "reverse", function: {__MODULE__, :reverse}, description: "Reverse a list or string"},
        %{name: "uniq", function: {__MODULE__, :uniq}, description: "Get unique elements from list"},
        %{name: "slice", function: {__MODULE__, :slice}, description: "Extract slice from list or string"},
        %{name: "contains", function: {__MODULE__, :contains}, description: "Check if collection contains value"},
        %{name: "compact", function: {__MODULE__, :compact}, description: "Remove nil values from list"},
        %{name: "flatten", function: {__MODULE__, :flatten}, description: "Flatten nested lists"},
        %{name: "sum", function: {__MODULE__, :sum}, description: "Sum numeric values in list"},
        
        # Map operations
        %{name: "keys", function: {__MODULE__, :keys}, description: "Get keys of a map"},
        %{name: "values", function: {__MODULE__, :values}, description: "Get values of a map"},
        
        # List of maps operations
        %{name: "group_by", function: {__MODULE__, :group_by}, description: "Group list elements by key"},
        %{name: "map", function: {__MODULE__, :map}, description: "Extract field values from list of maps"},
        %{name: "filter", function: {__MODULE__, :filter}, description: "Filter list of maps by field value"},
        %{name: "reject", function: {__MODULE__, :reject}, description: "Reject list of maps by field value"},
        
        # Display formatting
        %{name: "dump", function: {__MODULE__, :dump}, description: "Format data structures for display"}
      ]
    }
  end

  # Basic collection operations

  @doc """
  Get length/count of a collection.

  ## Examples
      {:ok, 3} = length([1, 2, 3], [])
      {:ok, 5} = length("hello", [])
      {:ok, 2} = length(%{a: 1, b: 2}, [])
  """
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
  """
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
  """
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
  """
  def join(value, []) when is_list(value) do
    # Default to ", " separator when no argument is provided
    join(value, [", "])
  end

  def join(value, [separator]) when is_list(value) and is_binary(separator) do
    string_values = Enum.map(value, &to_string/1)
    {:ok, Enum.join(string_values, separator)}
  end

  def join(_value, []) do
    {:error, "join filter only works on lists"}
  end

  def join(_value, [_separator]) do
    {:error, "join filter only works on lists"}
  end

  def join(_value, _args) do
    {:error, "join filter requires optional separator argument"}
  end

  # List operations

  @doc """
  Sort a list in ascending order.
  """
  def sort(value, []) when is_list(value) do
    {:ok, Enum.sort(value)}
  end

  def sort(_value, []) do
    {:error, "sort filter only supports lists"}
  end

  def sort(_value, _args) do
    {:error, "sort filter takes no arguments"}
  end

  @doc """
  Reverse a list or string.
  """
  def reverse(value, []) when is_list(value) do
    {:ok, Enum.reverse(value)}
  end

  def reverse(value, []) when is_binary(value) do
    {:ok, String.reverse(value)}
  end

  def reverse(_value, []) do
    {:error, "reverse filter only supports lists and strings"}
  end

  def reverse(_value, _args) do
    {:error, "reverse filter takes no arguments"}
  end

  @doc """
  Get unique elements from a list.
  """
  def uniq(value, []) when is_list(value) do
    {:ok, Enum.uniq(value)}
  end

  def uniq(_value, []) do
    {:error, "uniq filter only supports lists"}
  end

  def uniq(_value, _args) do
    {:error, "uniq filter takes no arguments"}
  end

  @doc """
  Extract a slice from a list or string.
  """
  def slice(value, [start, length]) when is_list(value) and is_integer(start) and is_integer(length) do
    {:ok, Enum.slice(value, start, length)}
  end

  def slice(value, [start, length]) when is_binary(value) and is_integer(start) and is_integer(length) do
    {:ok, String.slice(value, start, length)}
  end

  def slice(_value, _args) do
    {:error, "slice filter requires exactly two integer arguments (start, length)"}
  end

  @doc """
  Check if a collection contains a value.
  """
  def contains(value, [item]) when is_list(value) do
    {:ok, item in value}
  end

  def contains(value, [substring]) when is_binary(value) and is_binary(substring) do
    {:ok, String.contains?(value, substring)}
  end

  def contains(_value, _args) do
    {:error, "contains filter requires exactly one argument"}
  end

  @doc """
  Remove nil values from a list.
  """
  def compact(value, []) when is_list(value) do
    {:ok, Enum.reject(value, &is_nil/1)}
  end

  def compact(_value, []) do
    {:error, "compact filter only supports lists"}
  end

  def compact(_value, _args) do
    {:error, "compact filter takes no arguments"}
  end

  @doc """
  Flatten nested lists to a single level.
  """
  def flatten(value, []) when is_list(value) do
    {:ok, List.flatten(value)}
  end

  def flatten(_value, []) do
    {:error, "flatten filter only supports lists"}
  end

  def flatten(_value, _args) do
    {:error, "flatten filter takes no arguments"}
  end

  @doc """
  Calculate the sum of numeric values in a list.
  """
  def sum(value, []) when is_list(value) do
    try do
      result = Enum.reduce(value, 0, fn
        item, acc when is_number(item) -> acc + item
        item, acc when is_binary(item) ->
          case Float.parse(item) do
            {num, _} -> acc + num
            :error -> throw({:error, "sum filter requires all elements to be numeric"})
          end
        _item, _acc -> throw({:error, "sum filter requires all elements to be numeric"})
      end)
      {:ok, result}
    catch
      {:error, message} -> {:error, message}
    end
  end

  def sum(_value, []) do
    {:error, "sum filter only supports lists"}
  end

  def sum(_value, _args) do
    {:error, "sum filter takes no arguments"}
  end

  # Map operations

  @doc """
  Get the keys of a map as a list.
  """
  def keys(value, []) when is_map(value) do
    {:ok, Map.keys(value)}
  end

  def keys(_value, []) do
    {:error, "keys filter only supports maps"}
  end

  def keys(_value, _args) do
    {:error, "keys filter takes no arguments"}
  end

  @doc """
  Get the values of a map as a list.
  """
  def values(value, []) when is_map(value) do
    {:ok, Map.values(value)}
  end

  def values(_value, []) do
    {:error, "values filter only supports maps"}
  end

  def values(_value, _args) do
    {:error, "values filter takes no arguments"}
  end

  # List of maps operations

  @doc """
  Group list elements by a specified key.
  """
  def group_by(value, [key]) when is_list(value) and is_binary(key) do
    try do
      result = Enum.group_by(value, fn item ->
        case item do
          %{} -> Map.get(item, key) || Map.get(item, String.to_atom(key))
          _ -> throw({:error, "group_by filter requires a list of maps"})
        end
      end)
      {:ok, result}
    catch
      {:error, message} -> {:error, message}
    end
  end

  def group_by(_value, _args) do
    {:error, "group_by filter requires a list of maps and a string key"}
  end

  @doc """
  Extract field values from a list of maps.
  """
  def map(value, [key]) when is_list(value) and is_binary(key) do
    try do
      result = Enum.map(value, fn item ->
        case item do
          %{} -> Map.get(item, key) || Map.get(item, String.to_atom(key))
          _ -> throw({:error, "map filter requires a list of maps"})
        end
      end)
      {:ok, result}
    catch
      {:error, message} -> {:error, message}
    end
  end

  def map(_value, _args) do
    {:error, "map filter requires a list of maps and a string key"}
  end

  @doc """
  Filter list of maps by field value.
  """
  def filter(value, [key, filter_value]) when is_list(value) and is_binary(key) do
    try do
      result = Enum.filter(value, fn item ->
        case item do
          %{} -> 
            item_value = Map.get(item, key) || Map.get(item, String.to_atom(key))
            item_value == filter_value
          _ -> throw({:error, "filter filter requires a list of maps"})
        end
      end)
      {:ok, result}
    catch
      {:error, message} -> {:error, message}
    end
  end

  def filter(_value, _args) do
    {:error, "filter filter requires a list of maps, a string key, and a filter value"}
  end

  @doc """
  Reject list of maps by field value (opposite of filter).
  """
  def reject(value, [key, reject_value]) when is_list(value) and is_binary(key) do
    try do
      result = Enum.reject(value, fn item ->
        case item do
          %{} -> 
            item_value = Map.get(item, key) || Map.get(item, String.to_atom(key))
            item_value == reject_value
          _ -> throw({:error, "reject filter requires a list of maps"})
        end
      end)
      {:ok, result}
    catch
      {:error, message} -> {:error, message}
    end
  end

  def reject(_value, _args) do
    {:error, "reject filter requires a list of maps, a string key, and a reject value"}
  end

  # Display formatting

  @doc """
  Format data structures for display in templates.
  """
  def dump(value, []) do
    formatted = case value do
      value when is_list(value) -> inspect(value, charlists: :as_lists)
      value when is_map(value) -> inspect(value)
      value when is_binary(value) -> value
      value -> inspect(value)
    end
    {:ok, formatted}
  end

  def dump(_value, _args) do
    {:error, "dump filter takes no arguments"}
  end
end