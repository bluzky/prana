# HTTP Integration

**Purpose**: HTTP request actions and webhook triggers  
**Category**: Network  
**Module**: `Prana.Integrations.HTTP`

The HTTP integration provides HTTP request capabilities and webhook configuration functionality for external API interactions and incoming HTTP request handling. The webhook action configures webhook endpoints that can trigger new workflow executions when external HTTP requests are received.

## Actions

### HTTP Request
- **Action Name**: `request`
- **Description**: Make HTTP requests with configurable method, headers, and body
- **Input Ports**: `["input"]`
- **Output Ports**: `["success", "error", "timeout"]`

**Input Parameters** (Skema Schema Validated):
- `url`: Request URL (required, must start with http:// or https://)
- `method`: HTTP method (optional, defaults to "GET", one of: GET, POST, PUT, DELETE, HEAD, PATCH, OPTIONS)
- `headers`: Request headers as key-value pairs (optional, defaults to {})
- `body`: Raw request body as string (optional)
- `json`: JSON request body as object (optional)
- `params`: URL query parameters as key-value pairs (optional, defaults to {})
- `timeout`: Request timeout in milliseconds (optional, defaults to 5000, range: 1-300000)
- `retry`: Number of retry attempts (optional, defaults to 0, range: 0-10)
- `auth`: Authentication configuration (optional, see Authentication section)

**Authentication**:
The action supports multiple authentication types:

- **Basic Auth**: `{"type": "basic", "username": "user", "password": "pass"}`
- **Bearer Token**: `{"type": "bearer", "token": "your-token"}`
- **API Key**: `{"type": "api_key", "key": "your-key", "header": "X-API-Key"}` (header defaults to "X-API-Key")

**Returns**:
- `{:ok, response, "success"}` with response containing `status`, `headers`, and `body`
- `{:error, error_data, "timeout"}` if request times out
- `{:error, error_data, "error"}` for other HTTP or network errors

**Example**:
```elixir
%{
  "url" => "https://api.example.com/users",
  "method" => "POST",
  "headers" => %{"Content-Type" => "application/json"},
  "json" => %{"name" => "John", "email" => "john@example.com"},
  "timeout" => 10000,
  "auth" => %{
    "type" => "bearer",
    "token" => "your-api-token"
  }
}
```

### Webhook Configuration
- **Action Name**: `webhook`
- **Description**: Configure webhook endpoint for triggering workflow execution
- **Input Ports**: `[]` (no input - this is a trigger configuration)
- **Output Ports**: `["success"]`
- **Suspendable**: `false`

**Input Parameters** (Skema Schema Validated):
- `webhook_config`: Webhook configuration object (optional, defaults to {})
  - `path`: Webhook path (optional, defaults to "/webhook")
  - `methods`: Allowed HTTP methods (optional, defaults to ["POST"], valid: GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS)
  - `auth`: Authentication configuration (optional, defaults to {"type": "none"})
  - `response_type`: Response timing (optional, defaults to "immediately", one of: "immediately", "end_of_flow")
  - `secret`: Webhook secret for validation (optional)
  - `headers`: Expected headers (optional, defaults to {})

**Authentication Types**:
- **None**: `{"type": "none"}` (default)
- **Basic Auth**: `{"type": "basic", "username": "user", "password": "pass"}`
- **Header Auth**: `{"type": "header", "header_name": "X-API-Key", "header_value": "secret"}`
- **JWT Auth**: `{"type": "jwt", "jwt_secret": "secret"}` (algorithm extracted from token header)

**Base URL Configuration**:
The webhook base URL is configured via the `PRANA_BASE_URL` environment variable, not through input parameters. This ensures consistent webhook URL generation across the application.

**Returns**:
- `{:ok, configuration, "success"}` with webhook configuration details
- **On Error**: Execution fails immediately (no error output port)

**Configuration Response**:
```elixir
%{
  webhook_path: "/custom-webhook",
  allowed_methods: ["POST", "PUT"],
  auth_config: %{"type" => "basic", "username" => "user", "password" => "pass"},
  response_type: "immediately",
  webhook_url: "https://app.example.com/custom-webhook",  # if PRANA_BASE_URL is set
  configured_at: ~U[2025-01-01 12:00:00.000000Z]
}
```

**Example**:
```elixir
%{
  "webhook_config" => %{
    "path" => "/approval-webhook",
    "methods" => ["POST", "PUT"],
    "auth" => %{
      "type" => "jwt",
      "jwt_secret" => "your-jwt-secret"
    },
    "response_type" => "end_of_flow"
  }
}
```

**Webhook Validation**:
Use `Prana.Integrations.HTTP.WebhookAction.validate_webhook_request/2` to validate incoming HTTP requests against the webhook configuration:

```elixir
# In your application's HTTP handler
webhook_config = %{
  allowed_methods: ["POST"],
  auth_config: %{"type" => "basic", "username" => "user", "password" => "pass"}
}

request_data = %{
  method: "POST",
  headers: %{"authorization" => "Basic dXNlcjpwYXNz"},  # base64 "user:pass"
  body: "{\"data\": \"value\"}"
}

case WebhookAction.validate_webhook_request(webhook_config, request_data) do
  {:ok, validated_request} ->
    # Trigger new workflow execution with validated_request
    trigger_workflow_execution(validated_request)
  
  {:error, reason} ->
    # Authentication or method validation failed
    {:error, 401, reason}
end
```

## Schema Validation

Both actions use Skema schemas for comprehensive input validation:

- **Type Validation**: Ensures correct data types for all fields
- **Format Validation**: Validates URL formats, HTTP methods, and ranges
- **Default Values**: Applies sensible defaults for optional parameters  
- **Nested Validation**: Validates complex nested objects like authentication and webhook configuration
- **Error Formatting**: Provides clear, actionable error messages for validation failures

The schemas include built-in type casting (e.g., string numbers to integers) and comprehensive validation rules to ensure robust API interactions.