defmodule Prana.Integrations.HTTP.WebhookAction do
  @moduledoc """
  Webhook Trigger action implementation using Action behavior with suspend/resume pattern

  Creates a webhook endpoint that can trigger workflow execution when HTTP requests are received.
  The action configures webhook settings and passes through the incoming request data.

  ## Parameters
  - `path` (optional): Webhook endpoint path (default: "/webhook")
  - `methods` (optional): Allowed HTTP methods array (default: ["POST"])
  - `auth` (optional): Authentication configuration object (default: none)
  - `response_type` (optional): When to respond - "immediately", "on_completion", "at_return_node" (default: "immediately")
  - `secret` (optional): Webhook secret for validation
  - `headers` (optional): Expected headers map (default: {})

  ### Authentication Object
  - `type` (required): "none", "basic", "header", or "jwt"
  - For basic auth: `username` and `password`
  - For header auth: `header_name` (default: "Authorization") and `header_value`
  - For JWT auth: `jwt_secret`

  ## Example Params JSON
  ```json
  {
    "path": "/api/webhooks/github",
    "methods": ["POST", "PUT"],
    "auth": {
      "type": "header",
      "header_name": "X-GitHub-Token",
      "header_value": "{{$execution.state.github_secret}}"
    },
    "response_type": "immediately",
    "secret": "my-webhook-secret"
  }
  ```

  ## Output Ports
  - `main`: Webhook request data including headers, body, and metadata

  ## Output Format
  The webhook passes through the incoming HTTP request data:
  ```json
  {
    "headers": {"content-type": "application/json"},
    "body": "request body",
    "method": "POST",
    "path": "/webhook",
    "query": {"param": "value"}
  }
  ```
  """

  use Skema
  use Prana.Actions.SimpleAction

  alias Prana.Action

  def definition do
    %Action{
      name: "http.webhook_trigger",
      display_name: "Webhook Trigger",
      description: @moduledoc,
      type: :trigger,
      input_ports: [],
      output_ports: ["main"]
    }
  end

  defschema AuthConfigSchema do
    field(:type, :string,
      required: true,
      in: ["none", "basic", "header", "jwt"]
    )

    # For basic auth
    field(:username, :string)
    field(:password, :string)
    # For header auth
    field(:header_name, :string, default: "Authorization")
    field(:header_value, :string)
    # For JWT auth
    field(:jwt_secret, :string)
  end

  defschema WebhookConfigSchema do
    field(:path, :string, default: "/webhook")
    field(:methods, {:array, :string}, default: ["POST"])
    field(:auth, AuthConfigSchema, default: %{type: "none"})

    field(:response_type, :string,
      default: "immediately",
      in: ["immediately", "on_completion", "at_return_node"]
    )

    field(:secret, :string)
    field(:headers, :map, default: %{})
  end

  @impl true
  def execute(_params, context) do
    request_params = context["$input"]["main"]
    {:ok, request_params, "main"}
  end
end
