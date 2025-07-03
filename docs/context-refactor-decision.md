# Context Refactor Decision Document

**Date**: January 3, 2025  
**Status**: Approved  
**Version**: 1.3

## Background

The current Prana codebase has multiple context structures that create complexity, duplication, and conversion overhead:

- **Execution** - Top-level workflow execution tracking
- **ExecutionContext** - Structured context for NodeExecutor (atom keys)  
- **OrchestrationContext** - Private map in GraphExecutor (string keys)
- **ExpressionContext** - Format for ExpressionEngine ($ prefixed keys)
- **NodeExecution** - Individual node execution state

These multiple contexts require constant conversion and synchronization, leading to performance overhead and maintenance complexity.

## Decision

### **Unified Execution Structure with Runtime State**

Refactor to a single, authoritative execution context that eliminates ExecutionContext and consolidates all context management:

```elixir
%Prana.Execution{
  # Persistent metadata (for database storage)
  id: String.t(),
  workflow_id: String.t(), 
  status: :running | :completed | :failed | :suspended,
  vars: map(),  # workflow variables (renamed from input_data)
  node_executions: [NodeExecution.t()],  # execution audit trail
  
  # Suspension state
  suspended_node_id: String.t() | nil,
  suspension_data: map(),
  preparation_data: map(),
  
  # Runtime state (ephemeral, rebuilt on load)
  __runtime: %{
    "nodes" => %{node_id => output_data},     # completed node outputs for routing
    "env" => map(),                           # environment data from application
    "active_paths" => %{path_key => true},    # conditional branching state
    "executed_nodes" => [String.t()]          # execution order tracking
  } | nil  # nil when loaded from storage
}
```

### **Simplified API Interface**

**GraphExecutor:**
```elixir
execute_graph(execution_graph, init_context)
# Where init_context = %{vars: map(), env: map(), metadata: map()}

resume_workflow(execution, resume_data, env_data, execution_graph)
# Where execution is loaded by application, env_data provides environment context
```

**NodeExecutor:**
```elixir
execute_node(node, execution, routed_input)  # Direct execution access with pre-routed input
resume_node(node, execution, suspended_node_execution, resume_data)  # Resume suspended nodes
```

### **Standardized Expression Context**

NodeExecutor builds unified expression context with required built-in variables:

```elixir
%{
  "$id" => node.id,                    # current node ID
  "$input" => routed_input_by_port,    # input data by port: %{"primary" => data1, "secondary" => data2}
  "$nodes" => execution.__runtime["nodes"], # completed node outputs
  "$env" => execution.__runtime["env"],     # environment variables
  "$vars" => execution.vars,               # workflow variables
  "$workflow" => %{id: ..., name: ...},    # workflow metadata
  "$execution" => %{id: ..., mode: ..., pre: ...} # execution metadata
}
```

### **Two-Mode Input Handling**

**Mode 1: Structured Input (input_map defined)**
```elixir
%Prana.Node{
  input_map: %{
    "url" => "$vars.api_base/users/$input.primary.user_id",
    "method" => "GET", 
    "headers" => %{"Authorization" => "Bearer $env.token"},
    "user_data" => "$input.primary",
    "config" => "$input.secondary.config"
  }
}

# Action receives evaluated input_map:
# %{"url" => "https://api.com/users/123", "method" => "GET", "headers" => %{...}, ...}
```

**Mode 2: Raw Input (input_map nil)**
```elixir
%Prana.Node{
  integration_name: "code",
  action_name: "eval", 
  input_map: nil  # No input transformation
}

# Action receives raw routed_input:
# %{"primary" => %{user_id: 123, ...}, "secondary" => %{config: %{...}}}
```

## Key Benefits

### **1. Eliminates Context Duplication**
- Remove ExecutionContext struct entirely
- Single source of truth for all execution state
- No more context conversion overhead

### **2. Perfect State Rebuilding**
All runtime state is derivable from persistent data:
- `active_paths` from `node_executions.output_port`
- `nodes` from `node_executions.output_data`
- `executed_nodes` from `node_executions` order

### **3. Clean API Separation**
- **Persistent**: audit trail, suspension state, workflow variables
- **Runtime**: performance optimizations, environment data, routing state

### **4. Performance Maintained**
- O(1) node output access during execution
- String keys for expression engine compatibility
- No conversion overhead between contexts

### **5. Predictable Action Interface**
- Actions with `input_map` receive structured, known data formats
- Actions without `input_map` handle raw input for maximum flexibility
- Multi-port access through expression system (`$input.primary`, `$input.secondary`)
- Clear separation between input routing and action execution

## Analyzed Concerns & Resolutions

### **✅ Memory Usage**
**Concern**: Duplication of node output data in both `node_executions` and `__runtime.nodes`

**Resolution**: 
- Current architecture already has this duplication
- Performance benefit justifies memory cost
- Typical impact: <100KB for normal workflows, ~2MB for very large ones
- Acceptable trade-off for O(1) routing performance

### **✅ State Rebuilding Complexity**
**Concern**: Runtime state might be complex to rebuild from storage

