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

#### 4. Context and State Updates

Actions can update both workflow-level shared state and node-specific context in a single return:

```elixir
def execute(input, _context) do
  result = process_data(input)

  # Standard return format with state updates
  {:ok, result, "success", %{
    # Workflow shared state updates (accessible via $execution.state)
    "shared_state_key" => "value",
    "user_session" => %{"role" => "admin"},
    "batch_counter" => 15,

    # Node context updates (accessible via $nodes[node_key].context)
    "node_context" => %{
      "loop_index" => 3,
      "is_loop_back" => true,
      "processing_time_ms" => 150,
      "custom_metadata" => "any_data"
    }
  }}
end
```

**Return Format Variants:**
- `{:ok, data}` - Simple success
- `{:ok, data, port}` - Success with explicit port
- `{:ok, data, state_updates}` - Success with state updates (uses default success port)
- `{:ok, data, port, state_updates}` - Success with port and state updates

#### 5. Suspension for Async Operations
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

#### Understanding Retry Behavior

Prana's retry mechanism automatically retries failed nodes that return action errors. **All action errors are retryable** - the retry decision is made at the workflow level through node settings, not based on error classification.

**Required Error Format**: Actions **MUST** return errors using the `Prana.Core.Error.action_error/3` helper function.

**Unified Error Return Format**:
```elixir
{:error, Prana.Core.Error.action_error(error_type, message, details)}
```

#### Action Error Returns (Unified Format)
```elixir
def execute(input, _context) do
  case perform_operation(input) do
    {:ok, result} ->
      {:ok, result}

    # Network/timeout errors
    {:error, :network_timeout} ->
      {:error, Prana.Core.Error.action_error("timeout", "Network timeout during API call", %{timeout_ms: 5000})}

    {:error, :connection_refused} ->
      {:error, Prana.Core.Error.action_error("network_error", "Connection refused by remote server", %{host: "api.example.com", port: 443})}

    # Unknown errors
    {:error, reason} ->
      {:error, Prana.Core.Error.action_error("unknown_error", "Unexpected error occurred", %{original_reason: reason})}
  end
end
```

**Important Notes**:
- **All action errors are retryable** by the engine - retry control is managed through node settings
- The `error_type` (first parameter) is stored in `details["error_type"]` for categorization and logging
- Never create `%Prana.Core.Error{}` structs directly - always use the `action_error/3` helper
- The error gets wrapped by NodeExecutor into an `"action_error"` code for engine processing

#### Integration-Specific Retry Examples

**HTTP Integration**:
```elixir
defmodule MyApp.HTTPIntegration do
  def request(params, _context) do
    case HTTPClient.get(params["url"]) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, %{status: "success", data: body}}

      {:ok, %{status: 429}} ->
        # Rate limited
        {:error, %Prana.Core.Error{
          code: "rate_limit",
          message: "Rate limit exceeded",
          details: %{status_code: 429}
        }}

      {:ok, %{status: 500}} ->
        # Server error
        {:error, %Prana.Core.Error{
          code: "service_unavailable",
          message: "Internal server error",
          details: %{status_code: 500}
        }}

      {:ok, %{status: 401}} ->
        # Authentication error
        {:error, %Prana.Core.Error{
          code: "authentication_error",
          message: "Unauthorized access",
          details: %{status_code: 401}
        }}

      {:ok, %{status: 400}} ->
        # Bad request
        {:error, %Prana.Core.Error{
          code: "validation_error",
          message: "Bad request format",
          details: %{status_code: 400}
        }}

      {:error, :timeout} ->
        # Network timeout
        {:error, %Prana.Core.Error{
          code: "timeout",
          message: "Request timeout",
          details: %{timeout_ms: 30000}
        }}

      {:error, :nxdomain} ->
        # DNS error
        {:error, %Prana.Core.Error{
          code: "network_error",
          message: "DNS resolution failed",
          details: %{domain: params["url"]}
        }}
    end
  end
end
```

**Database Integration**:
```elixir
defmodule MyApp.DatabaseIntegration do
  def query(params, _context) do
    case Database.execute(params["query"]) do
      {:ok, result} ->
        {:ok, %{rows: result.rows, count: result.num_rows}}

      {:error, :connection_lost} ->
        # Connection issues
        {:error, %Prana.Core.Error{
          code: "network_error",
          message: "Database connection lost",
          details: %{reconnect_recommended: true}
        }}

      {:error, :timeout} ->
        # Query timeout
        {:error, %Prana.Core.Error{
          code: "timeout",
          message: "Query execution timeout",
          details: %{query_timeout_ms: 30000}
        }}

      {:error, :syntax_error} ->
        # SQL syntax error
        {:error, %Prana.Core.Error{
          code: "validation_error",
          message: "Invalid SQL syntax",
          details: %{query: params["query"]}
        }}

      {:error, :permission_denied} ->
        # Access denied
        {:error, %Prana.Core.Error{
          code: "authorization_error",
          message: "Insufficient database permissions",
          details: %{required_permission: "SELECT"}
        }}
    end
  end
end
```

