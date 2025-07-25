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
          name: "custom.my_action",
          display_name: "My Action",
          description: "Performs custom logic",
          type: :action,
          module: __MODULE__,
          input_ports: ["input"],
          output_ports: ["success", "error"]
        }
      }
    }
  end

  def execute(input, _context) do
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
def execute(input, _context) do
  result = process_data(input)
  {:ok, result}
end
```
- Uses the action's `default_success_port` or first available port
- Most common return format for straightforward operations

#### 2. Simple Error
```elixir
def execute(input, _context) do
  case validate_params(input) do
    :ok -> {:ok, process_data(input)}
    {:error, reason} -> {:error, reason}
  end
end
```

- Error data is wrapped in a structured format by NodeExecutor

#### 3. Explicit Port Selection
```elixir
def execute(input, _context) do
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
def execute(input, _context) do
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
{:suspend, suspension_type, suspension_data}
```

- **`suspension_type`**: Atom identifying the suspension type
- **`suspension_data`**: Map containing data needed to resume the operation

### Resume Data Handling

When a suspended node is resumed, the resume data is processed to extract the actual output data. For sub-workflows, the resume data includes both the workflow output and metadata:

```elixir
# Resume data structure for sub-workflows
resume_data = %{
  "output" => %{         # <- Actual workflow output (extracted)
    "processed_user_id" => 456,
    "status" => "completed"
  },
  "execution_time_ms" => 2500,        # <- Metadata (excluded from node output)
  "workflow_id" => "user_processing"  # <- Metadata (excluded from node output)
}

# The node's output_data will contain only the output:
# %{"processed_user_id" => 456, "status" => "completed"}
```

For custom integrations, if your resume data follows this pattern, the default resume handling will work automatically. If you need custom resume logic, you can override the `resume_node/4` function in your integration module.

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
def execute(input, _context) do
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
  name: "custom.classify_data",
  display_name: "Classify Data",
  description: "Classifies data based on confidence levels",
  type: :action,
  module: __MODULE__,
  input_ports: ["input"],
  output_ports: ["high_confidence", "medium_confidence", "low_confidence", "manual_review", "error"]
}
```

### Dynamic Port Actions

For integrations that need unlimited output routing:

```elixir
%Prana.Action{
  name: "custom.dynamic_router",
  display_name: "Dynamic Router",
  description: "Routes to dynamic ports based on input",
  type: :action,
  module: __MODULE__,
  input_ports: ["input"],
  output_ports: ["*"]  # Allows any port name
}

def execute(input, _context) do
  port_name = determine_route(input)
  {:ok, input, port_name}
end
```

### Error Handling Best Practices

#### Structured Error Returns
```elixir
def execute(input, _context) do
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
def execute(input, _context) do
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

### Enhanced Action Input

Actions receive enriched input that combines both their explicitly mapped data AND full context access. This provides the best of both worlds: explicit data dependencies and flexible context access when needed.

#### Input Structure

```elixir
def execute(input, context) do
  # input contains explicitly mapped data from the node's params
  user_email = input["user_email"]      # From "$input.user.email"
  api_key = input["api_key"]            # From "$variables.api_key"
  prev_result = input["previous_data"]  # From "$nodes.step1.result"

  # context provides full workflow context access
  full_input = context["$input"]      # Complete workflow input
  all_nodes = context["$nodes"]       # All completed node results
  variables = context["$vars"]        # All workflow variables

  # Use explicit data for primary logic
  send_email(to: user_email, api_key: api_key)

  # Use context access for advanced scenarios
  if context["$input"]["debug_mode"] do
    log_debug_info(all_nodes)
  end

  {:ok, %{message_sent: true}}
end
```

#### Example Scenarios

**Scenario 1: Using Explicit Mapping** (Recommended)
```elixir
# Node configuration
%Node{
  id: "send_email",
  params: %{
    "to" => "$input.user.email",
    "subject" => "Welcome!",
    "user_name" => "$input.user.name",
    "api_key" => "$variables.email_api_key"
  }
}

