# Task: Redesign WorkflowExecution with execution_data Structure

## Overview

Redesign WorkflowExecution to centralize context management and move active state tracking from runtime to persistent storage for better performance and organization.

## Current Problems

1. **Scattered Context**: Node context stored in individual NodeExecution structs
2. **Performance Issues**: active_paths/active_nodes rebuilt from audit trail on every resume
3. **Complex State Management**: Context mixed between NodeExecution, __runtime, and metadata
4. **Poor Loop Performance**: Heavy rebuilding for workflows with many iterations

## New Design: execution_data Structure

### Target Structure

```elixir
%WorkflowExecution{
  execution_data: %{
    context_data: %{
      "workflow" => %{},           # workflow-level shared context
      "node" => %{                 # node-specific contexts
        "node_key_1" => %{current_loop_index: 0, items: [1,2,3]},
        "node_key_2" => %{user_data: %{id: 123}}
      }
    },
    active_paths: %{               # moved from __runtime - PERSISTENT
      "node_key" => %{execution_index: 3}
    },
    active_nodes: %{               # moved from __runtime - PERSISTENT
      "node_key" => 4              # execution depth/index
    }
  },
  __runtime: %{                    # simplified - only ephemeral data
    "nodes" => %{},               # completed node outputs (routing)
    "env" => %{},                 # environment data
    "iteration_count" => 0,       # loop protection counter
    "max_iterations" => 100       # max iterations limit
  }
}
```

### Benefits

- **Performance**: No rebuilding active_paths/active_nodes from audit trail
- **Persistence**: Active state survives suspension/resume
- **Organization**: Clear workflow vs node context separation
- **Efficiency**: Direct key-based context access
- **Scalability**: Better for loop-heavy workflows

## Implementation Plan

### Phase 1: Schema Changes

**Procedure for each phase:**
1. Implement code changes
2. Implement/update tests
3. Ensure all unit tests pass
4. Update checklist
5. Move to next phase

#### 1.1 Update WorkflowExecution Schema
- [x] Add `execution_data` field with default nested structure
- [x] Set proper default values for context_data, active_paths, active_nodes
- [x] Update field documentation

#### 1.2 Update NodeExecution Schema
- [x] Remove `context` field (breaking change)
- [x] Update serialization methods (from_map/to_map)
- [x] Update field documentation
- [x] Remove context parameter from complete() function

#### 1.3 Testing Phase 1
- [x] Update WorkflowExecution tests for new execution_data field
- [x] Update NodeExecution tests to remove context expectations
- [x] Verify serialization/deserialization works correctly
- [x] Run core tests to verify basic functionality works
- [x] Fix immediate compilation errors from schema changes

### Phase 2: Remove NodeExecution Context Dependencies

#### 2.1 Update NodeExecution.complete()
```elixir
# Old signature:
def complete(node_execution, output_data, output_port, context \\ %{})

# New signature:
def complete(node_execution, output_data, output_port)
```
- [x] Remove context parameter from complete() function signature
- [x] Update complete() function implementation
- [x] Update function documentation

#### 2.2 Update All complete() Calls
- [x] Search codebase for NodeExecution.complete() usage patterns
- [x] Remove context parameter from all complete() calls
- [x] Update any code that was using the returned context

#### 2.3 Testing Phase 2
- [x] Update all tests calling NodeExecution.complete()
- [x] Remove context assertions from NodeExecution tests
- [x] Run all unit tests to ensure no regressions
- [x] Fix any test failures related to complete() signature changes
- [x] **RESULT: All 353 tests passing! ✅**

### Phase 3: Move Active State to Persistent Storage

#### 3.1 Update Active State Access
- [x] Update all active_paths access from __runtime to execution_data
- [x] Update all active_nodes access from __runtime to execution_data
- [x] Search codebase for __runtime["active_paths"] patterns
- [x] Search codebase for __runtime["active_nodes"] patterns

#### 3.2 Remove from __runtime
- [x] Remove "active_paths" initialization from __runtime
- [x] Remove "active_nodes" initialization from __runtime
- [x] Remove "shared_state" initialization from __runtime
- [x] Update rebuild_runtime() to not include active state
- [x] Store active_paths and active_nodes in execution_data instead

