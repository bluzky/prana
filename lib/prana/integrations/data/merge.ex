defmodule Prana.Integrations.Data.MergeAction do
  @moduledoc """
  Merge action - combine data from multiple named input ports (ADR-002)
  """

  use Prana.Actions.SimpleAction

  alias Prana.Action
  alias Prana.Core.Error

  def definition do
    %Action{
      name: "data.merge",
      display_name: "Merge Data",
      description: "Combine data from multiple named input ports (diamond pattern coordination)",
      type: :action,
      input_ports: ["input_a", "input_b"],
      output_ports: ["main", "error"]
    }
  end

  @impl true
  def execute(params, _context) do
    strategy = Map.get(params, "strategy", "append")

    # Extract inputs from named ports
    inputs = extract_inputs_from_map(params)

    case merge_data_with_strategy(inputs, strategy) do
      {:ok, merged_data} ->
        {:ok, merged_data}

      {:error, reason} ->
        {:error, Error.action_error("merge_error", reason)}
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

    Enum.reject([input_a, input_b], &is_nil/1)
  end

  # Merge data using ADR-002 strategies
  defp merge_data_with_strategy(inputs, strategy) do
    case strategy do
      "append" ->
        # Collect all inputs as separate array elements
        {:ok, inputs}

      "merge" ->
        # Combine object inputs using Map.merge/2, ignore non-maps
        merged =
          inputs
          |> Enum.filter(&is_map/1)
          |> Enum.reduce(%{}, &Map.merge(&2, &1))

        {:ok, merged}

      "concat" ->
        # Flatten and concatenate array inputs, ignore non-arrays
        concatenated =
          inputs
          |> Enum.filter(&is_list/1)
          |> List.flatten()

        {:ok, concatenated}

      _ ->
        {:error, "Unknown merge strategy: #{strategy}. Supported: append, merge, concat"}
    end
  end
end
