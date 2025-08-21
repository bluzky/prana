# Task: Implement Node Retry Mechanism

**Status**: ✅ COMPLETED  
**Priority**: Medium  
**Estimated Effort**: 2-3 days  
**Related ADR**: [ADR-008: Node Retry Mechanism](../adr/008-node-retry-mechanism.md)

## Overview

Implement retry functionality for failed node executions by leveraging the existing suspension/resume infrastructure. This will allow nodes to automatically retry on transient failures with configurable delay and attempt limits.

## Implementation Methodology

**For each phase:**
1. ✅ **Implement code** - Write the implementation following the design
2. ✅ **Write unit tests** - Create comprehensive tests to cover new code
3. ✅ **Validate tests** - If tests fail, check if expectation is correct:
   - If expectation is correct → modify code to pass tests
   - If expectation is wrong → update expectation, DON'T fix tests to fit broken code
4. ✅ **Update progress** - Mark completed items in checklist
5. ✅ **Move to next phase** - Only proceed when current phase is fully complete

## Progress Checklist

### Phase 1: Core Data Structures ✅
- [x] 1.1 Create NodeSettings struct
- [x] 1.2 Write NodeSettings unit tests
- [x] 1.3 Update Node struct with settings field
- [x] 1.4 Write Node struct tests for settings
- [x] 1.5 Phase 1 validation and cleanup

### Phase 2: NodeExecutor Retry Logic ✅
- [x] 2.1 Add retry helper functions
- [x] 2.2 Modify handle_execution_error to handle_execution_error/3  
- [x] 2.3 Add handle_resume_error/2 function
- [x] 2.4 Update all error handler call sites
- [x] 2.5 Write unit tests for retry decision logic
- [x] 2.6 Write unit tests for error handler separation  
- [x] 2.7 Phase 2 validation and cleanup
- [x] 2.8 Fix IntegrationRegistry setup in tests

### Phase 3: Retry Execution Function ✅
- [x] 3.1 Implement retry_node/4 function
- [x] 3.2 Write comprehensive retry_node tests
- [x] 3.3 Test retry vs resume separation
- [x] 3.4 Phase 3 validation and cleanup

### Phase 4: GraphExecutor Integration ✅
- [x] 4.1 Update GraphExecutor resume logic
- [x] 4.2 Add retry vs resume decision logic
- [x] 4.3 Write GraphExecutor retry tests
- [x] 4.4 Write end-to-end retry workflow tests
- [x] 4.5 Phase 4 validation and cleanup

### Phase 5: Final Integration ✅
- [x] 5.1 Run full test suite
- [x] 5.2 Fix any integration issues (IntegrationRegistry async conflicts)
- [x] 5.3 Update documentation with examples (CLAUDE.md, application-integration-guide.md, and building_workflows.md updated)
- [x] 5.4 Performance validation (minimal overhead confirmed)
- [x] 5.5 Final review and cleanup

## Implementation Plan

### Phase 1: Core Data Structures

#### Task 1.1: Create NodeSettings Struct
**File**: `lib/prana/core/node_settings.ex`
**Effort**: 1 hour implementation + 1 hour testing

```elixir
defmodule Prana.NodeSettings do
  @moduledoc """
  Node execution settings that apply to individual nodes in a workflow.
  
  Contains configuration options for retry behavior and future extensible settings.
  """
  
  use Skema

  defschema do
    # Retry configuration
    field(:retry_on_failed, :boolean, default: false)
    field(:max_retries, :integer, default: 1, number: [min: 1, max: 10])
    field(:retry_delay_ms, :integer, default: 1000, number: [min: 0, max: 60_000])
    
    # Future extensible settings can be added here
    # field(:timeout_ms, :integer, default: 30_000)
    # field(:priority, :integer, default: 0)
  end

  @doc "Creates default node settings"
  def default, do: new(%{})

  @doc "Load settings from a map with string keys"
  def from_map(data) when is_map(data) do
    {:ok, settings} = Skema.load(data, __MODULE__)
    settings
  end

  @doc "Convert settings to a JSON-compatible map"
  def to_map(%__MODULE__{} = settings), do: Map.from_struct(settings)

  @doc "Check if retry is enabled and configured properly"
  def retry_enabled?(%__MODULE__{retry_on_failed: enabled, max_retries: max_retries}) do
    enabled and max_retries > 0
  end

  @doc "Get effective retry delay for a given attempt number"
  def get_retry_delay(%__MODULE__{retry_delay_ms: delay_ms}, _attempt_number) do
    delay_ms
  end
end
```

