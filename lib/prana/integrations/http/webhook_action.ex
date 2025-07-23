defmodule Prana.Integrations.HTTP.WebhookAction do
  @moduledoc """
  Webhook action implementation using Action behavior with suspend/resume pattern

  Suspends execution and waits for incoming HTTP webhook requests.
  """

  @behaviour Prana.Behaviour.Action

  use Skema

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

  @impl true
  def prepare(node) do
    # Webhook preparation could include URL generation
    config = Map.get(node, :config, %{})

    preparation_data = %{
      webhook_path: Map.get(config, "webhook_path", "/webhook"),
      prepared_at: DateTime.utc_now()
    }

    {:ok, preparation_data}
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
  def execute(params, _context) do
    # Build webhook URL using base_url from environment variable only
    webhook_url =
      case System.get_env("PRANA_BASE_URL") do
        nil ->
          nil

        base_url ->
          webhook_path = Map.get(params, "path", "/webhook")
          "#{base_url}#{webhook_path}"
      end

    # Extract configuration and return webhook setup
    result = %{
      webhook_path: Map.get(params, "path", "/webhook"),
      allowed_methods: Map.get(params, "methods", ["POST"]),
      auth_config: Map.get(params, "auth", %{"type" => "none"}),
      response_type: Map.get(params, "response_type", "immediately"),
      webhook_url: webhook_url,
      configured_at: DateTime.utc_now()
    }

    {:ok, result, "success"}
  end

  @impl true
  def resume(_params, _context, _resume_data) do
    {:error, "Webhook action does not support resume"}
  end

  @impl true
  def suspendable?, do: false

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
