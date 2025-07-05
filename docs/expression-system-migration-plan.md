# Expression System Migration Plan

**Date**: July 2025
**Status**: Phase 1 Complete ✅
**Purpose**: Migrate from `$node.{node_id}` to `$node.{node_id}.output` for extensible node attributes

## Overview

**✅ COMPLETED**: The expression system now supports structured node access patterns `$node.{node_id}.output` and `$node.{node_id}.context` for extensible node attributes, enabling loop context support and future node metadata access.

**Key Achievement**: Full backward compatibility maintained - existing `$nodes.{node_id}` patterns continue to work unchanged while new structured patterns are available for advanced use cases.

## Current State Analysis

### Expression Engine Location
- **Primary Implementation**: `lib/prana/expression_engine.ex`
- **Test Coverage**: `test/prana/expression_engine_test.exs`

### Current Expression Patterns
```elixir
# Direct node output access
"$node.api_call.user_id"              # Single value
"$node.api_call.response.user_id"     # Nested access
"$node.api_call.users.*.name"         # Wildcard access
"$node.api_call.users.{status: \"active\"}.email"  # Filtered access
```

### Usage Locations to Audit
1. **Built-in Integrations**:
   - `lib/prana/integrations/logic/if_condition_action.ex`
   - `lib/prana/integrations/logic/switch_action.ex`
   - `lib/prana/integrations/data/merge_action.ex`
   - `lib/prana/integrations/workflow/execute_workflow_action.ex`

2. **Test Files**:
   - `test/prana/expression_engine_test.exs`
   - `test/prana/execution/graph_executor_test.exs`
   - `test/prana/execution/graph_executor_conditional_branching_test.exs`
   - `test/prana/execution/graph_executor_sub_workflow_test.exs`

3. **Documentation**:
   - `docs/guides/building_workflows.md`
   - `docs/built-in-integrations.md`
   - Integration-specific documentation

## Migration Strategy

### ✅ Phase 1: Extend Expression Engine (Backwards Compatible) - COMPLETE
**Duration**: Completed
**Risk**: Low

#### ✅ 1.1 Update Expression Engine
- **COMPLETE** `lib/prana/expression_engine.ex` now supports both patterns:
  - `$nodes.{node_id}` → legacy pattern (fully backward compatible)
  - `$node.{node_id}.output` → structured output access (new)
  - `$node.{node_id}.context` → context access (new)

#### ✅ 1.2 Update NodeExecution Structure
- **COMPLETE** `%NodeExecution{}` includes context_data field:
```elixir
%NodeExecution{
  node_id: "node_123",
  output_data: %{...},       # Existing output data
  context_data: %{...},      # New context data (added)
  status: :completed,        # Existing status
  # ... other fields
}
```

#### ✅ 1.3 Update NodeExecutor 
- **COMPLETE** `lib/prana/node_executor.ex` supports context-aware action returns
- **COMPLETE** Added support for `{:ok, data, context}` and `{:ok, data, port, context}` patterns
- **COMPLETE** Context populated via clean `update_context/2` pattern

#### ✅ 1.4 Add Comprehensive Tests
- **COMPLETE** Expression engine supports new node patterns
- **COMPLETE** All 311 existing tests pass with new functionality
- **COMPLETE** New patterns work with wildcards, filtering, and array access

### Phase 2: Deprecation Warning System - OPTIONAL
**Duration**: 1 week (if needed)
**Risk**: Low
**Status**: Skipped - No deprecation needed due to clean backward compatibility

#### 2.1 Add Deprecation Warnings
- **DECISION**: Skip deprecation warnings - both patterns can coexist indefinitely
- **RATIONALE**: `$nodes` patterns remain useful for simple cases, `$node` patterns for advanced cases

#### 2.2 Update Documentation
- **TODO**: Update documentation to show both patterns
- **TODO**: Add examples of new structured patterns
- **TODO**: Document when to use each pattern

### Phase 3: Gradual Migration - OPTIONAL
**Duration**: As needed
**Risk**: Low
**Status**: No forced migration needed - patterns can coexist

#### 3.1 Update Built-in Integrations
- **DECISION**: No migration required - existing patterns work fine
- **FUTURE**: Use new patterns for loop integrations and advanced features
- **APPROACH**: Organic adoption as features require context data

#### 3.2 Update Test Suite
- **COMPLETE**: Core functionality tested with new patterns
- **FUTURE**: Add more context-specific tests as loop integration develops
- **STATUS**: All existing tests continue to pass

#### 3.3 Update Documentation
- **TODO**: Update workflow building guides with both patterns
- **TODO**: Show when to use `$nodes` vs `$node` patterns
- **TODO**: Add loop integration examples using context patterns

### Phase 4: Remove Backwards Compatibility - CANCELLED
**Duration**: N/A
**Risk**: N/A
**Status**: Cancelled - No need to remove backward compatibility

#### Rationale for Cancellation
- **Clean Coexistence**: Both patterns serve different use cases effectively
- **No Performance Impact**: Minimal overhead to support both patterns
- **User Experience**: No forced migration burden on existing workflows
- **Future-Proof**: Foundation ready for loop integrations without breaking changes

## Implementation Details

### Expression Engine Changes

