# ADR-004: Middleware System for Workflow Lifecycle Events

**Date**: December 2024
**Status**: Accepted
**Deciders**: Prana Core Team

## Context

Prana workflow execution requires extensible hooks for applications to integrate with workflow lifecycle events such as:
- Workflow execution started/completed/failed
- Node execution started/completed/failed
- Custom business logic integration
- Logging, monitoring, and persistence

The system needs a clean separation between the core execution engine and application-specific concerns while maintaining composability and flexibility.

## Decision

We will implement a **middleware pipeline system** that allows applications to inject custom logic into workflow execution lifecycle events.

### Core Architecture

#### Middleware Interface
```elixir
defmodule Prana.Behaviour.Middleware do
  @callback call(event :: atom(), data :: map(), next :: function()) :: any()
end
```

#### Pipeline Execution
```elixir
defmodule Prana.Middleware do
  def call(event, data, middleware_list) do
    build_pipeline(middleware_list).(event, data)
  end

  defp build_pipeline([]), do: fn _event, data -> data end

  defp build_pipeline([middleware | rest]) do
    fn event, data ->
      middleware.call(event, data, build_pipeline(rest))
    end
  end
end
```

#### Supported Events
- `:execution_started` - Workflow execution begins
- `:execution_completed` - Workflow execution completes successfully
- `:execution_failed` - Workflow execution fails
- `:node_started` - Node execution begins
- `:node_completed` - Node execution completes successfully
- `:node_failed` - Node execution fails

## Rationale

### Why Middleware Pattern?

1. **Composability**: Multiple middleware can be chained together
2. **Separation of Concerns**: Core execution separate from application logic
3. **Flexibility**: Applications can add/remove behaviors dynamically
4. **Order Control**: Middleware execution order is explicit and configurable
5. **Event-Driven**: Clean integration points for application hooks

### Why Not Callbacks?

- **Rigid Interface**: Callbacks require predefined function signatures
- **Limited Composability**: Hard to combine multiple callback implementations
- **Coupling**: Direct coupling between core engine and application code

### Why Not GenServer Events?

- **Process Overhead**: Additional processes for simple hooks
- **Complexity**: Event bus complexity for synchronous operations
- **Error Handling**: More complex error propagation

## Implementation

### Middleware Registration
```elixir
# Applications configure middleware during startup
Prana.Middleware.configure([
  MyApp.LoggingMiddleware,
  MyApp.PersistenceMiddleware,
  MyApp.NotificationMiddleware
])
```

### Example Middleware Implementation
```elixir
defmodule MyApp.LoggingMiddleware do
  @behaviour Prana.Behaviour.Middleware

  require Logger

  def call(event, data, next) do
    Logger.info("Workflow event: #{event}", data)
    result = next.(event, data)
    Logger.info("Event processed: #{event}")
    result
  end
end
```

### Integration with GraphExecutor
```elixir
defmodule Prana.Execution.GraphExecutor do
  def execute_workflow(graph, input, context) do
    # Fire start event
    Prana.Middleware.call(:execution_started, %{
      execution_id: graph.execution_id,
      workflow_id: graph.workflow_id,
      input: input
    })

    # Execute workflow
    case execute_workflow_nodes(graph, context) do
      {:ok, result} ->
        # Fire completion event
        Prana.Middleware.call(:execution_completed, %{
          execution_id: graph.execution_id,
          result: result
        })
        {:ok, result}

      {:error, reason} ->
        # Fire failure event
        Prana.Middleware.call(:execution_failed, %{
          execution_id: graph.execution_id,
          reason: reason
        })
        {:error, reason}
    end
  end
end
```

## Consequences

### Positive
- **Clean Separation**: Core execution engine separate from application concerns
- **Composable**: Multiple middleware can be combined easily
- **Flexible**: Applications have full control over lifecycle event handling
- **Testable**: Middleware can be tested independently
- **Performant**: Minimal overhead for synchronous event handling

### Negative
- **Ordering Dependency**: Middleware order can affect behavior
- **Error Propagation**: Middleware errors can break execution pipeline
- **Debugging Complexity**: Multiple middleware layers can complicate debugging

### Risks
- **Middleware Conflicts**: Multiple middleware modifying same data
- **Performance Impact**: Heavy middleware can slow execution
- **Error Handling**: Middleware failures need careful handling

## Alternatives Considered

### 1. Direct Callbacks
```elixir
# Rejected - less flexible
def execute_workflow(graph, input, on_start, on_complete, on_error)
```

### 2. Event Bus with GenServer
```elixir
# Rejected - adds process complexity
EventBus.publish(:execution_started, data)
```

### 3. Hooks System
```elixir
# Rejected - similar to middleware but less composable
Prana.Hooks.register(:execution_started, &MyApp.handle_start/1)
```

## Acceptance Criteria

- [x] Middleware can be registered and executed in order
- [x] All workflow lifecycle events fire middleware
- [x] Middleware can modify event data and pass to next middleware
- [x] Error handling works correctly in middleware pipeline
- [x] Performance impact is minimal for simple middleware
- [ ] Documentation and examples provided
- [ ] Applications successfully migrated to middleware pattern

## References

- [Graph Execution Patterns Documentation](../graph_execution%20pattern.md)
- [NodeExecutor Implementation](../../lib/prana/node_executor.ex)
- [GraphExecutor Implementation](../../lib/prana/execution/graph_executor.ex)

---

**Status**: ✅ Accepted - Currently implemented and in use
**Implementation**: Complete in core engine, applications using successfully
