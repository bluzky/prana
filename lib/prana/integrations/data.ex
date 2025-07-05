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
          module: Prana.Integrations.Data.MergeAction,
          input_ports: ["input_a", "input_b"],
          output_ports: ["success", "error"],
          default_success_port: "success",
          default_error_port: "error"
        }
      }
    }
  end

end

defmodule Prana.Integrations.Data.MergeAction do
  @moduledoc """
  Merge action - combine data from multiple named input ports (ADR-002)
  """
  
  use Prana.Actions.SimpleAction

  @impl true
  def execute(params) do
    strategy = Map.get(params, "strategy", "append")
    
    # Extract inputs from named ports
    inputs = extract_inputs_from_map(params)
    
    case merge_data_with_strategy(inputs, strategy) do
      {:ok, merged_data} ->
        {:ok, merged_data}
        
      {:error, reason} ->
        {:error, %{type: "merge_error", message: reason}}
    end
  end

  # ============================================================================
  # Private Helper Functions
  # ============================================================================

  # Extract inputs from named ports (ADR-002 format)
  defp extract_inputs_from_map(params) do
    # Collect named port inputs, excluding nil values
    input_a = Map.get(params, "input_a")
    input_b = Map.get(params, "input_b")
    
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