```elixir
# Current implementation (simplified)
defp resolve_node_path(["$node", node_id | rest], context) do
  case Map.get(context.node_outputs, node_id) do
    nil -> {:error, "Node #{node_id} not found"}
    output -> resolve_nested_path(rest, output)
  end
end

# New implementation (backwards compatible)
defp resolve_node_path(["$node", node_id | rest], context) do
  case Map.get(context.node_executions, node_id) do
    nil -> 
      {:error, "Node #{node_id} not found"}
    
    %NodeExecution{} = node_execution ->
      case rest do
        # New pattern: $node.{node_id}.output.field
        ["output" | output_path] ->
          resolve_nested_path(output_path, node_execution.output)
        
        # New pattern: $node.{node_id}.context.field  
        ["context" | context_path] ->
          resolve_nested_path(context_path, node_execution.context)
        
        # Backwards compatible: $node.{node_id}.field
        direct_path ->
          # Log deprecation warning
          Logger.warn("Deprecated: $node.#{node_id}.field, use $node.#{node_id}.output.field")
          resolve_nested_path(direct_path, node_execution.output)
      end
  end
end
```

### NodeExecution Structure Updates

```elixir
# Current structure
%NodeExecution{
  node_id: "node_123",
  output: %{...},
  output_port: "success",
  status: :completed,
  error: nil,
  started_at: ~U[...],
  completed_at: ~U[...]
}

# New structure  
%NodeExecution{
  node_id: "node_123",
  output: %{...},           # Existing output data
  context: %{},             # New context data (empty by default)
  output_port: "success",
  status: :completed,
  error: nil,
  started_at: ~U[...],
  completed_at: ~U[...]
}
```

### Context Population for Loop Nodes

```elixir
# In loop action implementation
def execute(input, state) do
  # ... loop logic ...
  
  # Populate context for this node
  context = %{
    "batch_size" => state.batch_size,
    "has_more_item" => state.current_batch < state.total_batches - 1,
    "index" => state.current_batch
  }
  
  # Return with context
  {:ok, batch_output, updated_state, context}
end
```

## Testing Strategy

### Automated Testing
1. **Unit Tests**: Expression engine with both patterns
2. **Integration Tests**: All built-in integrations
3. **End-to-End Tests**: Complete workflows with new patterns
4. **Regression Tests**: Ensure backwards compatibility during transition

### Manual Testing
1. **Workflow Examples**: Test documented workflow examples
2. **Loop Scenarios**: Test simple and nested loop patterns
3. **Error Handling**: Test error messages and guidance

## Risk Mitigation

### Backwards Compatibility Risks
- **Mitigation**: Maintain backwards compatibility until Phase 4
- **Monitoring**: Log usage of old patterns to track migration progress
- **Support**: Provide clear migration guidance and examples

### Breaking Change Risks
- **Mitigation**: Extensive testing and documentation
- **Communication**: Clear timeline and migration instructions
- **Rollback**: Ability to revert if critical issues discovered

### Performance Risks
- **Mitigation**: Benchmark expression evaluation performance
- **Monitoring**: Profile memory usage with new structure
- **Optimization**: Optimize hot paths if needed

## Timeline

| Phase | Duration | Key Deliverables | Status |
|-------|----------|------------------|---------|
| ✅ Phase 1 | **Completed** | Extended expression engine with backwards compatibility | ✅ **DONE** |
| Phase 2 | **Skipped** | Deprecation warnings and updated documentation | **SKIPPED** |
| Phase 3 | **Organic** | All integrations and tests migrated | **ONGOING** |
| Phase 4 | **Cancelled** | Backwards compatibility removed | **CANCELLED** |
| **Total** | **Phase 1 Only** | **Foundation ready for loop support** | ✅ **ACHIEVED** |

## Success Criteria

### ✅ Phase 1 Success - ACHIEVED
- [x] Expression engine supports both old and new patterns
- [x] NodeExecution structure includes context_data field  
- [x] All existing tests pass (311 tests)
- [x] New expression patterns work correctly
- [x] Context-aware action returns implemented
- [x] Clean integration with existing codebase

### Phase 2 Success - SKIPPED
- [x] Decision made to skip deprecation warnings
- [ ] Documentation updated with both patterns (TODO)
- [ ] Usage guide for pattern selection (TODO)

### Phase 3 Success - ORGANIC APPROACH
- [x] Existing integrations continue working unchanged
- [x] New patterns available for loop integrations
- [ ] Documentation updated for both patterns (TODO)
- [x] Test coverage for new functionality

### Phase 4 Success - CANCELLED
- [x] Decision made to maintain backward compatibility permanently
- [x] Both patterns coexist cleanly
- [x] All functionality preserved
- [x] Loop contexts accessible via new patterns

## ✅ Achieved Benefits

1. **✅ Extensible Node Attributes**: Context field ready for loop metadata, timing data, etc.
2. **✅ Loop Context Support**: Clean structured access for iteration data via `$node.{id}.context`
3. **✅ Consistent API**: Structured access pattern available alongside legacy patterns
4. **✅ Future-Proof**: Foundation ready for loop integrations and advanced workflow features
5. **✅ Backward Compatibility**: Zero breaking changes - existing workflows continue unchanged
6. **✅ Action Context Support**: Actions can return context via `{:ok, data, context}` patterns

## Next Steps

1. **Loop Integration Development**: Use new context patterns for iteration tracking
2. **Documentation Updates**: Add examples showing both expression patterns
3. **Organic Adoption**: Teams can choose appropriate pattern for each use case

## Implementation Summary

**Commit**: `df1912c` - Implement Phase 1: Expression system migration  
**Files Changed**: 3 files, 75 insertions, 11 deletions  
**Test Status**: All 311 tests passing  
**Breaking Changes**: None

## References

- [ADR-006: Loop Integration Design](./adr/006-loop-integration-design.md)
- [Expression Engine Implementation](../lib/prana/expression_engine.ex)
- [NodeExecution Structure](../lib/prana/core/node_execution.ex)
- [GraphExecutor Implementation](../lib/prana/execution/graph_executor.ex)