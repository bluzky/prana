defmodule Prana.Action do
  @moduledoc """
  Represents an action definition within an integration.
  Defines the action's metadata, execution details, and schema.

  ## Example

      %Prana.Action{
        name: "http_request",
        display_name: "HTTP Request",
        description: "Make HTTP requests (GET, POST, PUT, DELETE, etc.)",
        module: MyApp.HttpRequestAction,
        input_ports: ["input"],
        output_ports: ["main", "error", "timeout"],

        params_schema: %{
          type: "object",
          required: ["url"],
          properties: %{
            url: %{type: "string", description: "Request URL"},
            method: %{type: "string", enum: ["GET", "POST", "PUT", "DELETE"], default: "GET"},
            headers: %{type: "object", description: "Request headers"},
            body: %{type: "string", description: "Request body"},
            timeout: %{type: "integer", description: "Timeout in milliseconds", default: 30000}
          }
        },
        metadata: %{
          category: "network",
          tags: ["http", "api", "request"]
        }
      }

  """

  @type action_type :: :trigger | :action | :logic | :wait | :output
  @type t :: %__MODULE__{
          name: String.t(),
          display_name: String.t(),
          description: String.t(),
          type: action_type(),
          module: atom(),
          input_ports: [String.t()],
          output_ports: [String.t()],
          params_schema: map() | nil,
          metadata: map()
        }

  defstruct [
    :name,
    :display_name,
    :description,
    :type,
    :module,
    :input_ports,
    :output_ports,
    :params_schema,
    metadata: %{}
  ]
end
