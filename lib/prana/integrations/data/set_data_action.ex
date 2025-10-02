defmodule Prana.Integrations.Data.SetDataAction do
  @moduledoc """
  Set Data Action - Creates or transforms data using templates

  Creates or transforms data using two operating modes: manual key-value mapping or JSON template parsing.
  Used for data transformation, object creation, and complex data manipulation in workflows.

  ## Parameters
  - `mode` (optional): Operating mode - "manual" or "json" (default: "manual")
  - `mapping_map` (for manual mode): Key-value map of data to output
  - `json_template` (for json mode): JSON string template to parse

  ### Manual Mode
  Simple key-value mapping where parameters are already template-rendered by NodeExecutor.

  ### JSON Mode
  Complex nested data structures created from JSON template strings that get parsed.

  ## Example Params JSON

  ### Manual Mode
  ```json
  {
    "mode": "manual",
    "mapping_map": {
      "user_id": "{{$input.id}}",
      "full_name": "{{$input.first_name}} {{$input.last_name}}",
      "processed_at": "{{$execution.timestamp}}",
      "status": "active"
    }
  }
  ```

  ### JSON Mode
  ```json
  {
    "mode": "json",
    "json_template": "{\"user\": {\"id\": \"{{$input.user_id}}\", \"profile\": {\"name\": \"{{$input.name}}\", \"email\": \"{{$input.email}}\"}}, \"metadata\": {\"created_at\": \"{{$execution.timestamp}}\", \"workflow_id\": \"{{$workflow.id}}\"}}"
  }
  ```

  ## Output Ports
  - `main`: Successfully created/transformed data
  - `error`: Data creation or JSON parsing errors

  ## Output Format
  Returns the created data object based on the specified mode and templates.
  """

  use Prana.Actions.SimpleAction

  alias Prana.Action

  def definition do
    %Action{
      name: "data.set_data",
      display_name: "Set Data",
      description: @moduledoc,
      type: :action,
      input_ports: ["main"],
      output_ports: ["main"]
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