**Tests**: Create comprehensive unit tests for all functions and validation rules.

#### Task 1.2: Update Node Struct
**File**: `lib/prana/core/node.ex`  
**Effort**: 1 hour

- Add `field(:settings, Prana.NodeSettings, default: %Prana.NodeSettings{})` to schema
- Update `from_map/1` and `to_map/1` to handle settings serialization
- Update tests to include settings field

### Phase 2: NodeExecutor Enhancements

#### Task 2.1: Implement Retry Decision Logic
**File**: `lib/prana/node_executor.ex`  
**Effort**: 4 hours

**Add helper functions:**
```elixir
# Check if node should retry based on settings and current attempt
defp should_retry?(node, node_execution, _error_reason) do
  settings = node.settings
  current_attempt = get_current_attempt_number(node_execution)
  
  NodeSettings.retry_enabled?(settings) and current_attempt < settings.max_retries
end

# Extract current attempt number from suspension_data (if this is a retry)
defp get_current_attempt_number(node_execution) do
  if node_execution.suspension_type == :retry do
    node_execution.suspension_data["attempt_number"] || 0
  else
    0  # First attempt
  end
end

# Get next attempt number
defp get_next_attempt_number(node_execution) do
  get_current_attempt_number(node_execution) + 1
end
```

**Modify `handle_execution_error/3`:**
```elixir
# For execute failures - includes retry logic  
defp handle_execution_error(node, node_execution, reason) do
  
  if should_retry?(node, node_execution, reason) do
    # Prepare retry suspension data
    next_attempt = get_next_attempt_number(node_execution)
    
    retry_suspension_data = %{
      "retry_delay_ms" => node.settings.retry_delay_ms,
      "attempt_number" => next_attempt,
      "max_attempts" => node.settings.max_retries,
      "original_error" => reason
      # Note: No original_input stored - will be rebuilt on retry
    }
    
    # Suspend for retry
    suspended_execution = NodeExecution.suspend(node_execution, :retry, retry_suspension_data)
    {:suspend, suspended_execution}
  else
    # Normal failure path
    failed_execution = NodeExecution.fail(node_execution, reason)
    {:error, {reason, failed_execution}}
  end
end
```

**Add separate error handler for resume failures:**
```elixir
# For resume failures - no retry logic
defp handle_resume_error(node_execution, reason) do
  failed_execution = NodeExecution.fail(node_execution, reason)
  {:error, {reason, failed_execution}}
end
```

**Update error handling:**
- Update all calls to `handle_execution_error` to pass Node parameter
- Update `resume_node` to use `handle_resume_error` (no retry for resume failures)
- Ensure node reference is available for retry decision logic

#### Task 2.2: Implement Separate Retry Function
**File**: `lib/prana/node_executor.ex`  
**Effort**: 3 hours

**Add new `retry_node/4` function:**
```elixir
@doc """
Retry a failed node execution by rebuilding input and re-executing the action.

This function is called specifically for retry scenarios and rebuilds the input
fresh from the current execution state, then calls action.execute().

## Parameters
- `node` - The node to retry
- `execution` - Current execution state  
- `failed_node_execution` - The failed NodeExecution to retry
- `execution_context` - Execution context (execution_index, run_index, etc.)

## Returns
Same as execute_node: {:ok, node_execution, updated_execution} | {:suspend, suspended_execution} | {:error, reason}
"""
def retry_node(node, execution, failed_node_execution, execution_context) do
  # Rebuild input fresh - same as execute_node
  routed_input = WorkflowExecution.extract_multi_port_input(node, execution)
  
  # Resume the failed execution
  resumed_node_execution = NodeExecution.resume(failed_node_execution)
  
  # Build context and execute action (same as normal execution)  
  action_context = build_expression_context(resumed_node_execution, execution, routed_input, execution_context)
  
  with {:ok, prepared_params} <- prepare_params(node, action_context),
       {:ok, action} <- get_action(node) do
    node_execution = %{resumed_node_execution | params: prepared_params}
    handle_action_execution(action, prepared_params, action_context, node_execution, execution)
  else
    {:error, reason} ->
      handle_execution_error(node, resumed_node_execution, reason)
  end
end
```

**Keep existing `resume_node/5` unchanged:**
- No modifications needed to existing resume logic
- Clean separation between retry and resume functionality

### Phase 3: Integration and Testing

#### Task 3.1: Update GraphExecutor 
**File**: `lib/prana/graph_executor.ex`  
**Effort**: 2 hours

