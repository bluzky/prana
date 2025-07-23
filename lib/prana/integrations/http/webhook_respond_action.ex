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

  def specification do
    %Action{
      name: "http.webhook_respond",
      display_name: "Webhook Respond",
      description: "Send custom response back to webhook caller",
      type: :action,
      module: __MODULE__,
      input_ports: ["input"],
      output_ports: ["success", "error"]
    }
  end

  defschema TextResponseSchema do
    field(:text, :string, required: true)
    field(:content_type, :string, default: "text/plain")
  end

  defschema JsonResponseSchema do
    field(:json_data, :map, required: true)
  end

  defschema RedirectResponseSchema do
    field(:redirect_url, :string, required: true)
    field(:redirect_type, :string, default: "temporary", in: ["temporary", "permanent"])
  end

  defschema WebhookRespondSchema do
    field(:respond_with, :string,
      required: true,
      in: ["text", "json", "redirect", "no_data"]
    )

    field(:status_code, :integer, default: 200)
    field(:headers, :map, default: %{})

    # Conditional fields based on respond_with type
    field(:text_response, TextResponseSchema)
    field(:json_response, JsonResponseSchema)
    field(:redirect_response, RedirectResponseSchema)
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
    respond_config = build_respond_config(params)

    # Create suspension data for application to handle HTTP response
    suspension_data = %{
      type: :webhook_response,
      execution_id: Map.get(context, :execution_id),
      node_id: Map.get(context, :node_id),
      respond_config: respond_config,
      suspended_at: DateTime.utc_now()
    }

    {:suspend, :webhook_response, suspension_data}
  end

  @impl true
  def resume(_params, _context, _resume_data) do
    # Simple resume - webhook response already sent by application
    {:ok, nil, "success"}
  end

  @impl true
  def suspendable?, do: true

  # Build response configuration based on respond_with type
  defp build_respond_config(params) do
    respond_with = Map.get(params, "respond_with")
    custom_headers = Map.get(params, "headers", %{})

    base_config = %{
      respond_with: respond_with,
      status_code: Map.get(params, "status_code", 200),
      headers: custom_headers
    }

    case respond_with do
      "text" ->
        text_response = Map.get(params, "text_response", %{})
        content_type = Map.get(text_response, "content_type", "text/plain")

        base_config
        |> Map.merge(%{
          text: Map.get(text_response, "text"),
          content_type: content_type
        })
        |> Map.put(:headers, Map.put(base_config.headers, "Content-Type", content_type))

      "json" ->
        json_response = Map.get(params, "json_response", %{})

        base_config
        |> Map.merge(%{
          json_data: Map.get(json_response, "json_data")
        })
        |> Map.put(:headers, Map.put(base_config.headers, "Content-Type", "application/json"))

      "redirect" ->
        redirect_response = Map.get(params, "redirect_response", %{})
        redirect_url = Map.get(redirect_response, "redirect_url")

        base_config
        |> Map.merge(%{
          redirect_url: redirect_url,
          redirect_type: Map.get(redirect_response, "redirect_type", "temporary")
        })
        |> Map.put(:headers, Map.put(base_config.headers, "Location", redirect_url))

      "no_data" ->
        base_config

      _ ->
        base_config
    end
  end


    # Validate that required fields are present for each response type
  defp validate_response_fields(%{respond_with: "text", text_response: text_response})
       when not is_nil(text_response) do
    :ok
  end

  defp validate_response_fields(%{respond_with: "text"}) do
    {:error, "text_response is required when respond_with is 'text'"}
  end

  defp validate_response_fields(%{respond_with: "json", json_response: json_response})
       when not is_nil(json_response) do
    :ok
  end

  defp validate_response_fields(%{respond_with: "json"}) do
    {:error, "json_response is required when respond_with is 'json'"}
  end

  defp validate_response_fields(%{respond_with: "redirect", redirect_response: redirect_response})
       when not is_nil(redirect_response) do
    :ok
  end

  defp validate_response_fields(%{respond_with: "redirect"}) do
    {:error, "redirect_response is required when respond_with is 'redirect'"}
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
