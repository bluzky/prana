defmodule Prana.Integrations.HTTP.RequestAction do
  @moduledoc """
  HTTP Request action implementation with Skema schema validation

  Supports GET, POST, PUT, DELETE methods with configurable headers, body, timeout, and authentication.
  """

  @behaviour Prana.Behaviour.Action

  use Skema

  alias Prana.Action
  alias Prana.Core.Error

  def definition do
    %Action{
      name: "http.request",
      display_name: "HTTP Request",
      description: "Make HTTP requests with configurable method, headers, and body",
      type: :action,
      input_ports: ["main"],
      output_ports: ["main", "error", "timeout"]
    }
  end

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

    field(:auth, AuthSchema)
    field(:body, :string)
    field(:json, :map)
    field(:params, :map, default: %{})
  end

  @impl true
  def params_schema, do: HTTPRequestSchema

  @impl true
  def validate_params(input_map) do
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
  def execute(params, _context) do
    case make_http_request(params) do
      {:ok, response} ->
        {:ok, format_response(response), "success"}

      {:error, :timeout} ->
        {:error, Error.action_error("http_timeout", "Request timed out"), "timeout"}

      {:error, reason} when is_binary(reason) ->
        {:error, Error.action_error("http_error", reason), "error"}

      {:error, reason} ->
        {:error, Error.action_error("http_error", format_error(reason)), "error"}
    end
  end

  @impl true
  def resume(_params, _context, _resume_data) do
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
         {:ok, options} <- add_auth(options, input_map) do
      add_params(options, input_map)
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
