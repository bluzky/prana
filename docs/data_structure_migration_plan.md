# Data Structure Migration Plan

## Overview
This document outlines the migration plan to simplify Prana's data structure for better JSON serialization/deserialization while maintaining functionality.

## Summary of Changes

### Field Name Simplifications
```elixir
# Current → New
configuration → config
source_node_id → from  
target_node_id → to
source_port → from_port
target_port → to_port
data_mapping → mapping
```

### Removed Fields
- Remove `id` field from connections
- Remove `condition` field from connections

### Enhanced Switch Node
Replace connection conditions with enhanced switch supporting condition expressions:

```elixir
# Enhanced switch (condition-based)
%Prana.Node{
  type: "switch", 
  config: %{
    "cases" => [
      %{
        "condition" => "$input.tier == 'premium' && $input.verified == true",
        "port" => "premium_port"
      }
    ],
    "default_port" => "default"
  }
}
```

## Migration Phases

### Phase 1: Core Data Structure Updates (Week 1)

#### 1.1 Update Structs
- [ ] Modify `Prana.Node` struct field: `configuration` → `config`
- [ ] Modify `Prana.Connection` struct fields:
  - `source_node_id` → `from`
  - `target_node_id` → `to`
  - `source_port` → `from_port`
  - `target_port` → `to_port`
  - `data_mapping` → `mapping`
  - Remove `id` field
  - Remove `condition` field

#### 1.2 Update Type Definitions
- [ ] Update struct definitions in `lib/prana/core/`
- [ ] Update documentation and @doc strings
- [ ] Update type specs and @type definitions

### Phase 2: Enhanced Switch Implementation (Week 1-2)

#### 2.1 Create Enhanced Switch Action
- [ ] Update `lib/prana/integrations/logic.ex`
- [ ] Add condition-based switch support alongside value-based
- [ ] Support both old and new switch formats during transition

#### 2.2 Switch Configuration Schema
```elixir
# Support both formats:
# Old: %{"expression" => "$input.tier", "cases" => %{"premium" => "port"}}
# New: %{"cases" => [%{"condition" => "expr", "port" => "port"}]}
```

### Phase 3: Serialization/Deserialization (Week 2)

#### 3.1 JSON Encoding/Decoding
- [ ] Update `Jason.Encoder` implementations for structs
- [ ] Create migration functions: `old_format_to_new/1`, `new_format_to_old/1`
- [ ] Add validation for new format

#### 3.2 Backward Compatibility
- [ ] Create format detection: `detect_format/1`
- [ ] Auto-migration during workflow loading
- [ ] Support both formats in API endpoints

### Phase 4: Update Core Engine (Week 2-3)

#### 4.1 Workflow Compiler Updates
- [ ] Update `lib/prana/execution/workflow_compiler.ex`
- [ ] Handle new field names in compilation
- [ ] Update connection resolution logic

#### 4.2 Graph Executor Updates
- [ ] Update `lib/prana/execution/graph_executor.ex`
- [ ] Remove connection condition evaluation
- [ ] Update node execution with new field names

#### 4.3 Expression Engine
- [ ] Ensure compatibility with new field names
- [ ] Update path resolution if needed

### Phase 5: Testing Updates (Week 3)

#### 5.1 Update Test Data
- [ ] Update all test workflows to use new format
- [ ] Update test assertions for new field names
- [ ] Add migration tests

#### 5.2 Test Coverage
- [ ] Test both old and new format support
- [ ] Test enhanced switch functionality
- [ ] Test JSON serialization/deserialization

### Phase 6: Documentation & Migration Tools (Week 3-4)

#### 6.1 Migration Utilities
- [ ] Create CLI migration tool
- [ ] Batch workflow migration scripts
- [ ] Validation tools for migrated workflows

#### 6.2 Documentation Updates
- [ ] Update README and guides
- [ ] Update examples in documentation
- [ ] Create migration guide for users

### Phase 7: Cleanup (Week 4)

#### 7.1 Remove Legacy Support
- [ ] Remove old format support after migration period
- [ ] Clean up migration utilities
- [ ] Remove backward compatibility code

#### 7.2 Performance Optimization
- [ ] Optimize new serialization paths
- [ ] Remove deprecated code paths
- [ ] Update benchmarks

## Implementation Order

1. **Start with structs** - Core data changes
2. **Add enhanced switch** - New functionality  
3. **Implement migration** - Backward compatibility
4. **Update engine** - Core execution logic
5. **Update tests** - Ensure stability
6. **Create tools** - User migration support
7. **Clean up** - Remove legacy code

## Risk Mitigation

- **Backward compatibility** during transition
- **Comprehensive testing** at each phase
- **Migration validation** tools
- **Rollback plan** if issues arise

## Benefits

1. **Cleaner JSON**: Shorter field names, less verbose
2. **Better Serialization**: More JSON-friendly structure
3. **Simplified Logic**: Single conditional routing mechanism (enhanced switch)
4. **Reduced Complexity**: Remove redundant connection conditions and IDs
5. **More Powerful**: Enhanced switch handles complex multi-condition routing

## Example Migration

### Before
```elixir
%Prana.Connection{
  id: "conn_1",
  source_node_id: "trigger_1",
  source_port: "success",
  target_node_id: "validate_1",
  target_port: "input",
  condition: "$input.enabled == true",
  data_mapping: %{"email" => "$output.email"}
}
```

### After
```elixir
%Prana.Connection{
  from: "trigger_1",
  from_port: "success",
  to: "validate_1",
  to_port: "input",
  mapping: %{"email" => "$output.email"}
}
```

These changes maintain all current functionality while producing cleaner, more maintainable JSON serialization.