# Loop Implementation Plan

## Overview

This document outlines the implementation plan for adding loop support to the Prana workflow engine. The changes are based on analysis of n8n's execution model and will introduce breaking changes to our data structures to support multiple node executions with proper iteration tracking.

## Key Changes Summary

1. **NodeExecution Structure**: Add `execution_index` and `run_index` fields
2. **Execution Structure**: Change `node_executions` from list to map
3. **Runtime Rebuilding**: Use last execution per node for expression evaluation
4. **GraphExecutor**: Track global execution order and per-node iterations

## Phase 1: Core Data Structure Changes ✅ **COMPLETED**

### 1.1 Update NodeExecution Struct (`lib/prana/core/node_execution.ex`) ✅ **COMPLETED**

**Add new fields:**
```elixir
@type t :: %__MODULE__{
  # ... existing fields ...
  execution_index: integer(),  # Global execution order (0, 1, 2, 3...)
  run_index: integer(),       # Per-node iteration (0, 1, 2, 3...)
  # ... rest of fields ...
}

defstruct [
  # ... existing fields ...
  execution_index: 0,
  run_index: 0,
  # ... rest of fields ...
]
```

**Update constructor:**
```elixir
def new(execution_id, node_id, execution_index \\ 0, run_index \\ 0) do
  %__MODULE__{
    # ... existing fields ...
    execution_index: execution_index,
    run_index: run_index,
    # ... rest of fields ...
  }
end
```

### 1.2 Update Execution Struct (`lib/prana/core/execution.ex`) ✅ **COMPLETED**

**Change node_executions from list to map and add execution index tracking:**
```elixir
@type t :: %__MODULE__{
  # ... existing fields ...
  node_executions: %{String.t() => [Prana.NodeExecution.t()]},  # Changed from list
  current_execution_index: integer(),  # Track next execution index to use
  # ... rest of fields ...
}

defstruct [
  # ... existing fields ...
  node_executions: %{},  # Changed from []
  current_execution_index: 0,  # Start at 0 for fresh executions
  # ... rest of fields ...
]
```

### 1.3 Update Execution Helper Functions ✅ **COMPLETED**

**Update `complete_node/2`:**
```elixir
def complete_node(%__MODULE__{} = execution, %Prana.NodeExecution{status: :completed} = completed_node_execution) do
  node_id = completed_node_execution.node_id

  # Get existing executions for this node
  existing_executions = Map.get(execution.node_executions, node_id, [])

  # Remove any existing execution with same run_index (for retries)
  remaining_executions =
    Enum.reject(existing_executions, fn ne -> ne.run_index == completed_node_execution.run_index end)

  # Add the completed execution (maintain chronological order by execution_index)
  updated_executions =
    (remaining_executions ++ [completed_node_execution])
    |> Enum.sort_by(& &1.execution_index)

  # Update the map
  updated_node_executions = Map.put(execution.node_executions, node_id, updated_executions)

  # Update runtime state if present
  updated_runtime =
    case execution.__runtime do
      nil -> nil
      runtime ->
        # Update with latest execution output
        node_data = %{
          "output" => completed_node_execution.output_data,
          "context" => completed_node_execution.context_data
        }
        updated_node_map = Map.put(runtime["nodes"] || %{}, node_id, node_data)
        Map.put(runtime, "nodes", updated_node_map)
    end

  %{execution | node_executions: updated_node_executions, __runtime: updated_runtime}
end
```

**Update `fail_node/2`:**
```elixir
def fail_node(%__MODULE__{} = execution, %Prana.NodeExecution{status: :failed} = failed_node_execution) do
  node_id = failed_node_execution.node_id

  # Get existing executions for this node
  existing_executions = Map.get(execution.node_executions, node_id, [])

  # Remove any existing execution with same run_index (for retries)
  remaining_executions =
    Enum.reject(existing_executions, fn ne -> ne.run_index == failed_node_execution.run_index end)

  # Add the failed execution
  updated_executions =
    (remaining_executions ++ [failed_node_execution])
    |> Enum.sort_by(& &1.execution_index)

  # Update the map
  updated_node_executions = Map.put(execution.node_executions, node_id, updated_executions)

  %{execution | node_executions: updated_node_executions}
end
```

