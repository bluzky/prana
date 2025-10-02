defmodule Prana.Integrations.HTTP.WebhookRespondAction do
  @moduledoc """
  Webhook Respond action implementation using Action behavior with suspend pattern

  Sends custom HTTP responses back to webhook callers. Suspends execution to allow the application
  to handle the actual HTTP response. Used with webhook triggers that have response_type set to "at_return_node".

  ## Parameters
  - `respond_with` (required): Response type - "text", "json", "redirect", or "no_data" (default: "text")
  - `status_code` (optional): HTTP status code (default: 200)
  - `headers` (optional): Additional HTTP headers map (default: {})
  - `text_data` (required for text): Plain text response content
  - `json_data` (required for json): JSON object to return
  - `redirect_url` (required for redirect): URL to redirect to
  - `redirect_type` (optional): "temporary" or "permanent" (default: "temporary")

  ## Example Params JSON

  ### Text Response
  ```json
  {
    "respond_with": "text",
    "status_code": 200,
    "text_data": "Webhook received successfully",
    "headers": {
      "X-Custom-Header": "value"
    }
  }
  ```

  ### JSON Response
  ```json
  {
    "respond_with": "json",
    "status_code": 201,
    "json_data": {
      "success": true,
      "message": "Data processed",
      "id": "{{$input.user_id}}"
    }
  }
  ```

  ### Redirect Response
  ```json
  {
    "respond_with": "redirect",
    "status_code": 302,
    "redirect_url": "https://example.com/success",
    "redirect_type": "temporary"
  }
  ```

  ## Output Ports
  - `main`: Response sent successfully
  - `error`: Response configuration or sending errors

  ## Behavior
  This action suspends workflow execution to allow the application to send the HTTP response,
  then resumes with success confirmation.
  """

  use Prana.Actions.SimpleAction
  use Skema

  alias Prana.Action

  def definition do
    %Action{
      name: "http.webhook_respond",
      display_name: "Webhook Respond",
      description: @moduledoc,
      type: :action,
      input_ports: ["main"],
      output_ports: ["main"]
    }
  end

  defschema WebhookRespondSchema do
    field(:respond_with, :string,
      required: true,
      default: "text",
      in: ["text", "json", "redirect", "no_data"]
    )

    field(:status_code, :integer, default: 200)
    field(:headers, :map, default: %{})

    # Conditional fields based on respond_with type (made optional, validated separately)
    field(:text_data, :string, required: false)
    field(:json_data, :map, required: false)
    field(:redirect_url, :string, required: false)
    field(:redirect_type, :string, default: "temporary", in: ["temporary", "permanent"])
  end

  @impl true
  def execute(params, context) do
    # Build response configuration
    response_config = build_respond_config(params)

    # Create suspension data for application to handle HTTP response
    suspension_data = %{
      "type" => :webhook_response,
      "execution_id" => Map.get(context, :execution_id),
      "node_id" => Map.get(context, :node_id),
      "response_config" => response_config,
      "suspended_at" => DateTime.utc_now()
    }

    {:suspend, :webhook_response, suspension_data}
  end

  @impl true
  def resume(_params, _context, _resume_data) do
    # Simple resume - webhook response already sent by application
    {:ok, nil, "main"}
  end

  @impl true
  def suspendable?, do: true

  # Build response configuration based on respond_with type
  defp build_respond_config(params) do
    respond_with = Map.get(params, "respond_with")
    custom_headers = Map.get(params, "headers", %{})

    base_config = %{
      respond_with: respond_with,
      status_code: Map.get(params, "status_code"),
      headers: custom_headers
    }

    case respond_with do
      "text" ->
        Map.put(base_config, :text, params["text_data"])

      "json" ->
        base_config
        |> Map.put(:json_data, Map.get(params, "json_data"))
        |> Map.put(:headers, Map.put(base_config.headers, "Content-Type", "application/json"))

      "redirect" ->
        redirect_url = Map.get(params, "redirect_url")

        base_config
        |> Map.merge(%{
          redirect_url: redirect_url,
          redirect_type: Map.get(params, "redirect_type", "temporary")
        })
        |> Map.put(:headers, Map.put(base_config.headers, "Location", redirect_url))

      "no_data" ->
        base_config

      _ ->
        base_config
    end
  end

end
