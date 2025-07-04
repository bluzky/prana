defmodule Prana.Integrations.HTTP do
  @moduledoc """
  HTTP Integration - Provides HTTP request actions and webhook triggers

  Supports:
  - HTTP requests with GET, POST, PUT, DELETE methods
  - Request configuration (headers, body, timeout, authentication)
  - Response handling with success/error/timeout port routing
  - Webhook triggers for incoming HTTP requests
  - Comprehensive error handling for network and HTTP errors

  This integration uses Req HTTP client for modern, performant HTTP operations.
  """

  @behaviour Prana.Behaviour.Integration

  alias Prana.Action
  alias Prana.Integration

  @doc """
  Returns the integration definition with all available actions
  """
  @impl true
  def definition do
    %Integration{
      name: "http",
      display_name: "HTTP",
      description: "HTTP requests and webhook handling",
      version: "1.0.0",
      category: "network",
      actions: %{
        "request" => %Action{
          name: "request",
          display_name: "HTTP Request",
          description: "Make HTTP requests with configurable method, headers, and body",
          module: Prana.Integrations.HTTP.RequestAction,
          input_ports: ["input"],
          output_ports: ["success", "error", "timeout"],
          default_success_port: "success",
          default_error_port: "error"
        },
        "webhook" => %Action{
          name: "webhook",
          display_name: "Webhook Trigger",
          description: "Wait for incoming HTTP webhook requests",
          module: Prana.Integrations.HTTP.WebhookAction,
          input_ports: ["input"],
          output_ports: ["success", "timeout", "error"],
          default_success_port: "success",
          default_error_port: "error"
        }
      }
    }
  end
end

