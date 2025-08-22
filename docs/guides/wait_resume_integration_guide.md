# Wait/Resume Integration Guide

**Version**: 1.0
**Date**: 2025-07-02
**Target Audience**: Application Developers
**Prerequisites**: Basic understanding of Prana workflows and Phoenix/HTTP handling

## Overview

This guide demonstrates how to implement webhook-based wait/resume workflows using Prana's Wait integration. The wait/resume pattern enables workflows to pause execution and wait for external events like user approvals, payment confirmations, or third-party API callbacks.

## Architecture Overview

```
1. Workflow Start → Generate resume URLs for wait nodes
2. Email/Notification → Include resume URL in message
3. Wait Node → Suspend execution, activate webhook
4. External Event → HTTP request to resume URL
5. Application → Validates webhook, calls resume_workflow/4
6. Workflow Resume → Continue execution from wait node
```

## Core Concepts

### Wait Modes

The Wait integration supports three modes:

- **`interval`**: Wait for a specific duration (e.g., 5 minutes, 2 hours)
  - **Short intervals** (< 60 seconds): Uses `Process.sleep()` - workflow blocks but completes synchronously
  - **Long intervals** (≥ 60 seconds): Uses suspension - workflow suspends and resumes via scheduler
- **`schedule`**: Wait until a specific datetime (e.g., next Monday at 9 AM) - always uses suspension
- **`webhook`**: Wait for an external HTTP request (e.g., user approval, payment callback) - always uses suspension

### Resume URLs

Resume URLs are generated at execution start and available via expressions:
- `$execution.{node_id}.resume_url` - Node-specific resume URL
- Available before wait nodes execute (for use in emails/notifications)
- Pattern: `webhook_{execution_id}_{node_id}_{random}`

## Implementation Guide

### Step 1: Basic Wait Workflow

First, let's create a simple approval workflow:

```elixir
# Define workflow with wait node
workflow = %Prana.Workflow{
  id: "approval_workflow",
  name: "Document Approval Workflow",
  nodes: [
    # Trigger node
    %Prana.Node{
      id: "trigger",
      integration: "manual",
      action: "webhook_trigger",
      configuration: %{}
    },

    # Send approval email
    %Prana.Node{
      id: "send_email",
      integration: "email",
      action: "send_email",
      configuration: %{
        to: "$input.approver_email",
        subject: "Document Approval Required",
        body: """
        Please review and approve the document: $input.document_name

        Approve: https://myapp.com/webhook/workflow/resume/$execution.wait_approval.resume_url?action=approve
        Reject: https://myapp.com/webhook/workflow/resume/$execution.wait_approval.resume_url?action=reject
        """
      }
    },

    # Wait for approval webhook
    %Prana.Node{
      id: "wait_approval",
      integration: "wait",
      action: "wait",
      configuration: %{
        "mode" => "webhook",
        "timeout_hours" => 72  # 3 days to respond
      }
    },

    # Process approval result
    %Prana.Node{
      id: "process_result",
      integration: "manual",
      action: "debug_log",
      configuration: %{
        message: "Approval received: $input.action"
      }
    }
  ],
  connections: [
    %Prana.Connection{
      from_node: "trigger",
      to_node: "send_email",
      from_port: "success",
      to_port: "input"
    },
    %Prana.Connection{
      from_node: "send_email",
      to_node: "wait_approval",
      from_port: "success",
      to_port: "input"
    },
    %Prana.Connection{
      from_node: "wait_approval",
      to_node: "process_result",
      from_port: "success",
      to_port: "input"
    }
  ]
}
```

### Step 2: Application Integration

Implement webhook handling in your Phoenix application:

```elixir
# Router setup
defmodule MyApp.Router do
  use Phoenix.Router

  # Webhook endpoints
  post "/webhook/workflow/trigger/:workflow_id", WebhookController, :handle_trigger
  post "/webhook/workflow/resume/:resume_id", WebhookController, :handle_resume
  get "/webhook/workflow/resume/:resume_id", WebhookController, :handle_resume  # Support GET for simple links
end

# Webhook controller
defmodule MyApp.WebhookController do
  use MyApp, :controller

  # Handle workflow triggers
  def handle_trigger(conn, %{"workflow_id" => workflow_id}) do
    payload = extract_payload(conn)

    case MyApp.WorkflowEngine.start_workflow(workflow_id, payload) do
      {:ok, execution_id} ->
        json(conn, %{status: "completed", execution_id: execution_id})

      {"suspended", execution_id, webhook_data} ->
        json(conn, %{status: "suspended", execution_id: execution_id})

      {:error, reason} ->
        conn |> put_status(400) |> json(%{error: reason})
    end
  end

  # Handle webhook resumes (both POST and GET)
  def handle_resume(conn, %{"resume_id" => resume_id}) do
    # Extract data from query params (GET) or body (POST)
    resume_data = case conn.method do
      "GET" -> conn.query_params
      "POST" -> extract_payload(conn)
    end

    case MyApp.WorkflowEngine.resume_workflow(resume_id, resume_data) do
      {:ok, execution_id} ->
        case conn.method do
          "GET" ->
            # Redirect to success page for browser requests
            redirect(conn, to: "/approval/success?execution_id=#{execution_id}")
          "POST" ->
            json(conn, %{status: "completed", execution_id: execution_id})
        end

      {"suspended", execution_id} ->
        json(conn, %{status: "suspended", execution_id: execution_id})

      {:error, reason} ->
        case conn.method do
          "GET" ->
            redirect(conn, to: "/approval/error?reason=#{reason}")
          "POST" ->
            conn |> put_status(400) |> json(%{error: reason})
        end
    end
  end

  defp extract_payload(conn) do
    case conn.body_params do
      %{} = params when map_size(params) > 0 -> params
      _ -> conn.query_params
    end
  end
end
```

### Step 3: Workflow Engine Implementation

```elixir
defmodule MyApp.WorkflowEngine do
  alias Prana.GraphExecutor
  alias MyApp.{ExecutionStorage, WebhookStorage}

  def start_workflow(workflow_id, input_data) do
    execution_id = generate_execution_id()

    # Create execution context with pre-generated resume URLs
    context = create_execution_context(execution_id, workflow_id)

    case GraphExecutor.execute_workflow(workflow_id, input_data, context, last_output) do
      {:ok, result} ->
        # Workflow completed without suspension
        cleanup_webhooks(execution_id)
        {:ok, execution_id}

      {:suspend, :webhook, suspension_data} ->
        # Save execution state and activate webhook
        save_suspended_execution(execution_id, suspension_data, context)
        activate_webhook(suspension_data, context)
        {"suspended", execution_id, suspension_data}

      {:error, reason} ->
        cleanup_webhooks(execution_id)
        {:error, reason}
    end
  end

  def resume_workflow(resume_id, resume_data) do
    with {:ok, webhook} <- WebhookStorage.get_active_webhook(resume_id),
         {:ok, execution} <- ExecutionStorage.get_suspended_execution(webhook.execution_id),
         :ok <- validate_webhook_not_expired(webhook) do

      # Mark webhook as consumed
      WebhookStorage.mark_webhook_consumed(resume_id)

      # Resume execution
      case GraphExecutor.resume_workflow(
        webhook.execution_id,
        webhook.node_id,
        resume_data,
        execution.context
      ) do
        {:ok, result} ->
          ExecutionStorage.mark_completed(webhook.execution_id)
          cleanup_webhooks(webhook.execution_id)
          {:ok, webhook.execution_id}

        {:suspend, :webhook, suspension_data} ->
          # Another suspension - save state and activate new webhook
          save_suspended_execution(webhook.execution_id, suspension_data, execution.context)
          activate_webhook(suspension_data, execution.context)
          {"suspended", webhook.execution_id}

        {:error, reason} ->
          ExecutionStorage.mark_failed(webhook.execution_id, reason)
          cleanup_webhooks(webhook.execution_id)
          {:error, reason}
      end
    else
      {:error, :webhook_not_found} -> {:error, "Invalid webhook URL"}
      {:error, :webhook_expired} -> {:error, "Webhook has expired"}
      {:error, :webhook_consumed} -> {:error, "Webhook already used"}
      error -> error
    end
  end

  # Private helper functions

  defp create_execution_context(execution_id, workflow_id) do
    # Scan workflow for wait nodes and generate resume URLs
    resume_urls = scan_and_generate_resume_urls(workflow_id, execution_id)

    %Prana.WorkflowExecutionContext{
      execution_id: execution_id,
      resume_urls: resume_urls,
      variables: %{},
      outputs: %{}
    }
  end

  defp scan_and_generate_resume_urls(workflow_id, execution_id) do
    # TODO: This will be implemented in webhook system tasks
    # For now, return empty map
    %{}
  end

  defp save_suspended_execution(execution_id, suspension_data, context) do
    ExecutionStorage.save_suspended(%{
      execution_id: execution_id,
      suspension_data: suspension_data,
      context: context,
      suspended_at: DateTime.utc_now()
    })
  end

  defp activate_webhook(suspension_data, context) do
    # Extract webhook info from suspension_data
    node_id = suspension_data["node_id"]  # This would come from NodeExecutor
    resume_url = context.resume_urls[node_id]

    if resume_url do
      WebhookStorage.activate_webhook(%{
        resume_id: resume_url,
        execution_id: context.execution_id,
        node_id: node_id,
        expires_at: suspension_data["expires_at"],
        webhook_config: suspension_data["webhook_config"] || %{}
      })
    end
  end

  defp validate_webhook_not_expired(webhook) do
    if DateTime.compare(DateTime.utc_now(), webhook.expires_at) == :lt do
      :ok
    else
      {:error, :webhook_expired}
    end
  end

  defp cleanup_webhooks(execution_id) do
    WebhookStorage.expire_webhooks_for_execution(execution_id)
  end

  defp generate_execution_id do
    "exec_" <> (:crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false))
  end
end
```