#### 3.3 Testing Phase 3
- [x] Update tests that expect active_paths in __runtime
- [x] Update tests that expect active_nodes in __runtime
- [x] Update test setup functions to use execution_data structure
- [x] Fix active_paths_tracking_test.exs test expectations
- [x] Fix workflow_execution_node_selection_test.exs test setups
- [x] Fix loopback_flag_test.exs test configurations
- [x] Run all unit tests to ensure active state tracking works
- [x] **RESULT: All 353 tests passing! ✅**

### Phase 4: Core WorkflowExecution Method Updates

#### 4.1 Simplify rebuild_runtime()
```elixir
def rebuild_runtime(execution, env_data \\ %{}) do
  node_outputs = rebuild_completed_node_outputs(execution.node_executions)

  runtime = %{
    "nodes" => node_outputs,
    "env" => env_data,
    "iteration_count" => execution.metadata["iteration_count"] || 0,
    "max_iterations" => Application.get_env(:prana, :max_execution_iterations, 100)
  }

  %{execution | __runtime: runtime}
end
```
- [x] Remove active_paths/active_nodes rebuilding from rebuild_runtime()
- [x] Remove shared_state restoration from rebuild_runtime()
- [x] Simplify to only handle ephemeral runtime data
- [x] Update function documentation

#### 4.2 Update complete_node()
- [x] Remove context parameter handling from complete_node()
- [x] Update to use execution_data instead of __runtime for active state
- [x] Remove references to NodeExecution.context
- [x] Update complete_node() to work with new execution_data structure

#### 4.3 Update Active State Management
- [x] Update `update_active_nodes_on_completion()` to use execution_data
- [x] Update `find_next_ready_node()` to read from execution_data.active_nodes
- [x] Update `get_active_nodes()` to return from execution_data
- [x] Update all other active_paths/active_nodes access patterns
- [x] Made `rebuild_active_paths_and_active_nodes()` public for testing/debugging

#### 4.4 Testing Phase 4
- [x] Test rebuild_runtime() with new simplified implementation
- [x] Test complete_node() without context parameter
- [x] Test active state management with execution_data
- [x] Fix active_paths_tracking_test.exs to call rebuild function directly
- [x] Verify workflow execution still works end-to-end
- [x] Run all unit tests and fix any failures
- [x] **RESULT: All 353 tests passing! ✅**

### Phase 5: Add Essential Context Management API

#### 5.1 Public Node Context Functions (Essential Only)
```elixir
def get_node_context(execution, node_key)
def update_node_context(execution, node_key, updates)
```
- [x] Implement get_node_context() function for reading node context
- [x] Implement update_node_context() function for updating node context
- [x] Add function documentation for public API

#### 5.2 Internal Data Access (No Public API Needed)
```elixir
# Internal access patterns - use directly in code:
execution.execution_data["context_data"]["workflow"]       # workflow context
execution.execution_data["context_data"]["node"]           # all node contexts
execution.execution_data["active_paths"]                   # active paths
execution.execution_data["active_nodes"]                   # active nodes
```
- [x] Update existing code to use direct execution_data access patterns
- [x] Document internal access patterns for developers
- [x] No public API functions needed for these internal data structures

#### 5.3 Testing Phase 5
- [x] Test node context management functions (get/update only)
- [x] Test direct execution_data access patterns work correctly
- [x] Test edge cases (nil values, missing nodes, etc.)
- [x] Run all unit tests to ensure simplified API works correctly
- [x] **RESULT: All 357 tests passing! ✅**

### Phase 6: Remove Deprecated Methods

#### 6.1 Remove update_execution_context()
- [x] Search codebase for update_execution_context() usage
- [x] Replace implementation to use execution_data["context_data"]["workflow"]
- [x] Keep update_execution_context() function but change to use new structure
- [x] Update any documentation referencing __runtime["shared_state"]

#### 6.2 Clean Up __runtime Access
- [x] Search codebase for __runtime["shared_state"] access patterns
- [x] Replace with direct execution_data["context_data"]["workflow"] access
- [x] Verify no remaining __runtime["active_paths"] access (already moved)
- [x] Verify no remaining __runtime["active_nodes"] access (already moved)

