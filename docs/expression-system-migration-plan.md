# Expression System Migration Plan

**Date**: July 2025
**Status**: Draft
**Purpose**: Migrate from `$node.{node_id}` to `$node.{node_id}.output` for extensible node attributes

## Overview

The current expression system uses `$node.{node_id}` to directly access node output data. To support loop contexts and other node attributes, we need to refactor to a structured approach: `$node.{node_id}.output` for output data and `$node.{node_id}.context` for context data.

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

### Phase 1: Extend Expression Engine (Backwards Compatible)
**Duration**: 1-2 weeks
**Risk**: Low

#### 1.1 Update Expression Engine
- **Modify** `lib/prana/expression_engine.ex` to support both patterns:
  - `$node.{node_id}` → direct output access (backwards compatible)
  - `$node.{node_id}.output` → structured output access (new)
  - `$node.{node_id}.context` → context access (new)

#### 1.2 Update NodeExecution Structure
- **Extend** `%NodeExecution{}` to include context field:
```elixir
%NodeExecution{
  node_id: "node_123",
  output: %{...},       # Existing output data
  context: %{...},      # New context data
  status: :completed,   # Existing status
  # ... other fields
}
```

#### 1.3 Update GraphExecutor
- **Modify** `lib/prana/execution/graph_executor.ex` to populate context data
- **Add** context management for loop nodes

#### 1.4 Add Comprehensive Tests
- Test both old and new expression patterns
- Test context access patterns
- Test nested access patterns

### Phase 2: Deprecation Warning System
**Duration**: 1 week
**Risk**: Low

#### 2.1 Add Deprecation Warnings
- **Add** warning system to expression engine
- **Log** deprecation warnings when old patterns are used
- **Provide** migration hints in warnings

#### 2.2 Update Documentation
- **Add** migration guide
- **Update** all documentation to use new patterns
- **Mark** old patterns as deprecated

### Phase 3: Gradual Migration
**Duration**: 2-3 weeks
**Risk**: Medium

#### 3.1 Update Built-in Integrations
- **Migrate** all built-in integrations to new patterns
- **Update** integration tests
- **Verify** functionality remains intact

#### 3.2 Update Test Suite
- **Migrate** all test expressions to new patterns
- **Add** tests for new context access patterns
- **Ensure** full test coverage

#### 3.3 Update Documentation
- **Migrate** all documentation examples
- **Update** workflow building guides
- **Create** migration examples

### Phase 4: Remove Backwards Compatibility
**Duration**: 1 week
**Risk**: High (Breaking Change)

#### 4.1 Remove Old Pattern Support
- **Remove** backwards compatibility from expression engine
- **Update** error messages to guide users
- **Ensure** clean error handling

#### 4.2 Final Testing
- **Run** full test suite
- **Verify** all integrations work
- **Test** example workflows

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

| Phase | Duration | Key Deliverables |
|-------|----------|------------------|
| Phase 1 | 1-2 weeks | Extended expression engine with backwards compatibility |
| Phase 2 | 1 week | Deprecation warnings and updated documentation |
| Phase 3 | 2-3 weeks | All integrations and tests migrated |
| Phase 4 | 1 week | Backwards compatibility removed |
| **Total** | **5-7 weeks** | **Complete migration with loop support** |

## Success Criteria

### Phase 1 Success
- [ ] Expression engine supports both old and new patterns
- [ ] NodeExecution structure includes context field
- [ ] All existing tests pass
- [ ] New expression patterns work correctly

### Phase 2 Success
- [ ] Deprecation warnings logged for old patterns
- [ ] Documentation updated with new patterns
- [ ] Migration guide available

### Phase 3 Success
- [ ] All built-in integrations use new patterns
- [ ] All tests use new patterns
- [ ] No deprecation warnings in test suite

### Phase 4 Success
- [ ] Old patterns no longer supported
- [ ] Clean error messages for old patterns
- [ ] All functionality preserved
- [ ] Loop contexts accessible via new patterns

## Post-Migration Benefits

1. **Extensible Node Attributes**: Can add status, metadata, timing data
2. **Loop Context Support**: Clean nested loop context access
3. **Consistent API**: Structured access pattern for all node data
4. **Future-Proof**: Foundation for additional node attributes

## References

- [ADR-006: Loop Integration Design](./adr/006-loop-integration-design.md)
- [Expression Engine Implementation](../lib/prana/expression_engine.ex)
- [NodeExecution Structure](../lib/prana/core/node_execution.ex)
- [GraphExecutor Implementation](../lib/prana/execution/graph_executor.ex)