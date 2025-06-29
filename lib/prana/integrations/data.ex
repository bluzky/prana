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
          description: "Combine data from multiple named input ports (diamond pattern coordination)",
          module: __MODULE__,
          function: :merge,
          input_ports: ["input_a", "input_b"],
          output_ports: ["success", "error"],
          default_success_port: "success",
          default_error_port: "error"
        }
      }
    }
  end

  @doc """
  Merge action - combine data from multiple named input ports (ADR-002)
  
  Expected input_map:
  - strategy: "append" | "merge" | "concat" (optional, defaults to "append")
  - input_a: data from first input port
  - input_b: data from second input port
  
  Strategies:
  - append: Collect all inputs as array elements [input_a, input_b]
  - merge: Combine object inputs using Map.merge/2, ignores non-maps
  - concat: Flatten and concatenate array inputs using List.flatten/1, ignores non-arrays
  
  
  Returns:
  - {:ok, merged_data, "success"}
  - {:error, reason, "error"} if merge fails
  """
  def merge(input_map) do
    strategy = Map.get(input_map, "strategy", "append")
    
    # Extract inputs from named ports or legacy inputs list
    inputs = extract_inputs_from_map(input_map)
    
    case merge_data_with_strategy(inputs, strategy) do
      {:ok, merged_data} ->
        {:ok, merged_data, "success"}
        
      {:error, reason} ->
        {:error, %{type: "merge_error", message: reason}, "error"}
    end
  end

  # ============================================================================
  # Private Helper Functions
  # ============================================================================

  # Extract inputs from named ports (ADR-002 format)
  defp extract_inputs_from_map(input_map) do
    # Collect named port inputs, excluding nil values
    input_a = Map.get(input_map, "input_a")
    input_b = Map.get(input_map, "input_b")
    
    [input_a, input_b] |> Enum.reject(&is_nil/1)
  end

  # Merge data using ADR-002 strategies
  defp merge_data_with_strategy(inputs, strategy) do
    case strategy do
      "append" ->
        # Collect all inputs as separate array elements
        {:ok, inputs}
        
      "merge" ->
        # Combine object inputs using Map.merge/2, ignore non-maps
        merged = inputs
                 |> Enum.filter(&is_map/1)
                 |> Enum.reduce(%{}, &Map.merge(&2, &1))
        {:ok, merged}
        
      "concat" ->
        # Flatten and concatenate array inputs, ignore non-arrays
        concatenated = inputs
                      |> Enum.filter(&is_list/1)
                      |> List.flatten()
        {:ok, concatenated}
        
      
      _ ->
        {:error, "Unknown merge strategy: #{strategy}. Supported: append, merge, concat"}
    end
  end
end