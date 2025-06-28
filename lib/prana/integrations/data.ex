defmodule Prana.Integrations.Data do
  @moduledoc """
  Data Integration - Provides data manipulation and combination operations
  
  Supports:
  - Merge operations for combining data from multiple paths
  - Future: Transform, filter, and other data manipulation operations
  """

  @behaviour Prana.Behaviour.Integration

  alias Prana.Action
  alias Prana.Integration

  @doc """
  Returns the integration definition with all available actions
  """
  @impl true
  def definition do
    %Integration{
      name: "data",
      display_name: "Data",
      description: "Data manipulation operations for workflow data processing",
      version: "1.0.0",
      category: "core",
      actions: %{
        "merge" => %Action{
          name: "merge",
          display_name: "Merge Data",
          description: "Combine data from multiple input sources",
          module: __MODULE__,
          function: :merge,
          input_ports: ["input"],
          output_ports: ["success", "error"],
          default_success_port: "success",
          default_error_port: "error"
        }
      }
    }
  end

  @doc """
  Merge action - combine data from multiple sources
  
  Expected input_map:
  - strategy: "combine_objects" | "combine_arrays" | "last_wins"
  - inputs: list of data to merge
  
  Returns:
  - {:ok, merged_data, "success"}
  - {:error, reason, "error"} if merge fails
  """
  def merge(input_map) do
    strategy = Map.get(input_map, "strategy", "combine_objects")
    inputs = Map.get(input_map, "inputs", [])
    
    case merge_data(inputs, strategy) do
      {:ok, merged_data} ->
        {:ok, merged_data, "success"}
        
      {:error, reason} ->
        {:error, %{type: "merge_error", message: reason}, "error"}
    end
  end

  # ============================================================================
  # Private Helper Functions
  # ============================================================================

  # Merge data using different strategies
  defp merge_data(inputs, strategy) do
    case strategy do
      "combine_objects" ->
        merged = Enum.reduce(inputs, %{}, fn input, acc ->
          if is_map(input), do: Map.merge(acc, input), else: acc
        end)
        {:ok, merged}
        
      "combine_arrays" ->
        arrays = Enum.filter(inputs, &is_list/1)
        merged = List.flatten(arrays)
        {:ok, merged}
        
      "last_wins" ->
        case List.last(inputs) do
          nil -> {:ok, %{}}
          last -> {:ok, last}
        end
        
      _ ->
        {:error, "Unknown merge strategy: #{strategy}"}
    end
  end
end