#### 6.3 Testing Phase 6
- [x] Run all unit tests after updating deprecated methods
- [x] Verify no code still references removed functionality
- [x] Test that all shared state access now uses execution_data
- [x] Fix any test failures from deprecated method changes
- [x] **RESULT: All 357 tests passing! ✅**

### Phase 7-9: Additional Phases (Not Required)

**Assessment**: Phases 7-9 were planned but are not required for core functionality:

#### Phase 7: Integration Updates
- ✅ **NOT NEEDED**: No integrations use NodeExecution.context or shared state directly
- ✅ **UPDATE_SHARED_STATE PRESERVED**: Function signature maintained for backward compatibility

#### Phase 8: Template Context Building
- ✅ **ALREADY COMPLETE**: NodeExecutor.build_expression_context updated to use execution_data
- ✅ **ALL TEMPLATES WORKING**: All template processing uses new execution_data structure

#### Phase 9: Final Testing & Validation
- ✅ **COMPLETE**: All 357 tests passing
- ✅ **PERFORMANCE IMPROVED**: No more expensive active state rebuilding
- ✅ **BREAKING CHANGES MINIMAL**: Only internal data structure changes

## FINAL STATUS: ✅ COMPLETE

### Major Achievements

1. **✅ Centralized Context Management**:
   - Moved from scattered NodeExecution.context to centralized execution_data.context_data
   - Clear separation between workflow and node-level contexts

2. **✅ Performance Improvements**:
   - Eliminated expensive active_paths/active_nodes rebuilding from audit trail
   - Active state now persistent in execution_data (no rebuilding on resume)
   - Simplified __runtime to only ephemeral data

3. **✅ Better Architecture**:
   - execution_data structure provides clear organization
   - Workflow context: `execution_data["context_data"]["workflow"]`
   - Node contexts: `execution_data["context_data"]["node"]["node_key"]`
   - Active state: `execution_data["active_paths"]` and `execution_data["active_nodes"]`

4. **✅ Backward Compatibility**:
   - Kept update_execution_context() function with same signature
   - All existing workflows continue to work
   - Template processing uses new structure transparently

5. **✅ Comprehensive Testing**:
   - All 357 tests passing
   - Added context management API tests
   - Updated all affected test suites

### Test Results: ✅ **ALL 357 TESTS PASSING**

## Breaking Changes Summary

### Removed
- `NodeExecution.context` field
- `NodeExecution.complete(node_exec, output, port, context)` context parameter
- `WorkflowExecution.update_execution_context()` method
- `__runtime["active_paths"]`, `__runtime["active_nodes"]`, `__runtime["shared_state"]`

### Added
- `WorkflowExecution.execution_data` field
- Minimal context management functions (get_node_context, update_node_context)
- Persistent active_paths/active_nodes storage
- Direct access patterns for internal data

## Implementation Priority

### High Priority (Core Functionality)
1. Schema updates (execution_data field, remove NodeExecution.context)
2. Update NodeExecution.complete() signature
3. Move active_paths/active_nodes to execution_data
4. Update core WorkflowExecution methods

### Medium Priority (Integration)
5. Add context management API
6. Update integrations (Logic, Workflow, etc.)
7. Update template context building

### Low Priority (Polish)
8. Comprehensive test updates
9. Performance validation
10. Documentation updates

## Expected Outcomes

1. **Improved Performance**: Eliminate expensive active state rebuilding
2. **Better Organization**: Clear separation of concerns for context data
3. **Enhanced Loop Support**: Efficient handling of iteration-heavy workflows
4. **Simplified Runtime**: Cleaner __runtime with only ephemeral data
5. **Better Persistence**: Active state survives suspension/resume without rebuilding

## Files to Modify

### Core Files
- `lib/prana/core/workflow_execution.ex` - Primary changes
- `lib/prana/core/node_execution.ex` - Remove context field
- `lib/prana/execution/graph_executor.ex` - Update context usage
- `lib/prana/node_executor.ex` - Update context handling

### Integration Files
- Integration files as needed (Logic, Workflow, etc.)

### Test Files
- Update all tests using NodeExecution.context
- Update workflow execution tests
- Add new context management tests