#### Error Classification Guidelines

**RETRYABLE Errors** (use these codes):
- `"network_error"` - Connection issues, DNS failures
- `"timeout"` - Request/operation timeouts
- `"service_unavailable"` - 5xx HTTP errors, service down
- `"rate_limit"` - 429 HTTP errors, quota exceeded
- `"unknown_error"` - Unexpected errors that might be transient

**NON-RETRYABLE Errors** (use these codes):
- `"validation_error"` - 400 HTTP errors, invalid input format
- `"authentication_error"` - 401 HTTP errors, invalid credentials
- `"authorization_error"` - 403 HTTP errors, insufficient permissions
- `"not_found"` - 404 HTTP errors, resource doesn't exist
- `"invalid_input"` - Schema validation failures, malformed data

#### Testing Retry Behavior

```elixir
defmodule MyIntegrationTest do
  test "returns retryable error for network timeout" do
    # Mock network timeout
    expect(HTTPClient, :get, fn _ -> {:error, :timeout} end)

    result = MyIntegration.execute(%{"url" => "http://example.com"}, %{})

    # Should return Prana.Core.Error with retryable code
    assert {:error, %Prana.Core.Error{code: "timeout"}} = result

    # Verify this error will be retried by the engine
    assert Prana.NodeExecutor.is_retryable_error?(elem(result, 1))
  end

  test "returns non-retryable error for authentication failure" do
    # Mock auth failure
    expect(HTTPClient, :get, fn _ -> {:ok, %{status: 401}} end)

    result = MyIntegration.execute(%{"url" => "http://example.com"}, %{})

    # Should return non-retryable error
    assert {:error, %Prana.Core.Error{code: "authentication_error"}} = result

    # Verify this error will NOT be retried
    refute Prana.NodeExecutor.is_retryable_error?(elem(result, 1))
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

## Node Context and State Updates

Prana provides two mechanisms for actions to update state during execution:

### 1. Node Context Updates

Actions can update their own node's context, which becomes accessible to other nodes in the workflow. This is perfect for loop tracking, metadata, and inter-node communication.

```elixir
def execute(input, context) do
  # Calculate loop information
  current_node = context["$execution"]["current_node_key"]
  loop_iteration = calculate_iteration(context, current_node)

  result = process_input(input)

  # Return with node context updates
  {:ok, result, "success", %{
    "node_context" => %{
      "loop_index" => loop_iteration,
      "is_loop_back" => loop_iteration > 0,
      "processing_metadata" => %{
        "duration_ms" => 250,
        "items_processed" => 42
      }
    }
  }}
end
```

**Accessing Node Context from Other Nodes:**

```elixir
# In templates or other actions
"$nodes['loop_node'].context.loop_index"        # => 3
"$nodes['loop_node'].context.is_loop_back"      # => true
"$nodes['loop_node'].context.processing_metadata.duration_ms"  # => 250
```

### 2. Workflow Shared State Updates

Actions can update workflow-level shared state that persists across node executions and is accessible via `$execution.state`:

```elixir
def execute(input, context) do
  result = process_input(input)

  # Update both node context AND shared workflow state
  {:ok, result, "success", %{
    # Workflow-level shared state (persists across all nodes)
    "user_session" => %{"authenticated" => true, "role" => "admin"},
    "batch_counter" => 15,
    "temp_data" => input["processing_cache"],

    # Node-specific context (tied to this node only)
    "node_context" => %{
      "local_metadata" => "node-specific data"
    }
  }}
end
```

**Accessing Shared State:**

```elixir
# In templates or other actions
"$execution.state.user_session.role"     # => "admin"
"$execution.state.batch_counter"         # => 15
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
    "validation_step" => %{
      "output" => %{"valid" => true, "score" => 95},
      "context" => %{}  # Node-specific context (empty if none set)
    },
    "api_call" => %{
      "output" => %{"response" => %{"status" => "success"}},
      "context" => %{"retry_count" => 2, "response_time_ms" => 150}
    },
    "loop_processor" => %{
      "output" => %{"processed_items" => [...]},
      "context" => %{
        "loop_index" => 3,
        "is_loop_back" => true,
        "total_iterations" => 5
      }
    }
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
    assert suspension_data["task_id"]
  end

  test "execute returns node context updates" do
    input = %{"data" => "test"}
    context = %{
      "$input" => %{},
      "$nodes" => %{},
      "$vars" => %{},
      "$execution" => %{"current_node_key" => "test_node"}
    }

    result = CustomIntegration.execute(input, context)

    assert {:ok, %{result: "processed"}, "success", state_updates} = result
    assert %{"node_context" => node_context} = state_updates
    assert node_context["loop_index"]
    assert is_boolean(node_context["is_loop_back"])
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
