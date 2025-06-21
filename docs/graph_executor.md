# Prana GraphExecutor Documentation

## Overview

The **GraphExecutor** is the core orchestration engine of Prana that executes workflows by coordinating multiple nodes, managing data flow, handling parallel execution, and providing comprehensive error recovery including retry mechanisms.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Core Concepts](#core-concepts)
3. [Execution Patterns](#execution-patterns)
4. [API Reference](#api-reference)
5. [Execution Planning](#execution-planning)
6. [Data Flow & Routing](#data-flow--routing)
7. [Error Handling & Retry](#error-handling--retry)
8. [Event System](#event-system)
9. [Performance Considerations](#performance-considerations)
10. [Usage Examples](#usage-examples)
11. [Testing Guide](#testing-guide)
12. [Troubleshooting](#troubleshooting)

## Architecture Overview

### Component Diagram

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Workflow      │    │  Graph Executor  │    │  Node Executor  │
│   (Definition)  │───▶│  (Orchestrator)  │───▶│  (Individual)   │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                              │                         │
                              ▼                         ▼
                       ┌──────────────────┐    ┌─────────────────┐
                       │   Middleware     │    │ Expression      │
                       │   (Events)       │    │ Engine          │
                       └──────────────────┘    └─────────────────┘
```

### Design Principles

- **Separation of Concerns**: GraphExecutor orchestrates, NodeExecutor handles individual execution
- **Event-Driven**: Comprehensive middleware event emission for observability
- **Fault Tolerant**: Robust error handling with configurable retry strategies
- **Performance Optimized**: Task-based parallel execution with resource management
- **Type Safe**: All operations use proper Elixir structs with compile-time checking

## Core Concepts

### ExecutionPlan

The execution plan contains the analysis and strategy for workflow execution:

```elixir
%ExecutionPlan{
  workflow: workflow,              # Original workflow definition
  entry_nodes: [node1, node2],     # Nodes with no dependencies
  dependency_graph: %{             # Node dependency relationships
    "node_2" => ["node_1"],
    "node_3" => ["node_1", "node_2"]
  },
  connection_map: %{               # Port-based connection lookup
    {"node_1", "success"} => [conn1, conn2]
  },
  node_map: %{                     # Quick node lookup
    "node_1" => node1_struct
  },
  total_nodes: 3
}
```

### ExecutionContext

Shared state maintained throughout workflow execution:

```elixir
%ExecutionContext{
  execution_id: "exec_123",
  workflow: workflow_struct,
  execution: execution_struct,
  nodes: %{                        # Node results by custom_id
    "api_call" => %{"status" => 200},
    "transform" => %{"result" => "processed"}
  },
  variables: %{"api_url" => "https://api.com"},
  input: %{"user_id" => 123},
  pending_nodes: #MapSet<["node_2"]>,
  completed_nodes: #MapSet<["node_1"]>,
  failed_nodes: #MapSet<[]>,
  metadata: %{                     # Execution metadata
    node_outputs: %{},             # Output port tracking
    routed_data: %{},              # Inter-node data routing
    execution_stats: %{},          # Performance metrics
    retry_info: %{}                # Retry tracking
  }
}
```

## Execution Patterns

The GraphExecutor supports five core execution patterns:

### 1. Sequential Execution

```
[A] → [B] → [C] → [D]
```

**Characteristics**:
- Each node waits for previous completion
- Data flows through default success ports
- Simple error propagation

### 2. Conditional Branching

```
[Input] → [IF] → [Success Path] → [Output]
            ↓ false
        [Error Path] → [Error Output]
```

**Characteristics**:
- Port-based routing (true/false, success/error)
- Different execution paths based on conditions
- Conditional data transformation

### 3. Fan-out/Fan-in Parallel

```
[Input] → [A] ↘
       ↘ [B] → [Merge] → [Output]
       ↘ [C] ↗
```

**Characteristics**:
- Parallel data collection and processing
- Synchronization point (merge node)
- Task-based concurrent execution

### 4. Error Routing

```
[Action] → [Success Path] → [Output]
    ↓ error
[Error Handler] → [Error Output]
```

**Characteristics**:
- Automatic error port routing
- Graceful error recovery
- Error-specific processing

### 5. Wait/Suspension

```
[Action] → [Wait] → [Resume] → [Continue]
```

**Characteristics**:
- Workflow suspension for external events
- Resume token management
- State preservation across suspension

## API Reference

### Main Functions

#### `execute_workflow/3`

Execute a workflow synchronously.

```elixir
@spec execute_workflow(Workflow.t(), map(), keyword()) :: execution_result()
```

**Parameters**:
- `workflow` - Workflow definition to execute
- `input_data` - Initial input data map
- `opts` - Execution options

**Returns**:
- `{:ok, context}` - Successful completion with final context
- `{:error, reason}` - Execution failed with error details
- `{:suspended, context}` - Workflow suspended, can be resumed

#### `execute_workflow_async/3`

Execute a workflow asynchronously using Tasks.

```elixir
@spec execute_workflow_async(Workflow.t(), map(), keyword()) :: {:ok, Task.t()} | {:error, term()}
```

#### `resume_workflow/2`

Resume a suspended workflow execution.

```elixir
@spec resume_workflow(Execution.t(), String.t()) :: execution_result()
```

## Execution Planning

### Workflow Analysis

Before execution, GraphExecutor analyzes the workflow structure:

1. **Validation** - Ensures workflow is structurally valid
2. **Dependency Analysis** - Builds dependency graph from connections
3. **Entry Point Detection** - Identifies nodes with no incoming connections
4. **Connection Mapping** - Creates efficient port-based lookup maps

### Ready Node Detection

Nodes are ready for execution when:
1. **Not already executed** - Not in completed or failed sets
2. **Not currently pending** - Not currently being executed
3. **Dependencies satisfied** - All prerequisite nodes completed successfully
4. **Valid connection path** - Incoming connections have proper output ports

## Data Flow & Routing

### Port-Based Routing

Data flows between nodes through explicit named ports:

```elixir
# Node produces output on "success" port
{:ok, data, "success"}

# Connection routes from "success" port to "input" port
%Connection{
  from_node_id: "node_1",
  from_port: "success",
  to_node_id: "node_2", 
  to_port: "input"
}
```

### Data Mapping

Connections can transform data using expressions:

```elixir
%Connection{
  from_node_id: "api_call",
  from_port: "success",
  to_node_id: "transform",
  to_port: "input",
  data_mapping: %{
    "user_data" => "$output.user",
    "timestamp" => "$variables.current_time",
    "source" => "api_response"
  }
}
```

## Error Handling & Retry

### Retry Policies

Comprehensive retry configuration:

```elixir
%RetryPolicy{
  max_attempts: 3,                    # Maximum retry attempts
  backoff_strategy: :exponential,     # :fixed, :linear, :exponential
  initial_delay_ms: 1000,            # Initial delay
  max_delay_ms: 30_000,              # Maximum delay cap
  backoff_multiplier: 2.0,           # Multiplier for exponential/linear
  retry_on_errors: ["timeout", "network"], # Filter specific error types
  jitter: true                       # Add random jitter to delays
}
```

### Backoff Strategies

#### Fixed Delay
```elixir
delay = initial_delay_ms  # Always 1000ms
```

#### Linear Backoff  
```elixir
delay = initial_delay_ms * (retry_count + 1)
# Attempts: 1000ms, 2000ms, 3000ms...
```

#### Exponential Backoff
```elixir
delay = initial_delay_ms * (backoff_multiplier ^ retry_count)
# Attempts: 1000ms, 2000ms, 4000ms, 8000ms...
```

## Event System

### Lifecycle Events

The GraphExecutor emits comprehensive events for observability:

#### Workflow Events
- `:execution_started` - Workflow execution begins
- `:execution_completed` - Workflow completes successfully  
- `:execution_failed` - Workflow fails permanently
- `:execution_suspended` - Workflow suspended for external action

#### Node Events
- `:node_started` - Individual node execution begins
- `:node_completed` - Node completes successfully
- `:node_failed` - Node fails (may be retried)

#### Retry Events
- `:node_retry_delay` - Before retry delay
- `:node_retry_started` - Retry attempt begins
- `:node_retry_succeeded` - Retry succeeds
- `:node_retry_failed` - Retry fails (may retry again)

## Performance Considerations

### Parallel Execution

- **Task-based concurrency** - Uses Elixir Tasks for true parallelism
- **Intelligent batching** - Groups ready nodes for parallel execution
- **Resource management** - Configurable timeouts and task supervision
- **Single node optimization** - Bypasses Task overhead for single nodes

### Memory Management

- **Efficient context updates** - Minimal memory copying
- **Metadata storage** - Organized execution information
- **Result caching** - Node results stored by custom_id
- **Cleanup** - Proper task termination on failures

## Usage Examples

### Basic Sequential Workflow

```elixir
# Create workflow
workflow = Workflow.new("User Processing", "Process new user registration")

# Add nodes
fetch_node = Node.new("Fetch User", :action, "http", "get", %{
  "url" => "$input.user_url"
}, "fetch_user")

process_node = Node.new("Process Data", :action, "transform", "extract", %{
  "source" => "$nodes.fetch_user.data",
  "fields" => ["id", "email", "name"]
}, "process_data")

save_node = Node.new("Save User", :action, "database", "insert", %{
  "table" => "users",
  "data" => "$nodes.process_data.result"
}, "save_user")

# Add nodes to workflow
workflow = workflow
  |> Workflow.add_node!(fetch_node)
  |> Workflow.add_node!(process_node) 
  |> Workflow.add_node!(save_node)

# Create connections
conn1 = Connection.new(fetch_node.id, "success", process_node.id, "input")
conn2 = Connection.new(process_node.id, "success", save_node.id, "input")

# Add connections
{:ok, workflow} = Workflow.add_connection(workflow, conn1)
{:ok, workflow} = Workflow.add_connection(workflow, conn2)

# Execute
input_data = %{"user_url" => "https://api.example.com/users/123"}
{:ok, context} = GraphExecutor.execute_workflow(workflow, input_data)
```

### Parallel Data Collection

```elixir
# Create workflow with parallel data collection
workflow = Workflow.new("Data Aggregation", "Collect data from multiple sources")

# Input processing
input_node = Node.new("Process Input", :action, "transform", "extract", %{
  "source" => "$input",
  "field" => "user_id"
}, "process_input")

# Parallel data fetching
user_node = Node.new("Fetch User", :action, "http", "get", %{
  "url" => "$input.user_service_url"
}, "fetch_user")

orders_node = Node.new("Fetch Orders", :action, "http", "get", %{
  "url" => "$input.order_service_url"
}, "fetch_orders")

settings_node = Node.new("Fetch Settings", :action, "http", "get", %{
  "url" => "$input.settings_service_url"
}, "fetch_settings")

# Merge results
merge_node = Node.new("Merge Data", :action, "transform", "merge", %{
  "sources" => [
    "$nodes.fetch_user.data",
    "$nodes.fetch_orders.data",
    "$nodes.fetch_settings.data"
  ]
}, "merge_data")

# Add all nodes
nodes = [input_node, user_node, orders_node, settings_node, merge_node]
workflow = Enum.reduce(nodes, workflow, &Workflow.add_node!(&2, &1))

# Create fan-out connections (input to parallel nodes)
fan_out = [
  Connection.new(input_node.id, "success", user_node.id, "input"),
  Connection.new(input_node.id, "success", orders_node.id, "input"),
  Connection.new(input_node.id, "success", settings_node.id, "input")
]

# Create fan-in connections (parallel nodes to merge)
fan_in = [
  Connection.new(user_node.id, "success", merge_node.id, "input"),
  Connection.new(orders_node.id, "success", merge_node.id, "input"), 
  Connection.new(settings_node.id, "success", merge_node.id, "input")
]

# Add all connections
all_connections = fan_out ++ fan_in
workflow = Enum.reduce(all_connections, workflow, fn conn, acc ->
  {:ok, updated} = Workflow.add_connection(acc, conn)
  updated
end)

# Execute with parallel processing
input_data = %{
  "user_id" => 123,
  "user_service_url" => "https://users.api.com/123",
  "order_service_url" => "https://orders.api.com/user/123",
  "settings_service_url" => "https://settings.api.com/user/123"
}

{:ok, context} = GraphExecutor.execute_workflow(workflow, input_data)
final_result = context.nodes["merge_data"]
```

### Error Handling with Retry

```elixir
# Create node with retry policy
retry_policy = %RetryPolicy{
  max_attempts: 3,
  backoff_strategy: :exponential,
  initial_delay_ms: 1000,
  backoff_multiplier: 2.0,
  retry_on_errors: ["timeout", "connection_error"],
  jitter: true
}

api_node = Node.new("Unreliable API", :action, "http", "get", %{
  "url" => "$input.api_url",
  "timeout" => 5000
}, "api_call")

# Set retry policy
api_node = %{api_node | retry_policy: retry_policy}

# Error handler
error_node = Node.new("Handle Error", :action, "log", "error", %{
  "message" => "API call failed after retries",
  "error_data" => "$nodes.api_call.error"
}, "error_handler")

# Success handler  
success_node = Node.new("Process Success", :action, "transform", "extract", %{
  "source" => "$nodes.api_call.data",
  "field" => "result"
}, "process_success")

# Add nodes
workflow = workflow
  |> Workflow.add_node!(api_node)
  |> Workflow.add_node!(error_node)
  |> Workflow.add_node!(success_node)

# Connect success and error paths
success_conn = Connection.new(api_node.id, "success", success_node.id, "input")
error_conn = Connection.new(api_node.id, "error", error_node.id, "input")

{:ok, workflow} = Workflow.add_connection(workflow, success_conn)
{:ok, workflow} = Workflow.add_connection(workflow, error_conn)

# Execute - will retry on failures
input_data = %{"api_url" => "https://unreliable-api.com/data"}
{:ok, context} = GraphExecutor.execute_workflow(workflow, input_data)
```

## Testing Guide

### Unit Testing

```elixir
defmodule MyApp.GraphExecutorTest do
  use ExUnit.Case, async: true
  
  alias Prana.{GraphExecutor, Workflow, Node, Connection}
  
  describe "execute_workflow/3" do
    test "executes simple sequential workflow" do
      workflow = create_test_workflow()
      input_data = %{"test_data" => "value"}
      
      assert {:ok, context} = GraphExecutor.execute_workflow(workflow, input_data)
      assert context.execution.status == :completed
      assert MapSet.size(context.completed_nodes) == 2
    end
    
    test "handles node failures gracefully" do
      workflow = create_failing_workflow()
      input_data = %{}
      
      case GraphExecutor.execute_workflow(workflow, input_data) do
        {:ok, context} -> 
          assert MapSet.size(context.failed_nodes) > 0
        {:error, reason} ->
          assert reason != nil
      end
    end
  end
end
```

### Performance Testing

```elixir
defmodule MyApp.PerformanceTest do
  use ExUnit.Case
  
  test "handles large parallel workflows efficiently" do
    workflow = create_large_parallel_workflow(50) # 50 parallel nodes
    input_data = %{"batch_id" => "perf_test"}
    
    {time_microseconds, result} = :timer.tc(fn ->
      GraphExecutor.execute_workflow(workflow, input_data)
    end)
    
    assert {:ok, context} = result
    
    # Should complete within reasonable time
    time_ms = div(time_microseconds, 1000)
    assert time_ms < 10_000  # Less than 10 seconds
    
    # Check parallel efficiency
    stats = get_in(context.metadata, [:execution_stats])
    parallel_efficiency = stats[:total_duration_ms] / time_ms
    assert parallel_efficiency > 5.0  # At least 5x parallel speedup
  end
end
```

## Troubleshooting

### Common Issues

#### Workflow Deadlock

**Symptoms**: Workflow never completes, no nodes are ready for execution

**Debugging**:
```elixir
# Check for ready nodes
ready_nodes = find_ready_nodes(plan, context)
IO.inspect(ready_nodes, label: "Ready Nodes")

# Check dependency satisfaction
node = get_stuck_node(workflow)
deps_satisfied = dependencies_satisfied?(plan, context, node)
IO.inspect(deps_satisfied, label: "Dependencies Satisfied")
```

**Solutions**:
- Validate workflow structure before execution
- Ensure all nodes have valid connection paths
- Check for circular dependencies

#### Memory Issues

**Symptoms**: High memory usage, out of memory errors

**Solutions**:
```elixir
# Limit parallel execution
config :prana, max_parallel_nodes: 10

# Monitor memory usage in middleware
defmodule MemoryMonitoringMiddleware do
  def call(:batch_execution_started, data, next) do
    :erlang.garbage_collect()
    memory = :erlang.memory(:total)
    Logger.info("Memory usage: #{div(memory, 1024 * 1024)}MB")
    next.(data)
  end
end
```

#### Performance Issues

**Optimization**:
```elixir
# Profile execution timing
defmodule ProfilingMiddleware do
  def call(:node_started, data, next) do
    start_time = :os.system_time(:microsecond)
    Process.put(:node_start_time, start_time)
    next.(data)
  end
  
  def call(:node_completed, data, next) do
    start_time = Process.get(:node_start_time)
    end_time = :os.system_time(:microsecond)
    duration = div(end_time - start_time, 1000)
    
    Logger.info("Node #{data.node_name} executed in #{duration}ms")
    next.(data)
  end
end
```

### Monitoring and Observability

#### Metrics Collection

```elixir
defmodule MetricsMiddleware do
  @behaviour Prana.Behaviour.Middleware
  
  def call(:execution_started, data, next) do
    :telemetry.execute([:prana, :workflow, :started], %{count: 1}, %{
      workflow_id: data.workflow_id,
      workflow_name: data.workflow_name
    })
    next.(data)
  end
  
  def call(:execution_completed, data, next) do
    :telemetry.execute([:prana, :workflow, :completed], %{
      duration: data.duration_ms,
      count: 1
    }, %{
      workflow_id: data.workflow_id
    })
    next.(data)
  end
  
  def call(:node_retry_started, data, next) do
    :telemetry.execute([:prana, :node, :retry], %{count: 1}, %{
      node_type: data.node_type,
      retry_count: data.retry_count
    })
    next.(data)
  end
  
  def call(event, data, next), do: next.(data)
end
```

## Advanced Configuration

### Performance Tuning

```elixir
config :prana, :execution,
  max_parallel_nodes: 20,           # Maximum concurrent node execution
  default_node_timeout: 30_000,     # Default node timeout (30s)
  default_workflow_timeout: 300_000, # Default workflow timeout (5m)
  retry_jitter_enabled: true,       # Enable retry jitter by default
  expression_cache_size: 1000       # Expression evaluation cache
```

### Custom Event Handlers

```elixir
defmodule MyApp.WorkflowSpecificMiddleware do
  @behaviour Prana.Behaviour.Middleware
  
  def call(:execution_started, %{workflow_name: "critical_workflow"} = data, next) do
    # Special handling for critical workflows
    AlertingSystem.notify(:critical_workflow_started, data)
    next.(data)
  end
  
  def call(:node_failed, %{node_type: :output} = data, next) do
    # Output node failures are critical
    AlertingSystem.critical_alert(:output_node_failed, data)
    next.(data)
  end
  
  def call(event, data, next), do: next.(data)
end
```

## Conclusion

The Prana GraphExecutor provides a robust, scalable foundation for workflow automation with:

✅ **Comprehensive execution patterns** - Sequential, parallel, conditional, error handling
✅ **Robust error recovery** - Configurable retry policies with intelligent backoff
✅ **High performance** - Task-based parallel execution with resource management
✅ **Full observability** - Rich event system with middleware integration
✅ **Type safety** - Struct-based design with compile-time checking
✅ **Production ready** - Extensive testing and real-world validation

For additional help, examples, or contributions, see:
- [API Documentation](api_reference.md)
- [Integration Guide](integration_guide.md) 
- [Performance Tuning](performance_guide.md)
- [GitHub Repository](https://github.com/your-org/prana)