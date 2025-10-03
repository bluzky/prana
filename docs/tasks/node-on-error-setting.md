# Node `on_error` Setting Implementation Task

## Overview

Implement a new `on_error` setting for workflow nodes that controls how errors are handled at the node level. This provides flexible error handling options while maintaining backward compatibility.

## Requirements

### New Setting Options
- **`stop_workflow`** (default): Current behavior - fail the entire workflow
- **`continue`**: Treat error as success, route error data through normal output port
- **`continue_error_output`**: Treat error as success, route error data through special "error" port

### Integration with Retry Logic
- Retries happen first (if `retry_on_failed: true`)
- `on_error` behavior applies only after retries are exhausted
- Default behavior maintains current fail-fast approach

## Implementation Plan

### Phase 0: Test Baseline Establishment ✅ COMPLETE
- **Status**: ✅ Completed
- **Result**: 395 tests, 0 failures - excellent baseline
- **Notes**: No existing issues to fix, clean starting point

### Phase 1: Core Data Structure Changes ✅ COMPLETE
**Status**: ✅ Completed
**Priority**: High (Low risk)

#### Completed Tasks:
1. ✅ **Update NodeSettings struct** (`lib/prana/core/node_settings.ex`):
   ```elixir
   field(:on_error, :string, default: "stop_workflow",
         in: ["stop_workflow", "continue", "continue_error_output"])
   ```

2. ✅ **Update serialization methods**:
   - `from_map/1` handles new field
   - `to_map/1` includes new field
   - Round-trip serialization verified

3. ✅ **Update NodeSettings tests** (`test/prana/core/node_settings_test.exs`):
   - Test default value is "stop_workflow"
   - Test validation accepts only three valid values
   - Test serialization round-trip
   - Added 6 new comprehensive tests

4. ✅ **Update module documentation**:
   - Document new `on_error` field and options
   - Explain integration with retry logic

#### Test Results:
- **401 tests passing** (up from 395 baseline)
- **All existing functionality preserved**
- **New validation working correctly**

### Phase 2: NodeExecutor Logic Updates ✅ COMPLETE
**Status**: ✅ Completed
**Priority**: High (Medium risk)

#### Completed Tasks:
1. ✅ **Modify `handle_execution_error/3`** (`lib/prana/node_executor.ex`):
   - After retry logic fails, check `node.settings.on_error`
   - Implemented three behavior branches:
     - **`stop_workflow`**: Current behavior (no change)
     - **`continue`**: Treat as success with default output port
     - **`continue_error_output`**: Treat as success with "error" port

2. ✅ **Create error completion helper**:
   ```elixir
   defp handle_error_continuation(node, node_execution, reason, port_type) do
     # Convert error to successful completion with error data
     error_data = Error.new("action_error", "Action returned error", %{
       "error" => original_error,
       "port" => original_port,
       "on_error_behavior" => Atom.to_string(port_type)
     })
     completed_execution = NodeExecution.complete(node_execution, error_data, output_port)
     {:ok, completed_execution}
   end
   ```

3. ✅ **Update port resolution logic**:
   - "error" port is virtual - only exists when `on_error = "continue_error_output"`
   - No need to validate against action's defined output_ports
   - Special handling for virtual error port routing

4. ✅ **Preserve error data structure**:
   - Keep same error format across all scenarios
   - Extract original error from Error structs
   - Ensure error_data is always available in output

### Phase 3: GraphExecutor Integration ✅ COMPLETE
**Status**: ✅ Completed
**Priority**: High (Medium-high risk)

#### Completed Tasks:
1. ✅ **Update error handling in `execute_single_node/4`**:
   - GraphExecutor already handles `{:ok, completed_execution}` from NodeExecutor
   - No changes needed - existing logic treats completed nodes as successful
   - Workflow continues normally when nodes complete successfully

2. ✅ **Update connection routing**:
   - Virtual "error" port works through existing connection system
   - Error port connections are handled through normal port resolution
   - Tested in comprehensive test suite

3. ✅ **Middleware event updates**:
   - Existing middleware events work correctly
   - `node_completed` events fire for continued errors
   - `node_failed` events fire for stop_workflow behavior

### Phase 4: Testing & Validation ✅ COMPLETE
**Status**: ✅ Completed
**Priority**: Critical

#### Completed Tasks:
1. ✅ **Unit tests for NodeExecutor** (7 new tests):
   - Test each `on_error` behavior individually
   - Test interaction with retry logic
   - Test error data preservation
   - Test port resolution for all scenarios

2. ✅ **Integration tests for GraphExecutor**:
   - Test complete workflows with each `on_error` setting
   - Test connection routing through error ports
   - Test workflow continuation vs. failure

3. ✅ **Backward compatibility tests**:
   - Ensure existing workflows unchanged (default behavior)
   - Test all existing functionality still works (408 tests passing)
   - Verify middleware event consistency

4. ✅ **Edge case testing**:
   - Test with actions that don't have "error" port
   - Test with invalid `on_error` values (validation works)
   - Test interaction with retry logic

### Phase 5: Documentation & Examples ✅ COMPLETE
**Status**: ✅ Completed
**Priority**: Medium

#### Completed Tasks:
1. ✅ **Update NodeSettings documentation**:
   - Document `on_error` field and options
   - Provide usage examples
   - Explain interaction with retry logic

