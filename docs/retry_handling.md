# Retry Handling in Prana GraphExecutor

## Overview

Prana implements comprehensive retry handling for failed node executions with configurable backoff strategies, error filtering, and integration with the main execution loop.

## How Retry Works

### 1. **Retry Configuration**

Each node can have a `RetryPolicy` that defines:

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

### 2. **Retry Decision Flow**

```
Node Fails → Check RetryPolicy → Filter Error Type → Check Attempt Count → Calculate Delay → Retry
```

1. **Node execution fails** in GraphExecutor
2. **RetryHandler.should_retry?/2** checks if retry is possible
3. **Error type filtering** - only retry on specified error types (if configured)
4. **Attempt count check** - ensure we haven't exceeded max_attempts
5. **Calculate delay** using backoff strategy
6. **Execute retry** with proper delay and event emission

### 3. **Backoff Strategies**

#### Fixed Delay
```elixir
delay = initial_delay_ms  # Always same delay
```

#### Linear Backoff
```elixir
delay = initial_delay_ms * (retry_count + 1)
# Attempt 1: 1000ms
# Attempt 2: 2000ms  
# Attempt 3: 3000ms
```

#### Exponential Backoff
```elixir
delay = initial_delay_ms * (backoff_multiplier ^ retry_count)
# Attempt 1: 1000ms
# Attempt 2: 2000ms
# Attempt 3: 4000ms
# Attempt 4: 8000ms
```

### 4. **Jitter Implementation**
Adds ±25% random variance to prevent thundering herd:
```elixir
jitter_range = div(delay, 4)
final_delay = delay + random(-jitter_range, +jitter_range)
```

## Integration with GraphExecutor

### 1. **Batch Failure Handling**

When nodes fail in a batch, GraphExecutor:

1. **Separates retryable vs permanent failures**
2. **Groups retryable failures** by node + execution
3. **Applies recovery strategy**:
   - `:continue` - Mark as failed and continue
   - `:retry` - Execute retry batch
   - `:stop` - Critical failure, stop workflow
   - `:suspend` - Wait for external intervention

### 2. **Retry Execution Process**

```elixir
# In GraphExecutor.execute_workflow_loop/2
{:partial_success, successes, failures, context} ->
  case Helpers.handle_batch_failures(failures, plan, context) do
    {:retry, retry_context, retry_nodes} ->
      # Execute retry batch with delays
      case execute_retry_batch(retry_nodes, plan, retry_context) do
        {:ok, retry_successes, final_context} ->
          # Combine successes and continue
          all_successes = successes ++ retry_successes
          continue_execution(all_successes, final_context)
          
        {:partial_success, retry_successes, final_failures, final_context} ->
          # Some retries succeeded, others permanently failed
          continue_execution(successes ++ retry_successes, final_context)
      end
  end
```

### 3. **Event Emission**

Retry process emits comprehensive events for observability:

```elixir
# Before retry
:node_retry_delay     # Emitted before delay
:node_retry_started   # Retry attempt begins
:retry_batch_started  # Multiple retries starting

# After retry  
:node_retry_succeeded # Retry succeeded
:node_retry_failed    # Retry failed (may retry again)
```

## Usage Examples

### Basic Retry Configuration

```elixir
# Create node with retry policy
retry_policy = %RetryPolicy{
  max_attempts: 3,
  backoff_strategy: :exponential,
  initial_delay_ms: 1000
}

node = Node.new("API Call", :action, "http", "get", input_config, "api_call")
node = %{node | retry_policy: retry_policy}
```

### Error-Specific Retries

```elixir
# Only retry on network-related errors
retry_policy = %RetryPolicy{
  max_attempts: 5,
  retry_on_errors: ["timeout", "connection_error", "network_error"],
  backoff_strategy: :exponential,
  initial_delay_ms: 500,
  max_delay_ms: 10_000
}
```

### Conservative Retry with Jitter

```elixir
# Prevent thundering herd with jitter
retry_policy = %RetryPolicy{
  max_attempts: 3,
  backoff_strategy: :linear,
  initial_delay_ms: 2000,
  jitter: true  # Adds ±25% randomness
}
```

## Key Components

### Files Created/Modified

1. **`/lib/prana/execution/retry_handler.ex`** - Core retry logic
2. **`/lib/prana/execution/graph_executor.ex`** - Retry integration 
3. **`/lib/prana/execution/graph_executor_helpers.ex`** - Batch retry handling
4. **`/test/prana/execution/retry_integration_test.exs`** - Comprehensive tests

### Key Functions

- **`RetryHandler.should_retry?/2`** - Determine if retry is possible
- **`RetryHandler.calculate_retry_delay/2`** - Calculate backoff delay
- **`GraphExecutor.execute_retry_batch/3`** - Execute multiple retries
- **`Helpers.separate_retryable_failures/2`** - Split retryable vs permanent failures

## Error Handling Edge Cases

### 1. **Mixed Success/Failure Batches**
- Original successes are preserved
- Only failed nodes are retried
- Results are combined after retry completion

### 2. **Retry Exhaustion**
- Nodes that exceed max_attempts are marked as permanently failed
- Workflow continues with other nodes (unless critical)
- Final failure count includes exhausted retries

### 3. **Critical Node Retries**
- Critical nodes (like output nodes) can still retry
- If critical node retries are exhausted, workflow stops
- Error handling strategy determines final behavior

### 4. **Timeout During Retry**
- Each retry attempt has its own timeout
- Timeout failures can themselves be retried
- Prevents infinite retry loops

## Performance Considerations

### 1. **Delay Management**
- Retries are executed sequentially (not in parallel)
- Each retry waits for its calculated delay
- Delays are capped by `max_delay_ms`

### 2. **Resource Usage**
- Failed executions store original error data
- Retry attempts track attempt count and timing
- Context stores retry statistics and metadata

### 3. **Observability**
- Comprehensive event emission for monitoring
- Retry statistics in execution context
- Individual node retry tracking

This retry implementation provides robust failure recovery while maintaining workflow execution performance and observability.