**Resolution**:
- `active_paths` rebuilds trivially from `output_port` in node executions
- `nodes` rebuilds from `output_data` in node executions
- Only external dependency is environment data (provided by application)
- Rebuilding is O(n log n) and only happens on resume/recovery

### **✅ Performance Impact**
**Concern**: Rebuilding could be expensive for large workflows

**Resolution**:
- Rebuilding only happens on resume/recovery, not during normal execution
- <1ms for typical workflows, <100ms for very large ones
- Net performance improvement by eliminating repeated context conversions
- Background/lazy rebuilding available if needed

### **✅ State Synchronization**
**Concern**: Risk of `node_executions` and `__runtime` getting out of sync

**Resolution**:
- Use encapsulated update functions (`Execution.complete_node/4`, `Execution.fail_node/3`)
- Never allow direct modification of execution fields
- Atomic updates ensure both persistent and runtime state stay synchronized

### **✅ Null Runtime Handling**
**Concern**: Need careful null checks when `__runtime` is nil

**Resolution**:
- Required initialization step: `prepare_execution_for_use/2` before execution
- Clear API contract: loaded executions need runtime rebuilding
- Lazy rebuilding on first access as fallback option

### **✅ Expression Context Input**
**Concern**: How `$input` gets routed node input in new architecture

**Resolution**:
- GraphExecutor pre-routes input using existing connection logic
- Pass routed input explicitly to NodeExecutor: `execute_node(node, execution, routed_input)`
- Clear separation: GraphExecutor handles routing, NodeExecutor handles execution

### **✅ Multiple Input Ports and Action Data Access**
**Concern**: How actions access data from multiple input ports and handle input_map configuration

**Resolution**:
- **Two-mode input handling**: Actions with `input_map` get structured, predictable data; actions without `input_map` get raw routed data
- **Mode 1 (input_map defined)**: Evaluate input_map expressions and pass result to action - ensures predictable data structure
- **Mode 2 (input_map nil)**: Pass raw routed_input directly to action - for code/dynamic actions that handle arbitrary data
- **Multi-port access**: Actions can specify `"$input.primary"`, `"$input.secondary"` in input_map to access specific ports
- **Flexible sourcing**: Mix input ports with configuration (`"$input.primary.user_id"`, `"$vars.api_url"`, `"$env.token"`)

### **✅ Suspension/Resume Integration**
**Concern**: How `resume_node` fits into the new unified execution architecture

**Resolution**:
- Update `resume_node` signature: `resume_node(node, execution, suspended_node_execution, resume_data)`
- Remove ExecutionContext dependency from resume flow
- Application loads execution, GraphExecutor ensures runtime state via `prepare_execution_for_use/2`
- Consistent pattern: both execute and resume use unified execution structure

## Implementation Plan

### **Phase 1: Add Runtime Infrastructure**
- Add `__runtime` field to Execution struct
- Implement `rebuild_runtime/2` function
- Add encapsulated update functions (`complete_node/4`, `fail_node/3`)
- Add `prepare_execution_for_use/2` for runtime initialization
- Add tests for runtime rebuilding and state synchronization

### **Phase 2: Update NodeExecutor Interface**
- Change `NodeExecutor.execute_node/3` to accept `(node, execution, routed_input)`
- Change `NodeExecutor.resume_node/4` to accept `(node, execution, suspended_node_execution, resume_data)`
- Implement two-mode input handling: evaluate `input_map` if defined, pass raw `routed_input` if nil
- Update context building to use unified execution with all built-in variables and multi-port input structure
- Remove dependency on ExecutionContext struct in both execute and resume flows

### **Phase 3: Update GraphExecutor**
- Update `execute_graph/2` calls to use new NodeExecutor interface with multi-port routed input
- Update `resume_workflow/4` to use new resume_node interface without ExecutionContext conversion
- Implement multi-port input routing: `extract_multi_port_input/3` to route data to named input ports
- Remove ExecutionContext creation and conversion from both execution and resume flows
- Update orchestration to use encapsulated execution updates
- Ensure proper runtime initialization for all execution paths (execute and resume)

### **Phase 4: Clean Up**
- Remove ExecutionContext struct and references
- Remove unused context conversion functions
- Update all tests and documentation
- Verify no direct execution field modifications remain

## Migration Strategy

**Backward Compatibility**: Implement phases incrementally to maintain working system

**Risk Mitigation**: 
- Extensive testing at each phase
- Keep old code until new implementation is proven
- Rollback plan available at each phase

## Success Criteria

1. **Context Simplification**: Single execution context eliminates all intermediate structures
2. **Performance Maintained**: No degradation in execution speed
3. **State Rebuilding**: 100% accurate reconstruction from persistent data
4. **API Cleanliness**: Simpler, more intuitive interfaces
5. **Memory Usage**: Acceptable memory footprint with justified trade-offs

## Decision Rationale

This refactoring addresses core architectural complexity while maintaining performance and adding capabilities. The unified execution structure provides a clear, maintainable foundation for future enhancements while eliminating the current context conversion overhead.

The approach prioritizes simplicity and performance over theoretical memory optimization, which aligns with practical usage patterns where execution speed is more critical than minimal memory usage.

---

**Approved by**: [Your name]  
**Next Review**: After Phase 2 completion