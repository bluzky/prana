# Execution State Usage Guide

Prana workflows support execution state that persists across node executions within the same workflow run. This allows nodes to communicate and coordinate beyond the normal input/output port system.

## Overview

Execution state provides:
- **Cross-node communication**: Nodes can share data without explicit connections
- **Workflow coordination**: Track counters, flags, and complex state across execution
- **Suspension persistence**: State survives suspend/resume cycles
- **Expression access**: Read state values using `$execution.state` expressions
- **Merge semantics**: State updates are merged with existing state

## Accessing Execution State

### In Node Parameters (Expressions)

Use `$execution.state` expressions to read state values in node configurations:

```elixir
# Read a counter value
%{
  "max_retries" => "$execution.state.counter",
  "user_id" => "$execution.state.session.user_id"
}
```

### In Action Code

Actions receive execution state through the context parameter:

```elixir
def execute(params, context) do
  # Read current execution state
  state = context["$execution"]["state"]
  counter = Map.get(state, "counter", 0)
  
  # Your action logic here...
end
```

## Modifying Execution State

Actions can modify state by returning a state map that gets **merged** with the existing state:

```elixir
def execute(params, context) do
  # Read current counter from state
  current_counter = Map.get(context["$execution"]["state"], "counter", 0)
  
  # Create state updates (only specify what changes)
  state_updates = %{"counter" => current_counter + 1}
  
  # Return with state updates (will be merged with existing state)
  {:ok, result_data, "main", state_updates}
end
```

## Example Usage

### Counter Example

```elixir
# Action that increments a counter in execution state
def execute(params, context) do
  current_counter = Map.get(context["$execution"]["state"], "counter", 0)
  
  # Only return the changes - existing state is preserved
  state_updates = %{"counter" => current_counter + 1}
  
  {:ok, %{"new_counter" => current_counter + 1}, "main", state_updates}
end
```

### State Merge Example

```elixir
# Original state: %{"counter" => 1, "email" => "test@example.com"}
# Action updates: %{"counter" => 2}
# Result state: %{"counter" => 2, "email" => "test@example.com"}

def execute(params, context) do
  current_state = context["$execution"]["state"]
  # Original: %{"counter" => 1, "email" => "test@example.com"}
  
  # Only specify what changes
  state_updates = %{"counter" => 2}
  
  {:ok, %{"status" => "updated"}, "main", state_updates}
  # Final state will be: %{"counter" => 2, "email" => "test@example.com"}
end
```

### Session Data Example

```elixir
# Action that stores user session data
def execute(params, context) do
  session_data = %{
    "user_id" => params["user_id"],
    "session_id" => UUID.uuid4(),
    "login_time" => DateTime.utc_now()
  }
  
  # Add session data to state (other state values preserved)
  state_updates = %{"session" => session_data}
  
  {:ok, session_data, "main", state_updates}
end
```

### Coordination Flags Example

```elixir
# Action that adds completion flags for workflow coordination
def execute(params, context) do
  step_name = params["step_name"]
  current_flags = Map.get(context["$execution"]["state"], "completed_steps", [])
  updated_flags = [step_name | current_flags]
  
  # Only update the completed_steps field
  state_updates = %{"completed_steps" => updated_flags}
  
  {:ok, %{"completed_step" => step_name}, "main", state_updates}
end
```

## API Reference

### WorkflowExecution Functions

```elixir
# Update state (merges with existing state)
WorkflowExecution.update_shared_state(execution, %{"counter" => 5, "flag" => true})

# Access state directly from runtime
execution.__runtime["shared_state"]
```

### Context Structure

Actions receive execution state in the context:

```elixir
context = %{
  "$input" => %{},           # Node input data
  "$nodes" => %{},           # Completed node outputs
  "$env" => %{},             # Environment data
  "$vars" => %{},            # Workflow variables
  "$workflow" => %{},        # Workflow metadata
  "$execution" => %{         # Execution metadata
    "id" => "exec_123",
    "run_index" => 0,
    "execution_index" => 5,
    "mode" => :async,
    "preparation" => %{},
    "state" => %{}           # Execution state ← Available here!
  }
}
```

## Best Practices

1. **Use meaningful keys**: Use descriptive names like `"user_session"` instead of `"data"`
2. **Initialize safely**: Always provide defaults when reading state (`Map.get(state, "key", default)`)
3. **Keep it simple**: Store serializable data (maps, lists, strings, numbers)
4. **Document dependencies**: Document which nodes read/write state
5. **Minimal updates**: Only return state changes, not the entire state

## Persistence

Shared state is automatically:
- **Persisted** to execution metadata for durability
- **Restored** during execution rebuilding after suspension
- **Available** across suspend/resume cycles
- **Maintained** throughout the entire workflow execution

## Example Action Implementation

See `Prana.Integrations.Workflow.SetStateAction` for a simple state management action that:
- Takes input parameters and merges them into execution state
- Uses merge semantics to preserve existing state values
- Provides a clean interface for workflow state management

This makes shared state a powerful tool for complex workflow coordination and data sharing between nodes.