**Add retry decision logic to `resume_workflow/3`:**
```elixir
# In resume_suspended_node function
case suspended_node_execution.suspension_type do
  :retry ->
    # Call dedicated retry function - no stored input needed
    case NodeExecutor.retry_node(
           suspended_node,
           resume_execution,
           suspended_node_execution,
           current_context
         ) do
      {:ok, completed_node_execution, updated_execution} ->
        Middleware.call(:node_completed, %{node: suspended_node, node_execution: completed_node_execution})
        {:ok, updated_execution, completed_node_execution.output_data}

      {:error, {reason, _failed_node_execution}} ->
        {:error, reason}
    end

  _ ->
    # Normal resume with resume_data (existing logic)
    case NodeExecutor.resume_node(
           suspended_node,
           resume_execution,
           suspended_node_execution,
           resume_data,
           current_context
         ) do
      # ... existing resume logic ...
    end
end
```

**Add retry-specific middleware events:**
- `node_retry_scheduled` when retry suspension is created
- `node_retry_attempt` when retry execution begins
- Enhanced logging for retry attempts

#### Task 3.2: Comprehensive Testing
**Files**: Create test files for all new functionality  
**Effort**: 6 hours

**Unit Tests:**
- `test/prana/core/node_settings_test.exs` - NodeSettings struct functionality
- `test/prana/node_executor_retry_test.exs` - NodeExecutor retry logic
- `test/prana/graph_executor_retry_test.exs` - End-to-end retry workflows

**Test Scenarios:**
1. **Basic retry success**: Node fails once, retries successfully
2. **Retry exhaustion**: Node fails max_retries + 1 times, final failure
3. **Retry disabled**: Node with `retry_on_failed: false` fails immediately
4. **Configuration validation**: Invalid retry settings handled properly
5. **Metadata preservation**: Original input and error data stored correctly
6. **Suspension integration**: Retry suspensions handled like other suspensions
7. **Resume distinction**: Retry resume vs normal resume behavior
8. **Loop compatibility**: Retry doesn't break loop `run_index` semantics

**Integration Tests:**
- Complete workflows with retry nodes
- Mixed workflows with retry and non-retry nodes
- Nested retry scenarios (retry within sub-workflows)
- Application-level retry scheduling

#### Task 3.3: Documentation Updates
**Files**: Update existing docs  
**Effort**: 2 hours

- Update `docs/guides/building_workflows.md` with retry examples
- Update `docs/guides/writing_integrations.md` with retry considerations
- Add retry section to `CLAUDE.md`
- Update API documentation for NodeExecutor changes

## Testing Strategy

### Manual Testing Scenarios

1. **Simple HTTP retry**: Configure HTTP integration with retry, test with timeout-prone endpoint
2. **Application integration**: Verify application can schedule and resume retry suspensions
3. **Retry exhaustion**: Test workflows that exhaust retry attempts
4. **Configuration edge cases**: Test with min/max retry values
5. **Loop interaction**: Test retry within for-each loops to ensure run_index compatibility

### Automated Test Coverage

- **Unit tests**: 95%+ coverage for new retry logic
- **Integration tests**: End-to-end retry workflows
- **Performance tests**: Ensure retry doesn't impact normal execution performance
- **Regression tests**: Verify existing suspension behavior unchanged

## Success Criteria

1. ✅ **NodeSettings struct** implemented with validation
2. ✅ **Node struct updated** with settings field and serialization
3. ✅ **NodeExecutor retry logic** working for error cases
4. ✅ **Resume distinction** between retry and normal resume
5. ✅ **GraphExecutor integration** with proper middleware events
6. ✅ **Comprehensive tests** passing with >95% coverage
7. ✅ **Documentation updated** with retry examples and guides
8. ✅ **Backward compatibility** - existing workflows unaffected
9. ✅ **Application integration** - retry suspensions handled like others
10. ✅ **Loop compatibility** - retry doesn't break existing loop logic

## Risk Mitigation

- **Breaking changes**: Ensure all changes are backward compatible
- **Performance impact**: Benchmark retry logic vs normal execution
- **Complex interaction**: Thorough testing of retry within loops and sub-workflows
- **Memory usage**: Verify original input storage doesn't cause memory issues
- **Edge cases**: Test boundary conditions (max retries, zero delay, etc.)

## Future Enhancements

After initial implementation, consider:
- **Exponential backoff**: More sophisticated delay strategies
- **Conditional retry**: Retry only on specific error types
- **Retry metrics**: Built-in retry success/failure tracking
- **Circuit breaker**: Disable retry after consecutive failures