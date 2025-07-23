defmodule Prana.Integrations.HTTP.WebhookAction do
  @moduledoc """
  Webhook action implementation using Action behavior with suspend/resume pattern

  Suspends execution and waits for incoming HTTP webhook requests.
  """

  @behaviour Prana.Behaviour.Action

  use Skema
  use Prana.Actions.SimpleAction

  alias Prana.Action

  def specification do
    %Action{
      name: "http.webhook_trigger",
      display_name: "Webhook Trigger",
      description: "Configure webhook endpoint for triggering workflow execution",
      type: :trigger,
      module: __MODULE__,
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
  def params_schema, do: WebhookConfigSchema

  @impl true
  def validate_params(input_map) do
    case Skema.cast_and_validate(input_map, WebhookConfigSchema) do
      {:ok, validated_data} ->
        case validate_methods(validated_data.methods) do
          :ok -> {:ok, validated_data}
          {:error, reason} -> {:error, [reason]}
        end

      {:error, errors} ->
        {:error, format_errors(errors)}
    end
  end

  # Validate HTTP methods
  defp validate_methods(methods) when is_list(methods) do
    valid_methods = ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"]

    invalid_methods = methods -- valid_methods

    if Enum.empty?(invalid_methods) do
      :ok
    else
      {:error,
       "Invalid HTTP methods: #{Enum.join(invalid_methods, ", ")}. Valid methods: #{Enum.join(valid_methods, ", ")}"}
    end
  end

  defp validate_methods(_methods) do
    {:error, "Methods must be a list of strings"}
  end

  # Public helper to get webhook configuration for external use
  # def get_webhook_config(suspension_data) do
  #   %{
  #     path: Map.get(suspension_data, :webhook_path, "/webhook"),
  #     methods: Map.get(suspension_data, :allowed_methods, ["POST"]),
  #     auth: Map.get(suspension_data, :auth_config, %{"type" => "none"}),
  #     response_type: Map.get(suspension_data, :response_type, "immediately"),
  #     webhook_url: Map.get(suspension_data, :webhook_url)
  #   }
  # end

  @impl true
  def execute(_params, context) do
    request_params = context["$input"]["main"]
    {:ok, request_params, "main"}
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