### Step 4: Storage Implementation

```elixir
# Webhook storage (using ETS for simplicity - use database in production)
defmodule MyApp.WebhookStorage do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    table = :ets.new(:webhooks, [:set, :public, :named_table])
    {:ok, %{table: table}}
  end

  # Create pending webhook (called at execution start)
  def create_pending_webhook(resume_id, execution_id, node_id) do
    webhook = %{
      resume_id: resume_id,
      execution_id: execution_id,
      node_id: node_id,
      status: "pending",
      created_at: DateTime.utc_now(),
      expires_at: nil,
      webhook_config: %{}
    }

    :ets.insert(:webhooks, {resume_id, webhook})
    {:ok, webhook}
  end

  # Activate webhook (called when wait node executes)
  def activate_webhook(webhook_data) do
    case :ets.lookup(:webhooks, webhook_data.resume_id) do
      [{resume_id, webhook}] ->
        updated_webhook = %{webhook |
          status: :active,
          expires_at: webhook_data.expires_at,
          webhook_config: webhook_data.webhook_config
        }
        :ets.insert(:webhooks, {resume_id, updated_webhook})
        {:ok, updated_webhook}

      [] ->
        {:error, :webhook_not_found}
    end
  end

  def get_active_webhook(resume_id) do
    case :ets.lookup(:webhooks, resume_id) do
      [{^resume_id, %{status: :active} = webhook}] -> {:ok, webhook}
      [{^resume_id, %{status: status}}] -> {:error, :"webhook_#{status}"}
      [] -> {:error, :webhook_not_found}
    end
  end

  def mark_webhook_consumed(resume_id) do
    case :ets.lookup(:webhooks, resume_id) do
      [{^resume_id, webhook}] ->
        updated = %{webhook | status: :consumed}
        :ets.insert(:webhooks, {resume_id, updated})
        :ok
      [] ->
        {:error, :webhook_not_found}
    end
  end

  def expire_webhooks_for_execution(execution_id) do
    # In production, use database queries for this
    :ets.tab2list(:webhooks)
    |> Enum.filter(fn {_id, webhook} -> webhook.execution_id == execution_id end)
    |> Enum.each(fn {id, webhook} ->
      updated = %{webhook | status: :expired}
      :ets.insert(:webhooks, {id, updated})
    end)
  end
end

# Execution storage
defmodule MyApp.ExecutionStorage do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    table = :ets.new(:executions, [:set, :public, :named_table])
    {:ok, %{table: table}}
  end

  def save_suspended(execution_data) do
    :ets.insert(:executions, {execution_data.execution_id, execution_data})
    :ok
  end

  def get_suspended_execution(execution_id) do
    case :ets.lookup(:executions, execution_id) do
      [{^execution_id, execution}] -> {:ok, execution}
      [] -> {:error, :execution_not_found}
    end
  end

  def mark_completed(execution_id) do
    :ets.delete(:executions, execution_id)
    :ok
  end

  def mark_failed(execution_id, reason) do
    case :ets.lookup(:executions, execution_id) do
      [{^execution_id, execution}] ->
        updated = %{execution | status: "failed", error: reason}
        :ets.insert(:executions, {execution_id, updated})
        :ok
      [] ->
        :ok
    end
  end
end
```

## Usage Examples

### Example 1: Simple Approval Workflow

```bash
# Start approval workflow
curl -X POST http://localhost:4000/webhook/workflow/trigger/approval_workflow \
  -H "Content-Type: application/json" \
  -d '{
    "document_name": "Contract v2.1",
    "approver_email": "manager@company.com"
  }'

# Response: {"status":"suspended","execution_id":"exec_abc123"}

# User clicks approve link in email (GET request)
# GET http://localhost:4000/webhook/workflow/resume/webhook_exec_abc123_wait_approval_xyz?action=approve

# Or programmatic approval (POST request)
curl -X POST http://localhost:4000/webhook/workflow/resume/webhook_exec_abc123_wait_approval_xyz \
  -H "Content-Type: application/json" \
  -d '{"action": "approve", "comments": "Looks good!"}'
```

