# HTTP Integration

**Purpose**: HTTP request actions and webhook triggers  
**Category**: Network  
**Module**: `Prana.Integrations.HTTP`

The HTTP integration provides HTTP request capabilities and webhook trigger functionality for external API interactions and incoming HTTP request handling.

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

### Webhook Trigger
- **Action Name**: `webhook`
- **Description**: Wait for incoming HTTP webhook requests
- **Input Ports**: `["input"]`
- **Output Ports**: `["success", "timeout", "error"]`

**Input Parameters** (Skema Schema Validated):
- `timeout_hours`: Hours until webhook expires (optional, defaults to 24.0, range: 0.1-8760.0)
- `base_url`: Base URL for webhook URL generation (optional, must start with http:// or https://)
- `webhook_config`: Webhook configuration object (optional, defaults to {})
  - `path`: Webhook path (optional, defaults to "/webhook")
  - `secret`: Webhook secret for validation (optional)
  - `headers`: Expected headers (optional, defaults to {})

**Returns**:
- `{:suspend, :webhook, suspend_data}` to suspend and wait for webhook
- `{:error, error_data, "error"}` if configuration is invalid

**Suspension Data**:
When suspended, the action provides comprehensive context:
- `mode`: "webhook"
- `timeout_hours`: Configured timeout
- `webhook_config`: Webhook configuration
- `started_at`: Suspension timestamp
- `expires_at`: Webhook expiration timestamp
- `webhook_url`: Generated webhook URL (if base_url provided)
- `input_data`: Original input data

**Resume**:
When a webhook is received, the action resumes with:
- `webhook_payload`: The received webhook data
- `received_at`: Timestamp when webhook was received
- `original_input`: Original input data from suspension

**Example**:
```elixir
%{
  "timeout_hours" => 72.0,
  "base_url" => "https://app.example.com",
  "webhook_config" => %{
    "path" => "/approval-webhook",
    "secret" => "webhook-secret",
    "headers" => %{"X-Webhook-Source" => "approval-system"}
  }
}
```

## Schema Validation

Both actions use Skema schemas for comprehensive input validation:

- **Type Validation**: Ensures correct data types for all fields
- **Format Validation**: Validates URL formats, HTTP methods, and ranges
- **Default Values**: Applies sensible defaults for optional parameters  
- **Nested Validation**: Validates complex nested objects like authentication and webhook configuration
- **Error Formatting**: Provides clear, actionable error messages for validation failures

The schemas include built-in type casting (e.g., string numbers to integers) and comprehensive validation rules to ensure robust API interactions.