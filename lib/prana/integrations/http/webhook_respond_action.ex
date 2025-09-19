defmodule Prana.Integrations.HTTP.WebhookRespondAction do
  @moduledoc """
  Webhook respond action implementation using Action behavior with suspend pattern

  Suspends execution and returns response configuration for application to handle
  HTTP response back to webhook caller. Used with webhook triggers that have
  response_type set to "at_return_node".
  """

  use Prana.Actions.SimpleAction
  use Skema

  alias Prana.Action

  def definition do
    %Action{
      name: "http.webhook_respond",
      display_name: "Webhook Respond",
      description: "Send custom response back to webhook caller",
      type: :action,
      input_ports: ["main"],
      output_ports: ["main", "error"]
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
  def params_schema, do: WebhookRespondSchema

  @impl true
  def validate_params(input_map) do
    case Skema.cast_and_validate(input_map, WebhookRespondSchema) do
      {:ok, validated_data} ->
        case validate_response_fields(validated_data) do
          :ok -> {:ok, validated_data}
          {:error, reason} -> {:error, [reason]}
        end

      {:error, errors} ->
        {:error, format_errors(errors)}
    end
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

  # Validate that required fields are present for each response type
  defp validate_response_fields(%{respond_with: "text", text_data: text_data}) when not is_nil(text_data) do
    :ok
  end

  defp validate_response_fields(%{respond_with: "text"}) do
    {:error, "text_data is required when respond_with is 'text'"}
  end

  defp validate_response_fields(%{respond_with: "json", json_data: json_data}) when not is_nil(json_data) do
    :ok
  end

  defp validate_response_fields(%{respond_with: "json"}) do
    {:error, "json_data is required when respond_with is 'json'"}
  end

  defp validate_response_fields(%{respond_with: "redirect", redirect_url: redirect_url}) when not is_nil(redirect_url) do
    :ok
  end

  defp validate_response_fields(%{respond_with: "redirect"}) do
    {:error, "redirect_url is required when respond_with is 'redirect'"}
  end

  defp validate_response_fields(%{respond_with: "no_data"}) do
    :ok
  end

  defp validate_response_fields(%{respond_with: respond_with}) do
    {:error, "Invalid respond_with value: #{respond_with}"}
  end

  # Format validation errors
  defp format_errors(errors) do
    Enum.map(errors, fn
      {field, messages} when is_list(messages) ->
        "#{field}: #{Enum.join(messages, ", ")}"

      {field, message} when is_binary(message) ->
        "#{field}: #{message}"

      {field, message} ->
        "#{field}: #{inspect(message)}"
    end)
  end
end
