# Wait Integration

**Purpose**: Time-based workflow control with delays, scheduling, and webhooks  
**Category**: Control  
**Module**: `Prana.Integrations.Wait`

The Wait integration provides comprehensive time-based workflow control capabilities, supporting interval delays, scheduled execution, and webhook-based external event waiting.

## Actions

### Wait
- **Action Name**: `wait`
- **Description**: Unified wait action supporting multiple wait modes
- **Input Ports**: `["input"]`
- **Output Ports**: `["success", "timeout", "error"]`

**Input Parameters**:
- `mode`: Wait mode - `"interval"` | `"schedule"` | `"webhook"` (required)
- `pass_through`: Whether to pass input data to output (optional, defaults to `true`)

**Mode-Specific Parameters**:

**Interval Mode** - Wait for a specific duration:
- `duration`: Time to wait (required, number)
- `unit`: Time unit - `"ms"` | `"seconds"` | `"minutes"` | `"hours"` (optional, defaults to `"ms"`)

**Schedule Mode** - Wait until a specific datetime:
- `schedule_at`: ISO8601 datetime string when to resume (required)
- `timezone`: Timezone for schedule_at (optional, defaults to `"UTC"`)

**Webhook Mode** - Wait for an external HTTP request:
- `timeout_hours`: Hours until webhook expires (optional, defaults to 24, max 8760/1 year)
- `webhook_config`: Additional webhook configuration (optional)

**Returns**:
- `{:ok, %{}}` for interval mode with duration < 60 seconds (uses process sleep)
- `{:suspend, :interval | :schedule | :webhook, suspend_data}` to suspend execution for longer durations/other modes
- `{:error, reason, "error"}` if configuration is invalid

**Sleep vs Suspend Behavior (Interval Mode)**:
- **Short intervals** (< 60 seconds): Uses `Process.sleep()` and returns immediately with `{:ok, %{}}`
- **Long intervals** (≥ 60 seconds): Returns suspension data for non-blocking execution via scheduler

**Examples**:

*Short Interval Wait - 30 seconds (uses sleep)*:
```elixir
%{
  "mode" => "interval",
  "duration" => 30,
  "unit" => "seconds"
}
# Returns: {:ok, %{}} after sleeping for 30 seconds
```

*Long Interval Wait - 5 minutes (uses suspension)*:
```elixir
%{
  "mode" => "interval",
  "duration" => 5,
  "unit" => "minutes"
}
# Returns: {:suspend, :interval, suspension_data} for non-blocking execution
```

*Schedule Wait - Next Monday 9 AM*:
```elixir
%{
  "mode" => "schedule",
  "schedule_at" => "2025-07-07T09:00:00Z",
  "timezone" => "UTC"
}
```

*Webhook Wait - User approval with 72 hour timeout*:
```elixir
%{
  "mode" => "webhook",
  "timeout_hours" => 72,
  "webhook_config" => %{"approval_type" => "document_review"}
}
```

**Webhook Integration**:
The webhook mode integrates with the webhook system for external event coordination:

1. **Resume URL Generation**: Applications generate unique resume URLs using `Prana.Webhook.generate_resume_id/1`
2. **Token Mapping**: Applications store `token → node_id` mapping for webhook routing
3. **HTTP Handling**: Applications handle webhook endpoints and call `resume_workflow/4` to continue execution
4. **Lifecycle Management**: Webhooks follow strict lifecycle (pending → active → consumed/expired)

For complete webhook implementation details, see the [Wait/Resume Integration Guide](../guides/wait_resume_integration_guide.md).