# ADR-005: Webhook System Architecture

**Status**: Accepted
**Date**: 2025-01-02
**Updated**: 2025-07-02
**Authors**: Development Team
**Reviewers**: Architecture Team

## Context

Prana workflows need to handle webhook interactions for two distinct use cases:

1. **Workflow Triggers**: Webhooks that start new workflow executions
2. **Execution Resume**: Webhooks that resume suspended workflow executions (e.g., user approvals, external API callbacks)

The system must support:
- Fast webhook routing and lookup
- Persistence across application restarts
- Clear separation between trigger and resume webhooks
- Integration with Prana's suspension/resume mechanism
- Scalable webhook management
- **Webhook lifecycle validation**: Resume webhooks are only valid during specific execution windows
- **Pre-generated resume URLs**: Available in expressions before wait nodes execute (like n8n's `$execution.resumeUrl`)

## Decision

We will implement a **Distributed Webhook System** with clear separation of responsibilities:

### Prana Library Responsibilities
- **Webhook URL generation**: Generate unique resume URLs at execution start
- **Webhook data structures**: Provide structs and utilities for webhook management
- **Execution integration**: Include webhook data in execution results when suspended
- **Resume coordination**: Handle webhook resume via existing `resume_workflow/4` API

### Application Responsibilities
- **HTTP routing**: Handle webhook endpoints (`/webhook/workflow/trigger/:workflow_id`, `/webhook/workflow/resume/:resume_id`)
- **Persistence**: Store webhook data from execution results in distributed database
- **Security & validation**: Authenticate webhook requests and validate state
- **Resume invocation**: Call Prana's `resume_workflow/4` when webhooks received

### Webhook Flow Architecture
```
1. Execution Start → Scan workflow for wait nodes → Generate resume URLs for each wait node
2. Resume URLs available as $execution.{node_id}.resume_url expressions
3. Email Node → Uses $execution.wait_approval.resume_url in email template
4. Wait Node → Activates its pre-generated webhook URL
5. Webhook Request → Application validates → Calls resume_workflow/4
6. Execution Resume → Normal Prana workflow continuation at specific node
```

### Multiple Wait Node Support
- **Pre-generate resume URLs** for all wait nodes at execution start
- **Node-specific expressions**: `$execution.{node_id}.resume_url`
- **Multiple active webhooks** supported simultaneously
- **Deterministic URLs** available before wait nodes execute

### Webhook Utilities Design

```elixir
# Webhook utilities (no centralized state)
defmodule Prana.Webhook do
  @doc "Generate resume webhook ID at execution start"
  def generate_execution_resume_id(execution_id)

  @doc "Parse webhook URLs for routing"
  def parse_webhook_url(url_path)

  @doc "Build full webhook URLs"
  def build_webhook_url(base_url, type, id)

  @doc "Create webhook registration data"
  def create_webhook_registration(resume_id, execution_id, node_id, config)

  @doc "Validate webhook for resume (application calls this)"
  def validate_webhook_resume(webhook_registration, payload)
end
```

### URL Pattern Structure

```
Trigger Webhooks:
/webhook/workflow/trigger/user_signup
/webhook/workflow/trigger/order_processing
/webhook/workflow/trigger/document_approval

Resume Webhooks:
/webhook/workflow/resume/exec_123_node_456_abc
/webhook/workflow/resume/exec_789_approval_def
/webhook/workflow/resume/exec_012_wait_ghi
```

### Webhook Lifecycle States

Resume webhooks follow a strict lifecycle with validation:

```elixir
# Webhook states
"pending"    # Created at execution start, not yet active
:active     # Wait node activated, ready to receive requests
:consumed   # Successfully used to resume execution (one-time use)
:expired    # Timed out or execution completed without use
```

### Webhook State Management

```elixir
# Webhook registry state tracking
%{
  "webhook_12345_abc789" => %{
    execution_id: "exec_123",
    status: "pending",        # State transition: pending → active → consumed/expired
    waiting_node_id: nil,    # Set when wait node activates
    expires_at: nil,         # Set when wait node activates with timeout
    created_at: DateTime.utc_now(),
    webhook_config: %{}      # Set when wait node activates
  }
}

# State validation and data extraction for existing GraphExecutor API
def handle_resume_webhook(webhook_id, payload) do
  case get_webhook_state(webhook_id) do
    %{status: "pending"} ->
      {:error, :wait_node_not_active}
    %{status: :active, execution_id: exec_id, waiting_node_id: node_id, expires_at: expires}
    when expires > DateTime.utc_now() ->
      mark_consumed(webhook_id)
      {:ok, exec_id, node_id, payload}  # Return data for GraphExecutor.resume_workflow/4
    %{status: :active} ->
      {:error, :webhook_expired}
    %{status: :consumed} ->
      {:error, :webhook_already_used}
    %{status: :expired} ->
      {:error, :webhook_expired}
    nil ->
      {:error, :webhook_not_found}
  end
end
```

### Expression Engine Integration

```elixir
# Resume URL available in expressions from execution start
"$execution.resume_url" → "webhook_12345_abc789"

# Enhanced ExecutionContext
%Prana.WorkflowExecutionContext{
  # ... existing fields
  resume_url: "webhook_12345_abc789",  # Generated at execution start
}

# Used in email templates before wait node:
%Prana.Node{
  integration: "email",
  action: "send_email",
  configuration: %{
    to: "$input.email",
    subject: "Approval Required",
    body: "Click to approve: https://app.com/webhook/workflow/resume/$execution.resume_url?action=approve"
  }
}
```

### Webhook Registration Data Structure

```elixir
# Data structure for webhook persistence (application responsibility)
webhook_registration = %{
  resume_id: "webhook_12345_abc789",
  webhook_url: "/webhook/workflow/resume/webhook_12345_abc789",
  full_url: "https://app.domain.com/webhook/workflow/resume/webhook_12345_abc789",
  execution_id: "exec_123",
  status: "pending",        # Initial state
  created_at: ~U[2025-01-02 10:00:00Z],
  expires_at: nil,         # Set when activated
  webhook_config: %{}      # Set when activated
}
```

### Application Integration Pattern

```elixir
# HTTP Router Setup
defmodule MyApp.Router do
  use Phoenix.Router

  # Trigger webhooks - start new executions
  post "/webhook/workflow/trigger/:workflow_id", WebhookController, :handle_trigger

  # Resume webhooks - resume suspended executions
  post "/webhook/workflow/resume/:webhook_id", WebhookController, :handle_resume
end

# 1. Trigger Webhook Handler
def handle_trigger(conn, %{"workflow_id" => workflow_id}) do
  payload = extract_payload(conn)

  case MyApp.WorkflowEngine.start_workflow(workflow_id, payload) do
    {:ok, execution_id} ->
      json(conn, %{status: "started", execution_id: execution_id})

    {"suspended", webhook_url} ->
      json(conn, %{status: "suspended", resume_url: webhook_url})

    {:error, reason} ->
      conn |> put_status(400) |> json(%{error: reason})
  end
end

# Application workflow starter
defmodule MyApp.WorkflowEngine do
  def start_workflow(workflow_id, input_data) do
    execution_id = generate_execution_id()
    resume_url = Prana.WebhookRegistry.generate_resume_url(execution_id)

    context = %Prana.WorkflowExecutionContext{
      execution_id: execution_id,
      resume_url: resume_url,
      # ... other fields
    }

    # Create pending webhook in database
    MyApp.WebhookDB.create_pending_webhook(resume_url, execution_id)

    case Prana.GraphExecutor.execute_workflow(workflow_id, input_data, context) do
      {:suspend, :external_event, suspension_data} ->
        # Activate webhook and save execution state
        MyApp.WebhookDB.activate_webhook(resume_url, suspension_data)
        MyApp.ExecutionDB.save_suspended(execution_id, suspension_data)
        {"suspended", build_full_webhook_url(resume_url)}

      {:ok, result} ->
        MyApp.WebhookDB.expire_webhook(resume_url)
        {:ok, execution_id}

      {:error, reason} ->
        MyApp.WebhookDB.expire_webhook(resume_url)
        {:error, reason}
    end
  end
end

# 2. Resume Webhook Handler
def handle_resume(conn, %{"webhook_id" => webhook_id}) do
  payload = extract_payload(conn)

  case Prana.WebhookRegistry.handle_resume_webhook(webhook_id, payload) do
    {:ok, execution_id, node_id, resume_data} ->
      # Load execution context and resume using existing GraphExecutor API
      context = MyApp.ExecutionDB.load_context(execution_id)

      case Prana.GraphExecutor.resume_workflow(execution_id, node_id, resume_data, context) do
        {:ok, result} ->
          MyApp.WebhookDB.mark_consumed(webhook_id)
          json(conn, %{status: "completed", result: result})

        {:suspend, :external_event, suspension_data} ->
          # Another suspension - reactivate webhook
          MyApp.WebhookDB.reactivate_webhook(webhook_id, suspension_data)
          MyApp.ExecutionDB.save_suspended(execution_id, suspension_data)
          json(conn, %{status: "suspended"})

        {:error, reason} ->
          conn |> put_status(500) |> json(%{error: reason})
      end

    {:error, :wait_node_not_active} ->
      conn |> put_status(400) |> json(%{error: "Wait node not active"})

    {:error, :webhook_expired} ->
      conn |> put_status(410) |> json(%{error: "Webhook expired"})

    {:error, :webhook_already_used} ->
      conn |> put_status(409) |> json(%{error: "Webhook already used"})

    {:error, :webhook_not_found} ->
      conn |> put_status(404) |> json(%{error: "Webhook not found"})
  end
end

# 3. Cleanup via middleware
defmodule MyApp.WebhookCleanupMiddleware do
  def call(:execution_completed, %{context: context}, next) do
    MyApp.WebhookDB.expire_webhook(context.resume_url)
    next.(%{context: context})
  end

  def call(:execution_failed, %{context: context}, next) do
    MyApp.WebhookDB.expire_webhook(context.resume_url)
    next.(%{context: context})
  end

  def call(event, data, next), do: next.(data)
end
```

## Rationale

### Why Two-Tier System?

1. **Performance**: Trigger webhooks need fast lookup without database queries
2. **Scalability**: Resume webhooks need persistence and expiry management
3. **Separation of Concerns**: Different lifecycle and storage requirements
4. **n8n Compatibility**: Follows proven patterns from mature workflow platforms (e.g., `$execution.resumeUrl`)

### Why Pre-Generated Resume URLs?

1. **Expression Availability**: URLs must be available in expressions before wait nodes execute
2. **Email/Notification Integration**: Templates can include resume URLs for approval workflows
3. **n8n Pattern Compatibility**: Matches `$execution.resumeUrl` behavior from n8n
4. **User Experience**: Consistent URL format throughout workflow execution

### Why Webhook Lifecycle Validation?

1. **Security**: Prevents unauthorized or repeated webhook usage
2. **State Management**: Ensures webhooks are only valid during active wait periods
3. **Error Prevention**: Clear error messages for invalid webhook timing
4. **One-Time Use**: Prevents replay attacks and duplicate processing

### Why Database-Backed Resume Webhooks?

1. **Persistence**: Survive application restarts and deployments
2. **State Tracking**: Manage webhook lifecycle (pending → active → consumed/expired)
3. **Auditability**: Track webhook usage and lifecycle
4. **Scalability**: Support high-volume webhook operations

### Why URL Pattern `/webhook/workflow/:action/:action_id`?

1. **Clarity**: Clear distinction between trigger and resume actions
2. **RESTful**: Follows REST conventions for resource organization
3. **Extensibility**: Easy to add new webhook action types
4. **Routing**: Simple path-based routing logic


## Consequences

### Positive

1. **Clear Separation**: Distinct handling for triggers vs resumes
2. **Persistence**: Webhooks survive application restarts
3. **Performance**: Fast routing with minimal database queries
4. **Scalability**: Supports high-volume webhook operations
5. **Maintainability**: Clean architecture with well-defined boundaries
6. **Security**: Lifecycle validation prevents unauthorized webhook usage
7. **Expression Integration**: Resume URLs available throughout workflow execution
8. **n8n Compatibility**: Familiar patterns for workflow automation users

### Negative

1. **Complexity**: Two-tier system and lifecycle management adds architectural complexity
2. **Application Dependency**: Resume webhooks require application-layer persistence and state tracking
3. **URL Management**: Application must manage webhook URL generation and cleanup
4. **State Synchronization**: Library and application must coordinate webhook state transitions

## References

- **n8n Webhook Architecture**: Research on n8n's webhook handling patterns
- **ADR-003 Unified Suspension Resume**: Foundation for webhook resume mechanism
- **REST API Design Guidelines**: URL pattern conventions
- **Database Design Patterns**: Webhook persistence strategies

## Review Notes

- Consider webhook authentication and security in future ADRs
- Monitor webhook performance and optimize database queries
- Evaluate webhook rate limiting and abuse prevention
- Plan for webhook analytics and monitoring

---

**Next Review Date**: 2025-02-01
**Related ADRs**: ADR-003 (Unified Suspension Resume)
