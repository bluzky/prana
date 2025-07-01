# Writing Integrations Guide

This guide explains how to create custom integrations for Prana workflows. Integrations provide actions that nodes can execute, from simple data transformations to complex async operations like sub-workflows.

## Integration Structure

Every integration implements the `Prana.Behaviour.Integration` behavior and provides a definition containing available actions.

### Basic Integration Template

```elixir
defmodule MyApp.CustomIntegration do
  @behaviour Prana.Behaviour.Integration

  def definition do
    %Prana.Integration{
      name: "custom",
      display_name: "Custom Integration",
      description: "Custom actions for workflows",
      actions: %{
        "my_action" => %Prana.Action{
          name: "my_action",
          display_name: "My Action",
          description: "Performs custom logic",
          module: __MODULE__,
          function: :my_action,
          input_ports: ["input"],
          output_ports: ["success", "error"],
          default_success_port: "success",
          default_error_port: "error"
        }
      }
    }
  end

  def my_action(input) do
    # Your action implementation here
    {:ok, %{result: "processed"}}
  end
end
```

## Action Return Formats

Actions must return specific tuple formats that Prana understands. The NodeExecutor processes these returns to determine execution flow.

### Standard Return Formats

#### 1. Simple Success
```elixir
def my_action(input) do
  result = process_data(input)
  {:ok, result}
end
```
- Uses the action's `default_success_port` or first available port
- Most common return format for straightforward operations

#### 2. Simple Error
```elixir
def my_action(input) do
  case validate_input(input) do
    :ok -> {:ok, process_data(input)}
    {:error, reason} -> {:error, reason}
  end
end
```
- Uses the action's `default_error_port` or "error" port
- Error data is wrapped in a structured format by NodeExecutor

#### 3. Explicit Port Selection
```elixir
def my_action(input) do
  case input["operation_type"] do
    "create" -> {:ok, create_result, "created"}
    "update" -> {:ok, update_result, "updated"} 
    "delete" -> {:ok, delete_result, "deleted"}
    invalid -> {:error, "Unknown operation", "invalid_input"}
  end
end
```
- Allows routing to specific output ports
- Enables complex conditional workflow patterns
- Port must be listed in the action's `output_ports`

#### 4. Suspension for Async Operations
```elixir
def execute_sub_workflow(input) do
  # Validate and prepare sub-workflow execution
  case setup_sub_workflow(input) do
    {:ok, workflow_data} ->
      # Return suspension tuple to pause execution
      {:suspend, :sub_workflow_sync, workflow_data}
    
    {:error, reason} ->
      {:error, reason}
  end
end
```

## Suspension System

The suspension system allows actions to pause workflow execution for async operations like sub-workflows, external API calls, or time delays.

### Suspension Tuple Format

```elixir
{:suspend, suspension_type, suspend_data}
```

- **`suspension_type`**: Atom identifying the suspension type
- **`suspend_data`**: Map containing data needed to resume the operation

### Built-in Suspension Types

#### Sub-workflow Coordination

**`:sub_workflow_sync`** - Synchronous sub-workflow execution
```elixir
{:suspend, :sub_workflow_sync, %{
  workflow_id: "child_workflow_id",
  input_data: %{"user_id" => 123},
  execution_mode: "sync",
  timeout_ms: 300_000,
  failure_strategy: "fail_parent"
}}
```

**`:sub_workflow_async`** - Asynchronous sub-workflow execution
```elixir
{:suspend, :sub_workflow_async, %{
  workflow_id: "background_task",
  input_data: %{"task" => "cleanup"},
  execution_mode: "async",
  callback_url: "https://api.example.com/webhooks/workflow"
}}
```

**`:sub_workflow_fire_forget`** - Fire-and-forget execution
```elixir
{:suspend, :sub_workflow_fire_forget, %{
  workflow_id: "notification_flow",
  input_data: %{"message" => "Hello"},
  execution_mode: "fire_and_forget"
}}
```


### Custom Suspension Types

You can define custom suspension types for domain-specific async patterns. These would require custom resume logic in your application:

```elixir
def wait_for_approval(input) do
  approval_request = create_approval_request(input)
  
  {:suspend, :approval_required, %{
    approval_id: approval_request.id,
    approver_email: input["approver"],
    request_data: input["data"]
  }}
end
```

## Advanced Integration Patterns

### Multi-Port Actions

Create actions with multiple output ports for complex routing:

```elixir
def classify_data(input) do
  confidence = calculate_confidence(input["data"])
  
  cond do
    confidence > 0.9 -> {:ok, input["data"], "high_confidence"}
    confidence > 0.7 -> {:ok, input["data"], "medium_confidence"} 
    confidence > 0.5 -> {:ok, input["data"], "low_confidence"}
    true -> {:ok, input["data"], "manual_review"}
  end
end
```

Action definition:
```elixir
%Prana.Action{
  name: "classify_data",
  # ... other fields
  output_ports: ["high_confidence", "medium_confidence", "low_confidence", "manual_review", "error"]
}
```

### Dynamic Port Actions

For integrations that need unlimited output routing:

```elixir
%Prana.Action{
  name: "dynamic_router",
  # ... other fields
  output_ports: ["*"]  # Allows any port name
}

def dynamic_router(input) do
  port_name = determine_route(input)
  {:ok, input, port_name}
end
```

