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
        output_ports: ["success", "error", "timeout"],
        default_success_port: "success",
        default_error_port: "error",
        input_schema: %{
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
        output_schema: %{
          type: "object",
          properties: %{
            status_code: %{type: "integer"},
            headers: %{type: "object"},
            body: %{type: "string"},
            duration_ms: %{type: "integer"}
          }
        },
        examples: [
          %{
            name: "GET Request",
            input: %{url: "https://api.example.com/users", method: "GET"},
            description: "Fetch data from API"
          },
          %{
            name: "POST Request",
            input: %{
              url: "https://api.example.com/users",
              method: "POST",
              headers: %{"Content-Type" => "application/json"},
              body: ~s({"name": "John", "email": "john@example.com"})
            },
            description: "Create new user"
          }
        ],
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
          default_success_port: String.t(),
          default_error_port: String.t(),
          input_schema: map() | nil,
          output_schema: map() | nil,
          examples: [map()],
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
    :default_success_port,
    :default_error_port,
    :input_schema,
    :output_schema,
    examples: [],
    metadata: %{}
  ]
end
