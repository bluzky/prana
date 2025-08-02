defmodule Prana.Template.FilterRegistry do
  @moduledoc """
  Compile-time filter registry that loads filter modules from configuration.

  This module uses `Application.compile_env` to load filter modules at compile time,
  eliminating runtime overhead while providing flexibility through configuration.

  ## Configuration

  Configure filter modules in your application config:

      # config/config.exs
      config :prana, :template_filters, [
        Prana.Template.Filters.StringFilters,
        Prana.Template.Filters.NumberFilters,
        Prana.Template.Filters.CollectionFilters,
        Prana.Template.Filters.MathFilters
      ]

  ## Filter Module Contract

  Each filter module must implement a `spec/0` function that returns:

      %{
        name: "module_name",
        description: "Module description",
        filters: [
          %{name: "filter_name", function: &module.function/2, description: "Filter description"}
        ]
      }
  """

  # Load filter modules from compile-time configuration
  @filter_modules Application.compile_env(:prana, :template_filters, [
                    Prana.Template.Filters.StringFilters,
                    Prana.Template.Filters.NumberFilters,
                    Prana.Template.Filters.CollectionFilters,
                    Prana.Template.Filters.MathFilters
                  ])

  # Build filter map at compile time
  @filters (for module <- @filter_modules,
                %{filters: filters} = module.spec(),
                %{name: name, function: function} <- filters,
                into: %{} do
              {name, function}
            end)

  # Build filter specs map for documentation/introspection
  @filter_specs (for module <- @filter_modules,
                     spec = module.spec(),
                     into: %{} do
                   {spec.name, spec}
                 end)

  @doc """
  Get a filter function by name.

  ## Examples

      iex> get_filter("upper_case")
      &Prana.Template.Filters.StringFilters.upper_case/2

      iex> get_filter("unknown_filter")
      nil
  """
  @spec get_filter(String.t()) :: (any(), list() -> {:ok, any()} | {:error, String.t()}) | nil
  def get_filter(name) when is_binary(name) do
    Map.get(@filters, name)
  end

  @doc """
  Apply a filter to a value with the given arguments.

  ## Examples

      {:ok, "HELLO"} = apply_filter("upper_case", "hello", [])
      {:ok, "$42.00"} = apply_filter("format_currency", 42, ["USD"])
  """
  @spec apply_filter(String.t(), any(), list()) :: {:ok, any()} | {:error, String.t()}
  def apply_filter(filter_name, value, args \\ []) do
    case get_filter(filter_name) do
      nil ->
        {:error, "Unknown filter: #{filter_name}"}

      filter_func ->
        try do
          case filter_func do
            {mod, func} when is_atom(mod) and is_atom(func) ->
              apply(mod, func, [value, args])

            _ ->
              filter_func.(value, args)
          end
        rescue
          error ->
            {:error, "Filter error: #{Exception.message(error)}"}
        catch
          :exit, reason ->
            {:error, "Filter exit: #{inspect(reason)}"}

          :throw, value ->
            {:error, "Filter throw: #{inspect(value)}"}
        end
    end
  end

  @doc """
  List all available filter names.

  ## Examples

      iex> list_filters()
      ["upper_case", "lower_case", "capitalize", "truncate", "default", "round", "format_currency", "length", "first", "last", "join"]
  """
  @spec list_filters() :: [String.t()]
  def list_filters do
    @filters |> Map.keys() |> Enum.sort()
  end

  @doc """
  Get filter specification by module name.

  ## Examples

      iex> get_filter_spec("string_filters")
      %{name: "string_filters", description: "String manipulation filters", filters: [...]}
  """
  @spec get_filter_spec(String.t()) :: map() | nil
  def get_filter_spec(module_name) when is_binary(module_name) do
    Map.get(@filter_specs, module_name)
  end

  @doc """
  List all filter module specifications.

  ## Examples

      iex> list_filter_specs()
      [%{name: "string_filters", ...}, %{name: "number_filters", ...}, ...]
  """
  @spec list_filter_specs() :: [map()]
  def list_filter_specs do
    Map.values(@filter_specs)
  end

  @doc """
  Check if a filter exists.

  ## Examples

      iex> filter_exists?("upper_case")
      true

      iex> filter_exists?("unknown_filter")
      false
  """
  @spec filter_exists?(String.t()) :: boolean()
  def filter_exists?(name) when is_binary(name) do
    Map.has_key?(@filters, name)
  end

  @doc """
  Get detailed information about a specific filter.

  ## Examples

      iex> get_filter_info("upper_case")
      %{name: "upper_case", function: &StringFilters.upper_case/2, description: "Convert string to uppercase", module: "string_filters"}
  """
  @spec get_filter_info(String.t()) :: map() | nil
  def get_filter_info(filter_name) when is_binary(filter_name) do
    Enum.find_value(@filter_specs, fn {_module_name, spec} ->
      Enum.find(spec.filters, fn filter ->
        if filter.name == filter_name do
          Map.put(filter, :module, spec.name)
        end
      end)
    end)
  end

  @doc """
  Get compile-time statistics about loaded filters.

  ## Examples

      iex> get_stats()
      %{
        total_filters: 11,
        total_modules: 3,
        modules: ["string_filters", "number_filters", "collection_filters"]
      }
  """
  @spec get_stats() :: map()
  def get_stats do
    %{
      total_filters: map_size(@filters),
      total_modules: length(@filter_modules),
      modules: Map.keys(@filter_specs)
    }
  end
end