**Update `rebuild_runtime/2`:**
```elixir
def rebuild_runtime(%__MODULE__{} = execution, env_data \\ %{}) do
  # Get LAST completed execution of each node (highest run_index)
  node_structured =
    execution.node_executions
    |> Enum.map(fn {node_id, executions} ->
      last_execution =
        executions
        |> Enum.filter(fn exec -> exec.status == :completed end)
        |> Enum.max_by(& &1.run_index, fn -> nil end)

      case last_execution do
        nil -> {node_id, nil}
        exec -> {node_id, %{"output" => exec.output_data, "context" => exec.context_data}}
      end
    end)
    |> Enum.reject(fn {_, data} -> is_nil(data) end)
    |> Enum.into(%{})

  # Build runtime state (simplified for now)
  runtime = %{
    "nodes" => node_structured,
    "env" => env_data
  }

  %{execution | __runtime: runtime}
end
```

## Phase 2: Execution Engine Updates ✅ **COMPLETED**

### 2.1 Update GraphExecutor (`lib/prana/execution/graph_executor.ex`) ✅ **COMPLETED**

**Update node execution tracking:**
```elixir
defp execute_node_with_tracking(node, execution, execution_graph, middleware_stack) do
  # Use current execution index (no calculation needed)
  execution_index = execution.current_execution_index

  # Get run_index for this specific node
  run_index = get_next_run_index(execution, node.id)

  # Execute node
  case NodeExecutor.execute_node(node, execution, execution_index, run_index) do
    {:ok, node_execution, updated_execution} ->
      # Increment execution index for next node
      final_execution = %{updated_execution | current_execution_index: execution_index + 1}
      {:ok, node_execution, final_execution}

    {:error, reason} ->
      # Still increment on error to maintain sequence
      final_execution = %{execution | current_execution_index: execution_index + 1}
      {:error, reason, final_execution}
  end
end

defp get_next_run_index(execution, node_id) do
  case Map.get(execution.node_executions, node_id, []) do
    [] -> 0
    executions ->
      max_run_index = Enum.max_by(executions, & &1.run_index).run_index
      max_run_index + 1
  end
end
```

**Benefits of current_execution_index approach:**
- **O(1) Performance**: No scanning of node executions needed
- **Fresh Execution**: Starts at 0 for new workflows
- **Resume-Friendly**: Automatically preserved across suspension/resume
- **Thread-Safe**: Single source of truth, no race conditions

### 2.2 Update NodeExecutor (`lib/prana/node_executor.ex`) ✅ **COMPLETED**

**Update execute_node function signature:**
```elixir
def execute_node(node, execution, execution_index, run_index) do
  # Create NodeExecution with both indices
  node_execution = NodeExecution.new(execution.id, node.id, execution_index, run_index)

  # ... rest of execution logic ...
end
```

## Phase 3: Testing & Validation 🔄 **IN PROGRESS**

### 3.1 Testing Strategy

**CRITICAL**: All existing tests must pass before adding new functionality. This ensures we haven't broken existing behavior during the refactor.

**Step 1: Fix Core Tests (Priority 1) ✅ COMPLETED**
1. ✅ Run `mix test` to identify all failing tests
2. ✅ Fix tests one module at a time in dependency order:
   - ✅ `test/prana/core/node_execution_test.exs` - **COMPLETED**
   - ✅ `test/prana/core/execution_test.exs` - **COMPLETED**
   - ✅ `test/prana/node_executor_test.exs` - **COMPLETED**
   - ✅ `test/prana/execution/graph_executor_test.exs` - **COMPLETED**
   - ✅ `test/prana/expression_engine_test.exs` - **COMPLETED**
3. 🔄 **Gate**: Core tests pass, remaining test files need map structure updates

**Step 2: Fix Remaining Test Files 🔄 IN PROGRESS**
- 🔄 `test/prana/execution/graph_executor_conditional_branching_test.exs` - **NEEDS UPDATE**
- 🔄 `test/prana/execution/simple_loop_test.exs` - **NEEDS UPDATE**  
- 🔄 `test/prana/execution/graph_executor_sub_workflow_test.exs` - **NEEDS UPDATE**

**Step 3: Add New Test Cases (Priority 3) ⏸️ PENDING**
Only after Steps 1-2 are complete, add new test cases for loop functionality.