defmodule Prana.Integrations.HTTP.RequestAction do
  @moduledoc """
  HTTP Request action implementation with Skema schema validation

  Supports GET, POST, PUT, DELETE methods with configurable headers, body, timeout, and authentication.
  """

  @behaviour Prana.Behaviour.Action

  use Skema

  defschema AuthSchema do
    field(:type, :string,
      required: true,
      in: ["basic", "bearer", "api_key"]
    )

    # For basic auth
    field(:username, :string)
    # For basic auth
    field(:password, :string)
    # For bearer auth
    field(:token, :string)
    # For API key
    field(:key, :string)
    # For API key
    field(:header, :string, default: "X-API-Key")
  end

  defschema HTTPRequestSchema do
    field(:url, :string,
      required: true,
      format: ~r/^https?:\/\/.+/
    )

    field(:method, :string,
      default: "GET",
      in: ["GET", "POST", "PUT", "DELETE", "HEAD", "PATCH", "OPTIONS"]
    )

    field(:headers, :map, default: %{})

    field(:timeout, :integer,
      default: 5000,
      number: [min: 1, max: 300_000]
    )

    field(:retry, :integer,
      default: 0,
      number: [min: 0, max: 10]
    )

    field(:auth, AuthSchema)
    field(:body, :string)
    field(:json, :map)
    field(:params, :map, default: %{})
  end

  @impl true
  def input_schema, do: HTTPRequestSchema

  @impl true
  def validate_input(input_map) do
    case HTTPRequestSchema.cast_and_validate(input_map) do
      {:ok, validated_data} ->
        {:ok, validated_data}

      {:error, errors} ->
        {:error, format_errors(errors)}
    end
  end

  @impl true
  def prepare(_node) do
    {:ok, %{prepared_at: DateTime.utc_now()}}
  end

  @impl true
  def execute(input_map) do
    case make_http_request(input_map) do
      {:ok, response} ->
        {:ok, format_response(response), "success"}

      {:error, :timeout} ->
        {:error, %{type: "timeout", message: "Request timed out"}, "timeout"}

      {:error, reason} when is_binary(reason) ->
        {:error, %{type: "http_error", message: reason}, "error"}

      {:error, reason} ->
        {:error, %{type: "http_error", message: format_error(reason)}, "error"}
    end
  end

  @impl true
  def resume(_suspend_data, _resume_input) do
    {:error, "HTTP request action does not support resume"}
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

  # Make HTTP request using Req
  defp make_http_request(input_map) do
    with {:ok, method} <- get_method(input_map),
         {:ok, url} <- get_url(input_map),
         {:ok, options} <- build_request_options(input_map) do
      case method do
        :get -> Req.get(url, options)
        :post -> Req.post(url, options)
        :put -> Req.put(url, options)
        :delete -> Req.delete(url, options)
        :head -> Req.head(url, options)
        :patch -> Req.patch(url, options)
        :options -> Req.request(url, [method: :options] ++ options)
      end
    end
  end

  # Get HTTP method from input
  defp get_method(input_map) do
    method = Map.get(input_map, "method", "GET")

    case String.downcase(method) do
      "get" -> {:ok, :get}
      "post" -> {:ok, :post}
      "put" -> {:ok, :put}
      "delete" -> {:ok, :delete}
      "head" -> {:ok, :head}
      "patch" -> {:ok, :patch}
      "options" -> {:ok, :options}
      _ -> {:error, "Unsupported HTTP method: #{method}"}
    end
  end

  # Get URL from input
  defp get_url(input_map) do
    case Map.get(input_map, "url") do
      nil -> {:error, "URL is required"}
      url when is_binary(url) -> {:ok, url}
      _ -> {:error, "URL must be a string"}
    end
  end

  # Build request options for Req
  defp build_request_options(input_map) do
    with {:ok, options} <- add_headers([], input_map),
         {:ok, options} <- add_body(options, input_map),
         {:ok, options} <- add_json(options, input_map),
         {:ok, options} <- add_timeout(options, input_map),
         {:ok, options} <- add_auth(options, input_map),
         {:ok, options} <- add_params(options, input_map) do
      add_retry(options, input_map)
    end
  end

  # Helper functions for building options
  defp add_headers(options, input_map) do
    case Map.get(input_map, "headers") do
      nil -> {:ok, options}
      headers when is_map(headers) -> {:ok, Keyword.put(options, :headers, headers)}
      _ -> {:error, "Headers must be a map"}
    end
  end

  defp add_body(options, input_map) do
    case Map.get(input_map, "body") do
      nil -> {:ok, options}
      body -> {:ok, Keyword.put(options, :body, body)}
    end
  end

  defp add_json(options, input_map) do
    case Map.get(input_map, "json") do
      nil -> {:ok, options}
      json -> {:ok, Keyword.put(options, :json, json)}
    end
  end

  defp add_timeout(options, input_map) do
    case Map.get(input_map, "timeout") do
      nil -> {:ok, options}
      timeout when is_integer(timeout) -> {:ok, Keyword.put(options, :receive_timeout, timeout)}
      _ -> {:error, "Timeout must be an integer (milliseconds)"}
    end
  end

  defp add_auth(options, input_map) do
    case build_auth_options(input_map) do
      {:ok, auth_options} -> {:ok, Keyword.merge(options, auth_options)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp add_params(options, input_map) do
    case Map.get(input_map, "params") do
      nil -> {:ok, options}
      params when is_map(params) -> {:ok, Keyword.put(options, :params, params)}
      _ -> {:error, "Params must be a map"}
    end
  end

  defp add_retry(options, input_map) do
    case Map.get(input_map, "retry") do
      nil -> {:ok, options}
      retry when is_boolean(retry) -> {:ok, Keyword.put(options, :retry, retry)}
      retry when is_integer(retry) -> {:ok, Keyword.put(options, :retry, retry)}
      _ -> {:error, "Retry must be boolean or integer"}
    end
  end

  # Build authentication options
  defp build_auth_options(input_map) do
    case Map.get(input_map, "auth") do
      nil ->
        {:ok, []}

      %{"type" => "basic", "username" => username, "password" => password} ->
        {:ok, [auth: {username, password}]}

      %{"type" => "bearer", "token" => token} ->
        {:ok, [auth: {:bearer, token}]}

      %{"type" => "api_key", "key" => key, "header" => header} ->
        header_name = header || "X-API-Key"
        {:ok, [headers: %{header_name => key}]}

      _ ->
        {:error, "Invalid authentication configuration"}
    end
  end

  # Format successful response
  defp format_response(%Req.Response{} = response) do
    %{
      status: response.status,
      headers: response.headers,
      body: response.body
    }
  end

  # Format error for output
  defp format_error(%Req.TransportError{reason: reason}), do: "Transport error: #{inspect(reason)}"
  defp format_error(%Req.HTTPError{} = error), do: "HTTP error: #{inspect(error)}"
  defp format_error(reason), do: inspect(reason)
end

defmodule Prana.Integrations.HTTP.WebhookAction do
  @moduledoc """
  Webhook action implementation using Action behavior with suspend/resume pattern

  Suspends execution and waits for incoming HTTP webhook requests.
  """

  @behaviour Prana.Behaviour.Action

  use Skema

  defschema WebhookConfigSchema do
    field(:path, :string, default: "/webhook")
    field(:secret, :string)
    field(:headers, :map, default: %{})
  end

  defschema WebhookSchema do
    field(:timeout_hours, :float,
      default: 24.0,
      number: [min: 0.1, max: 8760.0]
    )

    field(:base_url, :string, format: ~r/^https?:\/\/.+/)

    field(:webhook_config, WebhookConfigSchema, default: %{})
  end

  @impl true
  def input_schema, do: WebhookSchema

  @impl true
  def validate_input(input_map) do
    case Skema.cast_and_validate(input_map, WebhookSchema) do
      {:ok, validated_data} -> {:ok, validated_data}
      {:error, errors} -> {:error, format_errors(errors)}
    end
  end

  @impl true
  def prepare(node) do
    # Webhook preparation could include URL generation
    config = Map.get(node, :config, %{})

    preparation_data = %{
      timeout_hours: Map.get(config, "timeout_hours", 24),
      webhook_path: Map.get(config, "webhook_path", "/webhook"),
      prepared_at: DateTime.utc_now()
    }

    {:ok, preparation_data}
  end

  @impl true
  def execute(input_map) do
    timeout_hours = Map.get(input_map, "timeout_hours", 24)
    webhook_config = Map.get(input_map, "webhook_config", %{})

    case validate_webhook_config(timeout_hours, webhook_config) do
      :ok ->
        now = DateTime.utc_now()
        expires_at = DateTime.add(now, timeout_hours * 3600, :second)

        # Build webhook URL if base_url provided
        webhook_url =
          case Map.get(input_map, "base_url") do
            nil ->
              nil

            base_url ->
              webhook_path = Map.get(webhook_config, "path", "/webhook")
              "#{base_url}#{webhook_path}"
          end

        suspend_data = %{
          mode: "webhook",
          timeout_hours: timeout_hours,
          webhook_config: webhook_config,
          started_at: now,
          expires_at: expires_at,
          webhook_url: webhook_url,
          input_data: input_map
        }

        {:suspend, :webhook, suspend_data}

      {:error, reason} ->
        {:error, %{type: "webhook_config_error", message: reason}, "error"}
    end
  end

  @impl true
  def resume(suspend_data, resume_input) do
    expires_at = Map.get(suspend_data, :expires_at)

    # Check if webhook has expired
    if expires_at && DateTime.after?(DateTime.utc_now(), expires_at) do
      {:error, %{type: "webhook_timeout", message: "Webhook has expired"}}
    else
      # Return webhook payload
      {:ok,
       %{
         webhook_payload: resume_input,
         received_at: DateTime.utc_now(),
         original_input: Map.get(suspend_data, :input_data, %{})
       }}
    end
  end

  @impl true
  def suspendable?, do: true

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

  # Validate webhook configuration
  defp validate_webhook_config(timeout_hours, _webhook_config) do
    if is_number(timeout_hours) and timeout_hours > 0 and timeout_hours <= 8760 do
      :ok
    else
      {:error, "timeout_hours must be a positive number between 1 and 8760 (1 year)"}
    end
  end
end