### Example 2: Payment Confirmation

```elixir
# Payment workflow with webhook wait
payment_workflow = %Prana.Workflow{
  nodes: [
    %Prana.Node{
      id: "initiate_payment",
      integration: "payment",
      action: "create_checkout",
      configuration: %{
        amount: "$input.amount",
        currency: "USD",
        success_url: "https://myapp.com/webhook/workflow/resume/$execution.wait_payment.resume_url?status=success",
        cancel_url: "https://myapp.com/webhook/workflow/resume/$execution.wait_payment.resume_url?status=cancelled"
      }
    },
    %Prana.Node{
      id: "wait_payment",
      integration: "wait",
      action: "wait",
      configuration: %{
        "mode" => "webhook",
        "timeout_hours" => 24
      }
    },
    %Prana.Node{
      id: "process_payment",
      integration: "manual",
      action: "debug_log",
      configuration: %{
        message: "Payment completed: $input.status"
      }
    }
  ]
  # ... connections
}
```

### Example 3: Scheduled Workflow

```elixir
# Schedule workflow to run at specific time
%Prana.Node{
  id: "wait_until_monday",
  integration: "wait",
  action: "wait",
  configuration: %{
    "mode" => "schedule",
    "schedule_at" => "2025-07-07T09:00:00Z"  # Next Monday 9 AM UTC
  }
}
```

### Example 4: Interval-based Workflow

```elixir
# Wait for specific duration
%Prana.Node{
  id: "wait_5_minutes",
  integration: "wait",
  action: "wait",
  configuration: %{
    "mode" => "interval",
    "duration" => 5,
    "unit" => "minutes"
  }
}
```

## Advanced Patterns

### Multiple Wait Nodes

For workflows with multiple approval steps:

```elixir
# Each wait node gets its own resume URL
workflow = %Prana.Workflow{
  nodes: [
    # First approval
    %Prana.Node{
      id: "wait_manager_approval",
      integration: "wait",
      action: "wait",
      configuration: %{"mode" => "webhook", "timeout_hours" => 48}
    },
    # Second approval
    %Prana.Node{
      id: "wait_director_approval",
      integration: "wait",
      action: "wait",
      configuration: %{"mode" => "webhook", "timeout_hours" => 72}
    }
  ]
}

# Resume URLs available as:
# $execution.wait_manager_approval.resume_url
# $execution.wait_director_approval.resume_url
```

### Error Handling

```elixir
def handle_resume(conn, %{"resume_id" => resume_id}) do
  case MyApp.WorkflowEngine.resume_workflow(resume_id, extract_payload(conn)) do
    {:ok, execution_id} ->
      json(conn, %{status: "completed", execution_id: execution_id})

    {:error, "Invalid webhook URL"} ->
      conn |> put_status(404) |> json(%{error: "Webhook not found"})

    {:error, "Webhook has expired"} ->
      conn |> put_status(410) |> json(%{error: "This approval link has expired"})

    {:error, "Webhook already used"} ->
      conn |> put_status(409) |> json(%{error: "This approval has already been processed"})

    {:error, reason} ->
      conn |> put_status(500) |> json(%{error: "Internal error: #{reason}"})
  end
end
```

### Production Considerations

1. **Database Storage**: Replace ETS with persistent database (PostgreSQL, MySQL)
2. **Security**: Add webhook signature validation and authentication
3. **Rate Limiting**: Implement rate limiting for webhook endpoints
4. **Monitoring**: Add logging and metrics for webhook usage
5. **Cleanup**: Implement background job to clean up expired webhooks
6. **Scaling**: Consider webhook storage sharding for high volume

```elixir
# Production webhook storage with database
defmodule MyApp.WebhookStorage do
  import Ecto.Query
  alias MyApp.{Repo, Webhook}

  def create_pending_webhook(resume_id, execution_id, node_id) do
    %Webhook{
      resume_id: resume_id,
      execution_id: execution_id,
      node_id: node_id,
      status: "pending"
    }
    |> Repo.insert()
  end

  def get_active_webhook(resume_id) do
    Webhook
    |> where([w], w.resume_id == ^resume_id and w.status == :active)
    |> Repo.one()
    |> case do
      nil -> {:error, :webhook_not_found}
      webhook -> {:ok, webhook}
    end
  end

  # ... other functions with database queries
end
```

This guide provides a complete foundation for implementing webhook-based wait/resume workflows with Prana. The pattern enables powerful automation scenarios while maintaining clean separation between the workflow engine and application infrastructure.