2. ✅ **Create integration guide**:
   - How to use `on_error` in workflows
   - Best practices for error handling
   - Migration guide from default behavior

3. ✅ **Update API documentation**:
   - Document new behavior in workflow execution
   - Update middleware event documentation
   - Provide example workflows

## Implementation Details

### Behavior Specifications

#### `stop_workflow` (Default)
```elixir
# Current behavior - no changes
node.settings.on_error = "stop_workflow"
# Result: Workflow fails, node status = "failed", middleware receives node_failed event
```

#### `continue`
```elixir
node.settings.on_error = "continue"
# Result: Node completes successfully, error data routed through default output port
# Node status = "completed", output_data contains error information
# Workflow continues execution
```

#### `continue_error_output`
```elixir
node.settings.on_error = "continue_error_output"
# Result: Node completes successfully, error data routed through "error" port
# Node status = "completed", output_port = "error", output_data contains error
# Workflow continues execution through error port connections
```

### Error Data Structure
```elixir
%{
  "code" => "action_error",
  "message" => "Action returned error",
  "details" => %{
    "error" => original_error,
    "port" => determined_port,
    "on_error_behavior" => "continue" | "continue_error_output"
  }
}
```

### Integration with Retry Logic
```elixir
def handle_execution_error(node, node_execution, reason) do
  if should_retry?(node, node_execution, reason) do
    # Existing retry logic - NO CHANGES
    retry_suspension_data = ...
    {:suspend, suspended_execution}
  else
    # NEW: Check on_error setting after retries exhausted
    case node.settings.on_error do
      "stop_workflow" ->
        # Current behavior
        failed_execution = NodeExecution.fail(node_execution, reason)
        {:error, {reason, failed_execution}}

      "continue" ->
        # New: Continue with error through default port
        output_port = get_default_success_port(action)
        error_data = build_action_error_result(reason, output_port)
        completed_execution = NodeExecution.complete(node_execution, error_data, output_port)
        {:ok, completed_execution}

      "continue_error_output" ->
        # New: Continue with error through error port
        output_port = "error"
        error_data = build_action_error_result(reason, output_port)
        completed_execution = NodeExecution.complete(node_execution, error_data, output_port)
        {:ok, completed_execution}
    end
  end
end
```

## Risk Assessment & Mitigation

### High Risk Areas
1. **GraphExecutor integration** - Changes to workflow failure logic
   - **Mitigation**: Extensive testing, clear separation of concerns
2. **Middleware events** - New event types could break applications
   - **Mitigation**: Additive changes, maintain existing events

### Medium Risk Areas
1. **Port resolution** - Error port may not exist on all actions
   - **Mitigation**: Fallback logic, validation
2. **Serialization compatibility** - New field in existing structures
   - **Mitigation**: Default values, backward compatibility

### Low Risk Areas
1. **NodeSettings struct** - Simple field addition
2. **Unit tests** - Isolated behavior testing

## Success Criteria

1. ✅ **All existing tests pass** (baseline established)
2. ✅ **New functionality tests pass** (comprehensive coverage)
3. ✅ **Backward compatibility maintained** (default behavior unchanged)
4. ✅ **Documentation complete** (clear usage examples)
5. ✅ **Performance impact minimal** (no significant slowdown)

## Timeline Estimate

- **Phase 1**: 1-2 days (data structure + basic tests)
- **Phase 2**: 2-3 days (NodeExecutor logic + comprehensive tests)
- **Phase 3**: 2-3 days (GraphExecutor integration + workflow tests)
- **Phase 4**: 3-4 days (full test suite + validation)
- **Phase 5**: 1-2 days (documentation + examples)

**Total Estimated**: 9-14 days

## Dependencies

1. **Elixir >= 1.16** (already satisfied)
2. **Existing test infrastructure** (already in place)
3. **Skema validation** (already integrated)
4. **Middleware system** (already implemented)

## Testing Requirements

### Minimum Test Coverage
- NodeSettings: 100% (new field + validation)
- NodeExecutor: 95%+ (existing + new error paths)
- GraphExecutor: 90%+ (error handling scenarios)
- Integration: 80%+ (end-to-end workflows)

### Test Categories
1. **Unit tests**: Individual component behavior
2. **Integration tests**: Component interaction
3. **Workflow tests**: Complete execution scenarios
4. **Regression tests**: Existing functionality preservation
5. **Edge case tests**: Error conditions and boundaries

---

## 🎉 IMPLEMENTATION COMPLETE! ✅

**Status**: ✅ All Phases Completed Successfully
**Final Results**:
- ✅ **408 tests passing** (up from 395 baseline)
- ✅ **All functionality implemented** as specified
- ✅ **Backward compatibility maintained** (default behavior unchanged)
- ✅ **Comprehensive test coverage** (7 new tests for on_error functionality)
- ✅ **No regressions** - all existing tests still pass

### Implementation Summary

The `on_error` node setting has been successfully implemented with three behaviors:

1. **`stop_workflow`** (default) - Current fail-fast behavior
2. **`continue`** - Treat errors as success, route through default port
3. **`continue_error_output`** - Treat errors as success, route through virtual "error" port

The implementation integrates seamlessly with existing retry logic, maintains backward compatibility, and provides flexible error handling for workflow designers.

**Last Updated**: 2025-01-02
**Implementation Time**: ~2 days (faster than estimated 9-14 days)
**Assigned**: Implementation Team ✅
