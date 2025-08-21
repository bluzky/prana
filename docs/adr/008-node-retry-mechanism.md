# ADR-008: Node Retry Mechanism

**Status**: Accepted & Implemented  
**Date**: 2025-01-10  
**Deciders**: Development Team

## Context

Currently, Prana workflows have no built-in retry capability for failed node executions. When a node fails (e.g., network timeout, temporary service unavailability), the entire workflow fails immediately. This creates brittleness in production workflows that could otherwise recover from transient failures.

Users need a configurable retry mechanism that:
- Allows nodes to automatically retry on failure
- Is configurable per-node with settings like max attempts and delay
- Maintains full audit trails of retry attempts
- Integrates cleanly with Prana's existing architecture

## Decision

We will implement retry functionality by **leveraging the existing suspension/resume infrastructure**. Retry will be treated as a special type of suspension where:

1. **Failed nodes with retry enabled** return `{:suspend, :retry, suspension_data}` instead of `{:error, reason}`
2. **Applications handle retry scheduling** using the same mechanisms as webhook/timer suspensions
3. **Resume for retry** calls `action.execute()` with original input instead of `action.resume()`

## Detailed Design

### 1. Node-Level Configuration

Add a new `NodeSettings` struct to configure retry behavior:

```elixir
defmodule Prana.NodeSettings do
  use Skema
  
  defschema do
    field(:retry_on_failed, :boolean, default: false)
    field(:max_retries, :integer, default: 1, number: [min: 1, max: 10])
    field(:retry_delay_ms, :integer, default: 1000, number: [min: 0, max: 60_000])
  end
end
```

Update `Prana.Node` to include settings:

```elixir
defmodule Prana.Node do
  defschema do
    # ... existing fields ...
    field(:settings, Prana.NodeSettings, default: %Prana.NodeSettings{})
  end
end
```

### 2. Retry Information Storage

Use existing `NodeExecution.suspension_data` field to track retry information:

```elixir
suspension_data: %{
  "retry_delay_ms" => 1000,        # Delay before retry
  "attempt_number" => 1,           # Current retry attempt (1-based)
  "max_attempts" => 3,             # Max configured attempts
  "original_error" => %{...}       # Error that triggered retry
  # Note: No original_input stored - rebuilt fresh on retry
}
```

### 3. Suspension-Based Retry Flow

**NodeExecutor Error Handling** (`handle_execution_error/3`):

```elixir
# For execute failures - includes retry logic
defp handle_execution_error(node, node_execution, reason) do
  
  if should_retry?(node, node_execution, reason) do
    # Return suspension for retry
    retry_suspension_data = %{
      "retry_delay_ms" => node.settings.retry_delay_ms,
      "attempt_number" => get_next_attempt_number(node_execution),
      "max_attempts" => node.settings.max_retries,
      "original_error" => reason
      # Note: No original_input stored - will be rebuilt on retry
    }
    
    suspended_execution = NodeExecution.suspend(node_execution, :retry, retry_suspension_data)
    {:suspend, suspended_execution}
  else
    # Normal failure
    failed_execution = NodeExecution.fail(node_execution, reason)
    {:error, {reason, failed_execution}}
  end
end
```

**Separate NodeExecutor Functions**:

```elixir
# Separate error handler for resume failures (no retry logic)
defp handle_resume_error(node_execution, reason) do
  failed_execution = NodeExecution.fail(node_execution, reason)
  {:error, {reason, failed_execution}}
end

# New function specifically for retry
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

# Existing resume function (unchanged)
def resume_node(node, execution, suspended_node_execution, resume_data, execution_context) do
  context = build_expression_context(suspended_node_execution, execution, %{}, execution_context)
  params = suspended_node_execution.params || %{}

  case get_action(node) do
    {:ok, action} ->
      handle_resume_action(action, params, context, resume_data, suspended_node_execution, execution)
    {:error, reason} ->
      handle_resume_error(suspended_node_execution, reason)  # No retry for resume failures
  end
end
```

**GraphExecutor Decision Logic**:

```elixir
# In GraphExecutor.resume_workflow
case suspended_execution.suspension_type do
  :retry ->
    # Call dedicated retry function - no stored input needed
    NodeExecutor.retry_node(node, execution, suspended_node_execution, context)
    
  _ ->
    # Normal resume with resume_data
    NodeExecutor.resume_node(node, execution, suspended_node_execution, resume_data, context)
end
```

### 4. Application Integration

Applications handle retry exactly like other suspensions:

```elixir
case Prana.GraphExecutor.execute_workflow(execution, input) do
  {:suspend, suspended_execution, %{"retry_delay_ms" => delay}} ->
    # Schedule retry using same mechanism as other suspensions
    Process.send_after(self(), {:resume_execution, suspended_execution}, delay)
    
  {:suspend, suspended_execution, other_suspension_data} ->
    # Handle other suspension types normally
    handle_other_suspension(suspended_execution, other_suspension_data)
end

def handle_info({:resume_execution, suspended_execution}, state) do
  # Resume exactly like other suspensions - no special handling needed!
  case Prana.GraphExecutor.resume_workflow(suspended_execution, %{}) do
    {:ok, completed_execution} -> handle_completion(completed_execution)
    {:suspend, still_suspended_execution, _} -> handle_re_suspension(still_suspended_execution)
    {:error, failed_execution} -> handle_final_failure(failed_execution)
  end
end
```

## Benefits

1. **Leverage Existing Infrastructure**: Reuses proven suspension/resume mechanisms
2. **Simple Application Integration**: No new patterns - same as webhook/timer suspensions
3. **Clean Separation of Concerns**: Prana handles retry logic, application handles scheduling
4. **Full Audit Trail**: Complete retry history stored in NodeExecution metadata
5. **Flexible Configuration**: Per-node retry settings with extensible NodeSettings struct
6. **Backward Compatible**: No changes to existing suspension behavior

## Consequences

### Positive
- Minimal code changes required
- Consistent with existing Prana patterns
- Easy to test and debug
- Flexible retry scheduling (apps can use GenServer, job queues, etc.)

### Negative
- Slight complexity in NodeExecutor resume logic (retry vs normal resume)
- Applications must handle retry suspensions (but same burden as other suspensions)

## Implementation Notes

- Only retry on `{:error, reason}` returns from `action.execute()`, not `action.resume()` or suspensions
- Preserve existing `run_index` semantics for loop compatibility
- Use existing `execution_index` for global sequencing
- Input data is rebuilt fresh on each retry (not stored in suspension_data)
- Resume failures use separate `handle_resume_error/2` function (no retry logic)
- Execute failures use `handle_execution_error/3` function (with retry logic)

## Alternatives Considered

1. **Direct Retry in NodeExecutor**: Would require internal scheduling and complicate the execution model
2. **New Retry Response Type**: Would require applications to handle a third response pattern
3. **Create New NodeExecution for Each Retry**: Would complicate loop logic that depends on run_index

The suspension-based approach was chosen for its simplicity and consistency with existing patterns.