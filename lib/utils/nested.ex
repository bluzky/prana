defmodule Nested do
  @moduledoc false
  @doc """
  Query data nested in map and list, return default if path not exist

  Example:

  get(%{a: 1, b: [%{name: "test1"}, %{name: "test"2}]}, [:b, 0, :name])
  #> "test1"
  """
  def get(object, paths, default \\ nil) do
    case fetch(object, paths) do
      {:ok, data} -> data
      :error -> default
    end
  end

  @doc """
  Query data nested in map and list
  Return: `{:ok, data}` if found and `:error` if not found

  It support compare condition for list item which is a map

  **Example**

      data = %{users:
        [
          %{name: "user1", is_active: true, skills: ["js", "html"]},
          %{name: "user2", is_active: false, skills: ["elixir", "sql"]}]
        }

      Nested.fetch(data, [:users, %{is_active: true}, :skills ])

      #> {:ok, ["js", "html"]}
  """

  def fetch(nil, _) do
    :error
  end

  def fetch(value, []), do: {:ok, value}

  def fetch(object, [key | tail]) when is_map(object) do
    case Map.fetch(object, key) do
      {:ok, value} ->
        fetch(value, tail)

      error ->
        error
    end
  end

  def fetch(list, [key | tail]) when is_list(list) do
    cond do
      is_integer(key) ->
        case Enum.fetch(list, key) do
          {:ok, value} -> fetch(value, tail)
          error -> error
        end

      is_atom(key) ->
        case Keyword.fetch(list, key) do
          {:ok, value} -> fetch(value, tail)
          error -> error
        end

      is_map(key) ->
        case Enum.find(list, &item_matched?(&1, key)) do
          nil -> :error
          value -> fetch(value, tail)
        end

      is_function(key, 1) ->
        case Enum.find(list, key) do
          nil -> :error
          value -> fetch(value, tail)
        end

      true ->
        :error
    end
  end

  @doc """
  Query data nested in map and list

  **Params**:
  - `object`: map or list
  - `paths`: list of key or index, or function to compare
    + `*` match all
    + `integer` match index or map key
    + `atom` match keyword key or map key
    + `map` match map item in list
    + `function` match list item with function
    + `string` match map string key

  **Example**

      data = %{users:
        [
          %{name: "user1", is_active: true, skills: ["js", "html"]},
          %{name: "user2", is_active: false, skills: ["elixir", "sql"]}]
        }

      Nested.extract(data, [:users, "*", :skills ])

      #> [["js", "html"], ["elixir", "sql"]]

  """
  @spec extract(map | list, list) :: list
  def extract(object, [key | tail]) when is_map(object) do
    case Map.fetch(object, key) do
      {:ok, value} ->
        extract(value, tail)

      _error ->
        []
    end
  end

  def extract(list, [key | tail]) when is_list(list) do
    cond do
      key == "*" ->
        # match all
        list
        |> Enum.map(&extract(&1, tail))
        |> Enum.concat()

      is_integer(key) ->
        case Enum.fetch(list, key) do
          {:ok, value} -> extract(value, tail)
          _error -> []
        end

      is_atom(key) ->
        case Keyword.fetch(list, key) do
          {:ok, value} -> extract(value, tail)
          _error -> []
        end

      is_map(key) ->
        list
        |> Enum.filter(&item_matched?(&1, key))
        |> Enum.map(&extract(&1, tail))
        |> Enum.concat()

      is_function(key, 1) ->
        list
        |> Enum.filter(key)
        |> Enum.map(&extract(&1, tail))
        |> Enum.concat()

      true ->
        []
    end
  end

  def extract(value, []), do: [value]
  def extract(_, _), do: []

  # check if map meets criterials
  defp item_matched?(item, criterials) when is_map(item) and is_map(criterials) do
    criterials == Map.take(item, Map.keys(criterials))
  end

  defp item_matched?(_, _), do: false

  @doc """
  Traverse map and list, apply function to each item

  **Params**:
  - `object`: map or list
  - `fun/1`: function to apply to each item of map or list and return one of:
    + `:discard`: discard item
    + `{:skip, item}`: skip traverse nested value
    + `{:next, item}`: traverse nested value
    + `item`: behavior as `{:next, item}`

  **Examples**:
        # remove all `is_active` key
        data = %{users:
          [
            %{name: "user1", is_active: true, skills: ["js", "html"]},
            %{name: "user2", is_active: false, skills: ["elixir", "sql"]}]
          }

        Nested.traverse(data, fn
          {:is_active, _} -> :discard
          item -> IO.inspect(item)
        end)

        #> %{users:
          [
            %{name: "user1", skills: ["js", "html"]},
            %{name: "user2", skills: ["elixir", "sql"]}]
          }
  """
  @ignore_types [DateTime, NaiveDateTime, Date, Time]
  def traverse(%type{} = object, _) when type in @ignore_types, do: object
  def traverse(object, fun) when is_struct(object), do: traverse(Map.from_struct(object), fun)

  def traverse(object, fun) when is_map(object) do
    Enum.reduce(object, %{}, fn {key, value}, acc ->
      case fun.({key, value}) do
        :discard -> acc
        {:skip, {key, value}} -> Map.put(acc, key, value)
        {:next, {key, value}} -> Map.put(acc, key, traverse(value, fun))
        {key, value} -> Map.put(acc, key, traverse(value, fun))
      end
    end)
  end

  def traverse(object, fun) when is_list(object) do
    object
    |> Enum.reduce([], fn item, acc ->
      case fun.(item) do
        :discard -> acc
        {:skip, item} -> [item | acc]
        {:next, item} -> [traverse(item, fun) | acc]
        item -> [traverse(item, fun) | acc]
      end
    end)
    |> Enum.reverse()
  end

  def traverse(object, _fun), do: object

  @doc """
  Clean nil value in map and list
  """
  def clean_nil(object) do
    traverse(object, fn
      nil -> :discard
      {_, nil} -> :discard
      value -> {:next, value}
    end)
  end

  @doc """
  Convert struct to map by removing `__struct__` and `__meta__` keys
  """
  def to_map(struct) do
    traverse(struct, fn
      %type{} = value when type in @ignore_types -> {:skip, value}
      value when is_struct(value) -> {:next, Map.drop(value, [:__struct__, :__meta__])}
      value -> {:next, value}
    end)
  end

  @doc """
  Replace value in map and list with  `***` if key match any of keywords

  **Examples**

      data = %{users:
        [
          %{name: "user1", is_active: true, skills: ["js", "html"]},
          %{name: "user2", is_active: false, skills: ["elixir", "sql"]}]
        }

      Nested.censor(data, ["active", "skills"])

      #> %{users:
        [
          %{name: "user1", is_active: "***", skills: "***"},
          %{name: "user2", is_active: "***", skills: "***"}]
        }
  """
  def censor(object, keywords) when is_list(keywords) do
    traverse(object, fn
      {key, value} ->
        should_censor? = Enum.any?(keywords, &String.contains?(to_string(key), &1))

        if should_censor? do
          {:skip, {key, "***"}}
        else
          {:next, {key, value}}
        end

      value ->
        {:next, value}
    end)
  end

  @doc """
  Merge two maps deeply, preferring values from the right map.
  """
  def merge(left, right) do
    Map.merge(left, right, &deep_resolve/3)
  end

  # Key exists in both maps, and both values are maps as well.
  # These can be merged recursively.
  defp deep_resolve(_key, left = %{}, right = %{}) do
    merge(left, right)
  end

  # Key exists in both maps, but at least one of the values is
  # NOT a map. We fall back to standard merge behavior, preferring
  # the value on the right.
  defp deep_resolve(_key, _left, right) do
    right
  end
end