# Action receives
def execute(input, context) do
  # Clean, explicit dependencies
  to = input["to"]                    # "user@example.com"
  subject = input["subject"]          # "Welcome!"
  user_name = input["user_name"]      # "John"
  api_key = input["api_key"]          # "key123"

  # Full context also available if needed
  debug_mode = context["$input"]["debug_mode"]  # Optional debugging

  {:ok, %{message_id: "123", sent_to: to}}
end
```

**Scenario 2: Using Context Access** (For dynamic scenarios)
```elixir
# Node with minimal mapping
%Node{
  id: "dynamic_processor",
  params: %{
    "operation_type" => "$input.operation"
  }
}

# Action uses context for dynamic data access
def execute(input, context) do
  operation = input["operation_type"]  # Explicit mapping

  case operation do
    "user_data" ->
      # Access specific user data from context
      user_data = context["$input"]["user"]
      {:ok, process_user(user_data)}

    "node_results" ->
      # Access all previous node results
      results = context["$nodes"]
      {:ok, aggregate_results(results)}

    "variable_lookup" ->
      # Access workflow variables dynamically
      var_name = context["$input"]["variable_name"]
      value = context["$vars"][var_name]
      {:ok, %{variable: var_name, value: value}}
  end
end
```

### Context Structure

Actions receive two parameters: `input` (prepared parameters) and `context` (full workflow context):

```elixir
# Input parameter - your explicitly mapped data from node params
input = %{
  "user_id" => 123,
  "status" => "active"
}

# Context parameter - full workflow context
context = %{
  "$input" => %{
    # Complete workflow input data
    "user_id" => 123,
    "user" => %{"name" => "John", "email" => "john@example.com"},
    "settings" => %{"theme" => "dark"}
  },
  "$nodes" => %{
    # Results from all completed nodes (keyed by node key)
    "validation_step" => %{"valid" => true, "score" => 95},
    "api_call" => %{"response" => %{"status" => "success"}},
    "transform" => %{"processed_data" => [...]}
  },
  "$vars" => %{
    # All workflow variables
    "api_key" => "secret123",
    "timeout_ms" => 5000,
    "environment" => "production"
  },
  "$workflow" => %{
    "id" => "user_processing_workflow",
    "version" => 1
  },
  "$execution" => %{
    "id" => "exec_123",
    "mode" => :async,
    "state" => %{}  # Shared execution state
  }
}
```

### Input Validation

Validate input data within your actions:

```elixir
def execute(input, _context) do
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
  use ExUnit.Case, async: false

  alias MyApp.CustomIntegration

  test "execute processes input correctly" do
    input = %{"data" => "test"}
    context = %{"$input" => %{}, "$nodes" => %{}, "$vars" => %{}}
    result = CustomIntegration.execute(input, context)

    assert {:ok, %{result: "processed"}} = result
  end

  test "execute handles suspension" do
    input = %{"operation" => "async_task"}
    context = %{"$input" => %{}, "$nodes" => %{}, "$vars" => %{}}
    result = CustomIntegration.execute(input, context)

    assert {:suspend, :custom_suspension, suspension_data} = result
    assert suspension_data.task_id
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
        key: "test_node",
        type: "custom.my_action",
        params: %{"data" => "$input.user_data"}
      }
    ]
  }

  {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "test_node")
  result = GraphExecutor.execute_workflow(execution_graph, %{"user_data" => "test"}, %{})

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
def execute(input, _context) do
  # Instead of loading everything into memory
  result = input["file_path"]
  |> File.stream!()
  |> Stream.map(&process_line/1)
  |> Enum.reduce(%{count: 0}, &accumulate_results/2)

  {:ok, result, "success"}
end
```

### Error Recovery

Design actions to be idempotent when possible, especially for suspended operations:

```elixir
def execute(input, _context) do
  case check_if_already_processed(input["request_id"]) do
    {:ok, existing_result} -> {:ok, existing_result, "success"}
    {:error, :not_found} -> perform_action(input)
  end
end
```

This guide provides the foundation for creating robust, efficient integrations that leverage Prana's full workflow orchestration capabilities.
