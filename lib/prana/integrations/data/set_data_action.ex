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
  alias Prana.Core.Error

  def definition do
    %Action{
      name: "data.set_data",
      display_name: "Set Data",
      description: @moduledoc,
      type: :action,
      input_ports: ["main"],
      output_ports: ["main"],
      params_schema: %{
        mode: [
          type: :string,
          description: "Operating mode - 'manual' (key-value map) or 'json' (JSON template string)",
          default: "manual",
          in: ["manual", "json"]
        ],
        mapping_map: [
          type: :map,
          description: "Key-value map of data to output (for manual mode)"
        ],
        json_template: [
          type: :string,
          description: "JSON string template to parse (for json mode)"
        ]
      }
    }
  end

  @impl true
  def execute(params, _context) do
    case params.mode do
      "manual" ->
        {:ok, params.mapping_map}

      "json" ->
        case Jason.decode(params.json_template) do
          {:ok, parsed_data} ->
            {:ok, parsed_data}

          {:error, %Jason.DecodeError{} = error} ->
            {:error, Error.new("json_error", "JSON parsing failed: #{Exception.message(error)}")}
        end
    end
  end
end