### 3.2 Core Test Updates Required

**Key changes needed:**
1. **Assertion Updates**: Change from list to map structure access
2. **Test Data Helpers**: Update mock data creation functions
3. **Field Updates**: Add execution_index and run_index to test data
4. **Runtime State**: Update rebuild_runtime test assertions

**Example test fixes:**
```elixir
# OLD assertion
assert length(execution.node_executions) == 2

# NEW assertion
assert map_size(execution.node_executions) == 2
assert length(execution.node_executions["node_1"]) == 1

# OLD access
first_execution = List.first(execution.node_executions)

# NEW access
first_execution = execution.node_executions["node_1"] |> List.first()
```

### 3.3 New Test Cases (After Core Tests Pass)

**Loop execution patterns:**
```elixir
test "tracks execution_index globally across all nodes" do
  # Verify execution_index increments: 0, 1, 2, 3...
end

test "tracks run_index per node" do
  # Verify same node can have multiple executions: 0, 1, 2...
end

test "rebuild_runtime uses last execution per node" do
  # Verify expressions get latest output
end

test "node_executions map structure maintains chronological order" do
  # Verify executions within each node are ordered by execution_index
end

test "current_execution_index increments correctly" do
  # Verify execution index advances with each node execution
end
```


## Phase 4: Expression Engine Updates

### 4.1 Enhanced Expression Access

With the new structure, expressions can access:
```elixir
# Current execution (last)
"$nodes.wait_node.output"

# Specific iteration (future enhancement)
"$nodes.wait_node[2].output"  # 3rd iteration (run_index 2)

# All iterations (future enhancement)
"$nodes.wait_node.*.output"   # Array of all outputs
```

## Breaking Changes Impact

### Files Requiring Updates
- `lib/prana/core/execution.ex` ✅ **COMPLETED**
- `lib/prana/core/node_execution.ex` ✅ **COMPLETED**  
- `lib/prana/execution/graph_executor.ex` ✅ **COMPLETED**
- `lib/prana/node_executor.ex` ✅ **COMPLETED**
- Core test files (`execution_test.exs`, `graph_executor_test.exs`) ✅ **COMPLETED**
- Remaining test files (conditional branching, simple loop, sub-workflow) 🔄 **IN PROGRESS**

### Migration Strategy
1. **Gradual Migration**: Update core structures first
2. **Test-Driven**: Fix tests incrementally
3. **Backward Compatibility**: Consider temporary adapters if needed
4. **Documentation**: Update all examples and guides

### Risk Mitigation
- **Comprehensive Testing**: Ensure all existing functionality works
- **Performance Testing**: Verify map operations don't degrade performance
- **Edge Case Testing**: Test error conditions and edge cases
- **Integration Testing**: Verify with all built-in integrations

## Success Criteria

1. ✅ **Data Structure**: Map-based node_executions with proper indexing - **COMPLETED**
2. ✅ **Execution Tracking**: Global execution_index and per-node run_index - **COMPLETED**
3. ✅ **Expression Access**: Proper access to latest node outputs - **COMPLETED**
4. 🔄 **Test Coverage**: Core tests pass, remaining test files need map structure updates - **IN PROGRESS**
5. ✅ **Loop Foundation**: Ready for loop control flow implementation - **COMPLETED**

## Implementation Status Summary

**✅ COMPLETED (Phases 1-2):**
- Core data structure changes with execution tracking
- Map-based node_executions with O(1) lookup by node_id  
- GraphExecutor and NodeExecutor updated with execution tracking
- Legacy list structure support removed for cleaner codebase
- Core test files migrated to new structure
- Foundation ready for loop implementation

**🔄 IN PROGRESS (Phase 3):**
- Remaining test files need map structure updates (conditional branching, simple loop, sub-workflow)

**⏸️ PENDING:**
- New test cases for loop functionality (after all existing tests pass)

## Next Steps After Implementation

1. **Loop Integration**: Create Loop integration with iteration controls
2. **Loop Conditions**: Implement loop termination conditions
3. **Loop Variables**: Add loop-specific variables and context
4. **Advanced Patterns**: Support nested loops and complex iteration patterns

This implementation provides the foundation for full loop support while maintaining compatibility with existing workflow patterns.
