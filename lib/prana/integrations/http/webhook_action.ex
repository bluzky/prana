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
      name: "webhook",
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
      in: ["immediately", "end_of_flow"]
    )

    field(:secret, :string)
    field(:headers, :map, default: %{})
  end

  defschema WebhookSchema do
    field(:webhook_config, WebhookConfigSchema, default: %{})
  end

  @impl true
  def params_schema, do: WebhookSchema

  @impl true
  def validate_params(input_map) do
    case Skema.cast_and_validate(input_map, WebhookSchema) do
      {:ok, validated_data} ->
        case validate_methods(validated_data.webhook_config.methods) do
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
    webhook_config = Map.get(params, "webhook_config", %{})

    # Build webhook URL using base_url from environment variable only
    webhook_url =
      case System.get_env("PRANA_BASE_URL") do
        nil ->
          nil

        base_url ->
          webhook_path = Map.get(webhook_config, "path", "/webhook")
          "#{base_url}#{webhook_path}"
      end

    # Extract configuration and return webhook setup
    result = %{
      webhook_path: Map.get(webhook_config, "path", "/webhook"),
      allowed_methods: Map.get(webhook_config, "methods", ["POST"]),
      auth_config: Map.get(webhook_config, "auth", %{"type" => "none"}),
      response_type: Map.get(webhook_config, "response_type", "immediately"),
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

  # Validate incoming webhook request (used by application layer)
  def validate_webhook_request(webhook_config, request_data) do
    method = Map.get(request_data, :method) || Map.get(request_data, "method")
    headers = Map.get(request_data, :headers, %{}) || Map.get(request_data, "headers", %{})
    body = Map.get(request_data, :body) || Map.get(request_data, "body")

    # Get configuration from webhook_config
    allowed_methods = Map.get(webhook_config, :allowed_methods, ["POST"])
    auth_config = Map.get(webhook_config, :auth_config, %{"type" => "none"})

    with :ok <- validate_method(allowed_methods, method),
         :ok <- validate_authentication(auth_config, headers, body) do
      {:ok, %{method: method, headers: headers, body: body}}
    end
  end

  # Validate HTTP method
  defp validate_method(allowed_methods, method) when is_binary(method) do
    method_upper = String.upcase(method)
    allowed_methods_upper = Enum.map(allowed_methods, &String.upcase/1)

    if method_upper in allowed_methods_upper do
      :ok
    else
      {:error, "Method #{method} not allowed. Allowed methods: #{Enum.join(allowed_methods, ", ")}"}
    end
  end

  defp validate_method(_allowed_methods, nil) do
    {:error, "HTTP method is required"}
  end

  # Validate authentication
  defp validate_authentication(%{"type" => "none"}, _headers, _body), do: :ok
  defp validate_authentication(%{type: "none"}, _headers, _body), do: :ok

  defp validate_authentication(%{"type" => "basic", "username" => username, "password" => password}, headers, _body)
       when is_binary(username) and is_binary(password) do
    validate_basic_auth(headers, username, password)
  end

  defp validate_authentication(%{type: "basic", username: username, password: password}, headers, _body)
       when is_binary(username) and is_binary(password) do
    validate_basic_auth(headers, username, password)
  end

  defp validate_authentication(
         %{"type" => "header", "header_name" => header_name, "header_value" => expected_value},
         headers,
         _body
       )
       when is_binary(header_name) and is_binary(expected_value) do
    validate_header_auth(headers, header_name, expected_value)
  end

  defp validate_authentication(%{type: "header", header_name: header_name, header_value: expected_value}, headers, _body)
       when is_binary(header_name) and is_binary(expected_value) do
    validate_header_auth(headers, header_name, expected_value)
  end

  defp validate_authentication(%{"type" => "jwt", "jwt_secret" => secret}, headers, _body) when is_binary(secret) do
    validate_jwt_auth(headers, secret)
  end

  defp validate_authentication(%{type: "jwt", jwt_secret: secret}, headers, _body) when is_binary(secret) do
    validate_jwt_auth(headers, secret)
  end

  defp validate_authentication(auth_config, _headers, _body) do
    {:error, "Invalid authentication configuration: #{inspect(auth_config)}"}
  end

  # Helper functions for authentication validation
  defp validate_basic_auth(headers, username, password) do
    auth_header = Map.get(headers, "authorization") || Map.get(headers, "Authorization")

    case auth_header do
      "Basic " <> encoded ->
        case Base.decode64(encoded) do
          {:ok, decoded} ->
            case String.split(decoded, ":", parts: 2) do
              [^username, ^password] -> :ok
              _ -> {:error, "Invalid basic authentication credentials"}
            end

          :error ->
            {:error, "Invalid base64 encoding in Authorization header"}
        end

      _ ->
        {:error, "Missing or invalid Authorization header for basic auth"}
    end
  end

  defp validate_header_auth(headers, header_name, expected_value) do
    actual_value = Map.get(headers, header_name) || Map.get(headers, String.downcase(header_name))

    if actual_value == expected_value do
      :ok
    else
      {:error, "Invalid or missing header authentication"}
    end
  end

  defp validate_jwt_auth(headers, secret) do
    auth_header = Map.get(headers, "authorization") || Map.get(headers, "Authorization")

    case auth_header do
      "Bearer " <> token ->
        validate_jwt_token(token, secret)

      _ ->
        {:error, "Missing or invalid Authorization header for JWT auth"}
    end
  end

  # Basic JWT validation (in production, use a proper JWT library)
  defp validate_jwt_token(token, secret) do
    case String.split(token, ".", parts: 3) do
      [header_b64, payload_b64, signature] ->
        # Decode header to get algorithm
        case Base.url_decode64(header_b64, padding: false) do
          {:ok, header_json} ->
            case Jason.decode(header_json) do
              {:ok, %{"alg" => algorithm}} ->
                # Basic signature verification
                expected_signature = generate_jwt_signature("#{header_b64}.#{payload_b64}", secret, algorithm)

                if signature == expected_signature do
                  :ok
                else
                  {:error, "Invalid JWT signature"}
                end

              _ ->
                {:error, "Invalid JWT header format"}
            end

          _ ->
            {:error, "Invalid JWT header encoding"}
        end

      _ ->
        {:error, "Invalid JWT format"}
    end
  end

  # Generate JWT signature (simplified - use proper JWT library in production)
  defp generate_jwt_signature(data, secret, "HS256") do
    :hmac
    |> :crypto.mac(:sha256, secret, data)
    |> Base.url_encode64(padding: false)
  end

  defp generate_jwt_signature(data, secret, "HS512") do
    :hmac
    |> :crypto.mac(:sha512, secret, data)
    |> Base.url_encode64(padding: false)
  end

  defp generate_jwt_signature(_data, _secret, algorithm) do
    raise "Unsupported JWT algorithm: #{algorithm}"
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
