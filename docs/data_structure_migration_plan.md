# Data Structure Migration Plan

## Current Status: Phase 2 ✅ COMPLETED + Dynamic Ports Enhancement
**Last Updated:** June 29, 2025  
**Branch:** `feature/data-structure-migration`  
**Commit:** Latest - Enhanced Switch Implementation with condition-based routing and dynamic ports

### Progress Summary
- ✅ **Phase 1: Core Data Structure Updates** - COMPLETED
- ✅ **Phase 2: Enhanced Switch Implementation** - COMPLETED  
- ✅ **Phase 4: Update Core Engine** - COMPLETED (done in Phase 1)
- ✅ **Phase 5: Testing Updates** - COMPLETED (done in Phase 1)
- ⏳ **Phase 7: Cleanup** - PENDING

### Key Achievements
- Connection struct simplified: `from_node_id`/`to_node_id` → `from`/`to`, `data_mapping` → `mapping`
- Removed redundant `id` and `conditions` fields from connections
- Updated all core execution modules (WorkflowCompiler, GraphExecutor, ExecutionContext)
- All critical tests passing (31/31 tests including conditional branching and dynamic ports)
- Backward compatibility maintained in `Connection.from_map/1`
- **Enhanced switch implementation** with condition-based routing (Phase 2)
- **Dynamic output ports** using `["*"]` marker for flexible port names

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

### Phase 1: Core Data Structure Updates (Week 1) ✅ COMPLETED

#### 1.1 Update Structs
- [x] ~~Modify `Prana.Node` struct field: `configuration` → `config`~~ (Not needed - Node uses `input_map`)
- [x] Modify `Prana.Connection` struct fields:
  - `from_node_id` → `from` ✅
  - `to_node_id` → `to` ✅
  - `from_port` → `from_port` ✅ (already correct)
  - `to_port` → `to_port` ✅ (already correct)
  - `data_mapping` → `mapping` ✅
  - Remove `id` field ✅
  - Remove `conditions` field ✅

#### 1.2 Update Type Definitions
- [x] Update struct definitions in `lib/prana/core/` ✅
- [x] Update documentation and @doc strings ✅
- [x] Update type specs and @type definitions ✅

### Phase 2: Enhanced Switch Implementation (Week 1-2) ✅ COMPLETED

#### 2.1 Create Enhanced Switch Action
- [x] Update `lib/prana/integrations/logic.ex` ✅
- [x] Add condition-based switch support ✅
- [x] Remove legacy value-based switch format ✅

#### 2.2 Switch Configuration Schema ✅ IMPLEMENTED
```elixir
# New condition-based format (IMPLEMENTED):
%{
  "cases" => [
    %{"condition" => "$input.tier", "value" => "premium", "port" => "premium_port"},
    %{"condition" => "$input.verified", "value" => true, "port" => "verified_port"}
  ],
  "default_port" => "default",
  "default_data" => %{"message" => "no match"}
}
```

#### 2.3 Testing Updates ✅ COMPLETED
- [x] Updated all conditional branching tests to new format ✅
- [x] Added new Logic integration tests ✅
- [x] All 28 tests passing ✅

#### 2.4 Dynamic Ports Enhancement ✅ COMPLETED
- [x] Implemented `["*"]` marker for dynamic output ports ✅
- [x] Enhanced NodeExecutor validation with `allows_dynamic_ports?/1` helper ✅
- [x] Updated Logic switch action to support any custom port name ✅
- [x] Added comprehensive dynamic ports test suite ✅
- [x] Updated documentation for dynamic ports feature ✅


### Phase 4: Update Core Engine (Week 2-3) ✅ COMPLETED

#### 4.1 Workflow Compiler Updates
- [x] Update `lib/prana/execution/workflow_compiler.ex` ✅
- [x] Handle new field names in compilation ✅
- [x] Update connection resolution logic ✅

#### 4.2 Graph Executor Updates
- [x] Update `lib/prana/execution/graph_executor.ex` ✅
- [x] Remove connection condition evaluation ✅ (conditions field removed)
- [x] Update node execution with new field names ✅

#### 4.3 Expression Engine
- [x] Ensure compatibility with new field names ✅
- [x] Update path resolution if needed ✅ (no changes needed)

### Phase 5: Testing Updates (Week 3) ✅ COMPLETED

#### 5.1 Update Test Data
- [x] Update all test workflows to use new format ✅
- [x] Update test assertions for new field names ✅
- [x] Add migration tests ✅ (backward compatibility in Connection.from_map/1)

#### 5.2 Test Coverage
- [x] Test both old and new format support ✅ (backward compatibility implemented)
- [x] Test enhanced switch functionality ✅ (31 tests passing including dynamic ports)
- [x] Test dynamic output ports functionality ✅


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

1. ✅ **Start with structs** - Core data changes (COMPLETED)
2. ✅ **Add enhanced switch** - New functionality with dynamic ports (COMPLETED)  
3. ✅ **Update engine** - Core execution logic (COMPLETED)
4. ✅ **Update tests** - Ensure stability (COMPLETED)
5. ⏳ **Clean up** - Remove legacy code (PENDING)

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

## Dynamic Output Ports Feature

As part of Phase 2, we implemented a flexible dynamic output ports system:

### Implementation
- **Marker**: Actions use `output_ports: ["*"]` to indicate dynamic port support
- **Validation**: NodeExecutor detects `["*"]` and bypasses port name validation
- **Flexibility**: Actions can return any custom port name at runtime

### Benefits
- **Semantic Names**: Use `"premium_users"` instead of `"output_1"`  
- **Self-Documenting**: Port names indicate their purpose in workflows
- **Unlimited Scenarios**: Support any number of routing outcomes
- **Better UX**: More intuitive than numbered outputs

### Example Usage
```elixir
# Action returns custom port names
{:ok, data, "premium_port"}     # ✅ Allowed
{:ok, data, "verified_user"}    # ✅ Allowed  
{:ok, data, "special_case"}     # ✅ Allowed

# Fixed-port actions still validated
{:ok, data, "invalid_port"}     # ❌ Rejected if not in output_ports list
```