defmodule Prana.Integrations.Data.SetDataAction do
  @moduledoc """
  Set Data Action - Creates or transforms data using templates

  Supports two operating modes:
  - `manual`: Simple key-value mapping (params already template-rendered by NodeExecutor)
  - `json`: Complex nested data structures from JSON templates (template-rendered string parsed as JSON)
  """

  use Prana.Actions.SimpleAction

  alias Prana.Action

  def definition do
    %Action{
      name: "data.set_data",
      display_name: "Set Data",
      description: "Create or transform data using templates in manual or json mode",
      type: :action,
      input_ports: ["main"],
      output_ports: ["main", "error"]
    }
  end

  @impl true
  def execute(params, _context) do
    mode = Map.get(params, "mode", "manual")

    case mode do
      "manual" ->
        execute_manual_mode(params)

      "json" ->
        execute_json_mode(params)

      invalid_mode ->
        {:error, "Invalid mode '#{invalid_mode}'. Supported modes: 'manual', 'json'"}
    end
  end

  defp execute_manual_mode(params) do
    case Map.get(params, "mapping_map") do
      nil ->
        {:ok, nil}

      mapping_map when is_map(mapping_map) ->
        {:ok, mapping_map}

      _ ->
        {:error, "Parameter 'mapping_map' must be a map"}
    end
  end

  defp execute_json_mode(params) do
    case Map.get(params, "json_template") do
      nil ->
        {:ok, nil}

      json_template when is_binary(json_template) ->
        case Jason.decode(json_template) do
          {:ok, parsed_data} ->
            {:ok, parsed_data}

          {:error, %Jason.DecodeError{} = error} ->
            {:error, "JSON parsing failed: #{Exception.message(error)}"}
        end

      _ ->
        {:error, "Parameter 'json_template' must be a string"}
    end
  end
end
