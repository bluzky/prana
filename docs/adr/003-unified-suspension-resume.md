# ADR-003: Unified Suspension/Resume Mechanism for Async Coordination

**Date**: December 2024  
**Status**: Proposed  
**Deciders**: Prana Core Team  

## Context

Prana needs to support async coordination patterns including:
- External event coordination (webhooks, human approvals)
- Sub-workflow orchestration (parent-child workflows) 
- External system polling (API status checks)
- Time-based delays (scheduled execution)

Initial analysis suggested implementing separate APIs and integrations for each pattern. However, this would create significant API surface area and complexity.

## Decision

We will implement a **unified suspension/resume mechanism** that handles all async coordination patterns through:

1. **Single return pattern** from integrations: `{:suspend, suspend_type, suspension_data}`
2. **Minimal public API**: Only `resume_workflow/2` and `cancel_workflow/2`
3. **Middleware-based callbacks** for application integration
4. **Internal coordination** by GraphExecutor

### Core Architecture

#### Suspension Flow
```elixir
# 1. Integration returns suspension
{:suspend, :external_event, %{event_type: "approval", timeout_ms: 86400000}}

# 2. GraphExecutor handles suspension internally
def handle_internal_suspension(graph, node, suspend_type, suspension_data) do
  # Fire middleware event
  fire_middleware_event(:node_suspended, %{
    execution_id: graph.execution_id,
    suspend_type: suspend_type,
    suspension_data: suspension_data
  })
  
  # Return suspended execution
  {"suspended", graph.execution_id, suspension_data}
end

# 3. Application handles via middleware
def call(:node_suspended, data, next) do
  case data.suspend_type do
    :external_event -> setup_event_listening(data)
    :sub_workflow -> execute_sub_workflow(data)
    :polling -> start_polling_worker(data)
    :delay -> schedule_timer(data)
  end
  next.(data)
end

# 4. Application triggers resume
Prana.WorkflowManager.resume_workflow(execution_id, result_data)
```

#### Public API Surface
```elixir
# Only 2 public APIs
def resume_workflow(execution_id, resume_data) :: {:ok, result} | {:error, reason}
def cancel_workflow(execution_id, reason) :: :ok | {:error, reason}
```

## Rationale

### Why Unified Approach?

1. **Minimal API Surface**: Only 2 public functions vs 10+ in separate approach
2. **Consistent Pattern**: All async patterns use same suspend/resume flow
3. **Existing Infrastructure**: Leverages proven middleware system
4. **Application Control**: Applications handle all external concerns (persistence, HTTP, timers)
5. **Library Focus**: Prana stays focused on workflow execution coordination

### Why Middleware vs Callbacks?

- **Existing Pattern**: Middleware is already proven in Prana
- **Composability**: Multiple middleware can handle different aspects
- **Flexibility**: Applications can add/remove behaviors dynamically
- **Separation**: Clear boundaries between library and application concerns

### Suspension Types

| Type | Use Case | Application Handles |
|------|----------|-------------------|
| `:external_event` | Webhooks, approvals | Event routing, persistence, timeouts |
| `:sub_workflow` | Parent-child workflows | Workflow loading, execution tracking |
| `:polling` | API status checks | HTTP client, condition evaluation |
| `:delay` | Time-based delays | Timer scheduling, persistence |

## Implementation Plan

### Phase 1: Core Suspension Mechanism
- [ ] Enhance GraphExecutor to handle `{:suspend, type, data}` returns
- [ ] Add middleware events: `:node_suspended`, `:node_resumed`, `:workflow_cancelled`
- [ ] Implement `resume_workflow/2` and `cancel_workflow/2` APIs
- [ ] Create suspension state management

### Phase 2: Integration Updates
- [ ] Update Wait integration for external events
- [ ] Create Workflow integration for sub-workflow execution
- [ ] Create Poll integration for external polling
- [ ] Create Time integration for delays

### Phase 3: Documentation & Guides
- [ ] Application integration guide
- [ ] Middleware examples for each use case
- [ ] Migration guide from any existing patterns

## Consequences

### Positive
- **Simplified API**: Minimal surface area reduces complexity
- **Unified Pattern**: Consistent approach across all async patterns
- **Application Flexibility**: Full control over external integrations
- **Leveraged Infrastructure**: Uses existing middleware system
- **Library Focus**: Keeps Prana focused on execution coordination

### Negative
- **Application Complexity**: Applications must implement more logic
- **Learning Curve**: Developers must understand middleware patterns
- **Documentation Burden**: Need comprehensive integration guides

### Risks
- **Middleware Ordering**: Applications must handle middleware correctly
- **Error Handling**: Suspension failures need careful handling
- **State Management**: Applications responsible for persistence complexity

## Alternatives Considered

### 1. Separate APIs per Use Case
```elixir
# Rejected - too many APIs
Prana.EventCoordinator.wait_for_event/2
Prana.WorkflowOrchestrator.execute_sub_workflow/3
Prana.PollingManager.start_polling/3
Prana.TimerManager.schedule_delay/2
```

**Rejected because**: Creates large API surface, duplicates coordination logic

### 2. Behavior-Based Callbacks
```elixir
# Rejected - rigid interface  
@callback on_workflow_suspended(execution_id, suspension_data) :: :ok | {:error, term()}
@callback on_workflow_resumed(execution_id, result_data) :: :ok | {:error, term()}
```

**Rejected because**: Less flexible than middleware, harder to compose

### 3. GenServer-Based Coordination
```elixir
# Rejected - adds complexity
{:ok, suspension_pid} = Prana.SuspensionManager.start_suspension(config)
```

**Rejected because**: Adds process management complexity, less transparent

## Acceptance Criteria

- [ ] Single `{:suspend, type, data}` pattern works for all use cases
- [ ] Middleware can handle all suspension types appropriately  
- [ ] Applications can implement external event coordination
- [ ] Applications can implement sub-workflow orchestration
- [ ] Applications can implement external polling
- [ ] Applications can implement time-based delays
- [ ] Resume workflow API works for all suspension types
- [ ] Cancel workflow API properly cleans up suspensions
- [ ] Comprehensive documentation and examples provided
- [ ] Migration path from any existing patterns defined

## References

- [ADR-004: Middleware System for Workflow Lifecycle Events](./004-middleware-system.md)
- [Graph Execution Patterns Documentation](../graph_execution%20pattern.md)
- [Application Integration Guide](../application-integration-guide.md)

---

**Status**: ✅ Proposed - Ready for implementation
**Next Steps**: Begin Phase 1 implementation with GraphExecutor enhancements