### Error Handling Best Practices

#### Structured Error Returns
```elixir
def risky_operation(input) do
  case perform_operation(input) do
    {:ok, result} -> 
      {:ok, result}
    
    {:error, :network_timeout} -> 
      {:error, %{type: "timeout", retryable: true}, "retry"}
    
    {:error, :invalid_credentials} -> 
      {:error, %{type: "auth_error", retryable: false}, "auth_failed"}
    
    {:error, reason} -> 
      {:error, %{type: "unknown", reason: reason}, "error"}
  end
end
```

#### Graceful Degradation
```elixir
def fetch_with_fallback(input) do
  case primary_fetch(input) do
    {:ok, data} -> {:ok, data, "primary"}
    {:error, _} ->
      case fallback_fetch(input) do
        {:ok, data} -> {:ok, data, "fallback"}
        {:error, reason} -> {:error, reason, "failed"}
      end
  end
end
```

## Input Processing

### Expression Engine Integration

Actions automatically receive processed input where expressions like `$input.field` and `$nodes.previous.result` are evaluated:

```elixir
def send_notification(input) do
  # input["user_email"] already contains the resolved value from "$input.user.email"
  # input["api_key"] already contains the resolved value from "$variables.api_key"
  
  result = send_email(
    to: input["user_email"],
    subject: input["subject"],
    body: input["body"],
    api_key: input["api_key"]
  )
  
  case result do
    {:ok, message_id} -> {:ok, %{message_id: message_id}}
    {:error, reason} -> {:error, reason}
  end
end
```

### Input Validation

Validate input data within your actions:

```elixir
def validate_and_process(input) do
  with :ok <- validate_required_fields(input),
       :ok <- validate_data_types(input),
       {:ok, processed} <- process_data(input) do
    {:ok, processed}
  else
    {:error, reason} -> {:error, reason}
  end
end

defp validate_required_fields(input) do
  required = ["user_id", "action_type"]
  missing = required -- Map.keys(input)
  
  if Enum.empty?(missing) do
    :ok
  else
    {:error, "Missing required fields: #{Enum.join(missing, ", ")}"}
  end
end
```

## Registration and Testing

### Register Your Integration

```elixir
# In your application startup
{:ok, _registry} = Prana.IntegrationRegistry.start_link()
:ok = Prana.IntegrationRegistry.register_integration(MyApp.CustomIntegration)
```

### Testing Actions

```elixir
defmodule MyApp.CustomIntegrationTest do
  use ExUnit.Case, async: true
  
  alias MyApp.CustomIntegration

  test "my_action processes input correctly" do
    input = %{"data" => "test"}
    result = CustomIntegration.my_action(input)
    
    assert {:ok, %{result: "processed"}} = result
  end

  test "my_action handles suspension" do
    input = %{"operation" => "async_task"}
    result = CustomIntegration.my_action(input)
    
    assert {:suspend, :custom_suspension, suspend_data} = result
    assert suspend_data.task_id
  end
end
```

### Integration with GraphExecutor

Test your integration within complete workflows:

```elixir
test "integration works in workflow" do
  workflow = %Workflow{
    nodes: [
      %Node{
        id: "test_node",
        integration_name: "custom",
        action_name: "my_action",
        input_map: %{"data" => "$input.user_data"}
      }
    ]
  }
  
  {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "test_node")
  result = GraphExecutor.execute_graph(execution_graph, %{"user_data" => "test"}, %{})
  
  assert {:ok, completed_execution} = result
end
```

## Built-in Integration Examples

Study the existing integrations for patterns and best practices:

- **Manual Integration** (`lib/prana/integrations/manual.ex`) - Simple test actions and triggers
- **Logic Integration** (`lib/prana/integrations/logic.ex`) - Conditional branching with IF/ELSE and switch patterns
- **Workflow Integration** (`lib/prana/integrations/workflow.ex`) - Sub-workflow orchestration with suspension/resume
- **Data Integration** (`lib/prana/integrations/data.ex`) - Data merging and combination operations

See the [Built-in Integrations Guide](../built-in-integrations.md) for detailed documentation of all available actions and usage patterns.

## Performance Considerations

### Efficient Action Implementation

1. **Minimize blocking operations** in actions - use suspension for long-running tasks
2. **Process input efficiently** - the expression engine has already resolved expressions
3. **Return appropriate data sizes** - large outputs affect workflow state size
4. **Use timeouts** for external API calls

### Memory Management

```elixir
def process_large_dataset(input) do
  # Instead of loading everything into memory
  input["file_path"]
  |> File.stream!()
  |> Stream.map(&process_line/1)
  |> Enum.reduce(%{count: 0}, &accumulate_results/2)
  |> then(&{:ok, &1})
end
```

### Error Recovery

Design actions to be idempotent when possible, especially for suspended operations:

```elixir
def idempotent_action(input) do
  case check_if_already_processed(input["request_id"]) do
    {:ok, existing_result} -> {:ok, existing_result}
    {:error, :not_found} -> perform_action(input)
  end
end
```

This guide provides the foundation for creating robust, efficient integrations that leverage Prana's full workflow orchestration capabilities.