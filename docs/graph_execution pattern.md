# GraphExecutor - Execution Patterns & Plans

**Version**: 2.1
**Date**: June 23, 2025
**Purpose**: Document all possible workflow execution patterns supported by GraphExecutor with sequential execution

## Core Design Principles

### Single Final Output
- **Workflow Completion**: Workflows complete when ALL leaf nodes (nodes with no outgoing connections) finish
- **Leaf Node Detection**: Compile-time validation prevents multiple separate output scenarios
- **Conditional Completion**: Only wait for executed path's leaf nodes in conditional branching
- **Failure Behavior**: If any leaf node fails, entire workflow fails immediately

### Node Settings Architecture
- **Flexible Configuration**: Each node has `settings` map for node-specific configuration
- **Integration-Defined**: Settings schema determined by individual integrations
- **No Core Schema**: Core system doesn't enforce settings structure

### Execution Context Tracking
- **Executed Nodes**: Context includes `executed_nodes: ["A", "if_condition", "B3"]` for downstream access
- **Path Awareness**: Nodes can determine execution path through context inspection

---

## 1. Linear Execution Patterns

### 1.1 Straight Sequential (Chain)
**Pattern**: A → B → C → D
**Description**: Simple sequential execution where each node depends on the previous one.

```
[Start] → [Node A] → [Node B] → [Node C] → [End]
```

**Use Cases**:
- Data processing pipelines
- Step-by-step user onboarding
- Sequential API calls with dependencies

**Execution Characteristics**:
- ✅ Single execution path
- ✅ No parallelism
- ✅ Clear dependency chain
- ✅ Easy to debug and monitor

**Implementation Status**: ✅ **Fully Supported**

---

### 1.2 Linear with Branching (Fork)
**Pattern**: A → (B, C, D) where B, C, D execute sequentially
**Description**: One node triggers multiple branches that execute in sequence, not parallel.

```
[Start] → [Node A] → [Node B] → (completes)
                  → [Node C] → (completes)
                  → [Node D] → (completes)
```

**Execution Requirements**:
- **Sequential Execution**: Branches execute one after another, not simultaneously
- **All Must Complete**: Workflow completes when ALL branches finish
- **Fail-option**: single fail could fail whole workflow or continue execution
- **Data Distribution**: Each branch receives copy of Node A's output
- **Predictable Order**: Execution order maintained within ready node batch

**Use Cases**:
- Sequential notifications to multiple channels
- Ordered data validation checks
- Sequential API calls with same input
- Predictable processing pipelines

**Execution Characteristics**:
- ✅ Sequential execution after trigger
- ✅ Predictable execution order
- ✅ Independent branch processing
- ✅ Automatic completion detection
- ✅ Fail-fast error handling

**Implementation Status**: ✅ **Fully Supported**

---

## 2. Conditional Execution Patterns

### 2.1 Simple Condition (If-Then-Else)
**Pattern**: A → Condition → B or C → (different or same paths)
**Description**: Conditional routing where each clause may lead to different output paths or converge to same path.

```
# Scenario 1: Different output paths
[Start] → [Node A] → [Condition] ┌─ [Node B] → [End B] (leaf)
                                 └─ [Node C] → [End C] (leaf)

# Scenario 2: Convergent paths
[Start] → [Node A] → [Condition] ┌─ [Node B] ─┐
                                 └─ [Node C] ─┘ → [Node D] → [End]
```

**Execution Requirements**:
- **Single Path Execution**: Only one branch (B OR C) executes based on condition
- **Context Tracking**: Update `executed_nodes` to include path taken
- **Flexible Convergence**: Branches may lead to different endpoints or same endpoint
- **User Responsibility**: Downstream nodes must handle different data structures if paths converge

**Context Access Pattern**:
```elixir
# Node D can check execution path (if paths converge)
if "B" in $context.executed_nodes do
  # Handle B branch data
else if "C" in $context.executed_nodes do
  # Handle C branch data
end
```

**Use Cases**:
- User role-based workflows with different endpoints
- Error handling with separate or convergent paths
- Feature flag routing

**Execution Characteristics**:
- ✅ Single path execution
- ✅ Dynamic routing
- ✅ Flexible path destinations
- ✅ Efficient resource usage


---

### 2.2 Multi-branch Condition (Switch)
**Pattern**: A → Switch → B or C or D or E (to various endpoints)
**Description**: Multiple conditional paths based on switch node output, with flexible endpoint routing.

```
[Start] → [Node A] → [Switch] ┌─ [Node B] (case 1) → [End 1]
                              ├─ [Node C] (case 2) → [End 2]
                              ├─ [Node D] (case 3) → [Merge] → [End 3]
                              └─ [Node E] (default) → [End 4]
```

**Execution Requirements**:
- **Exclusive Execution**: Only ONE branch executes based on switch evaluation
- **Flexible Routing**: Each case can lead to different processing and endpoints
- **Default Handling**: Fallback path when no conditions match
- **Context Tracking**: Record which case was executed

**Use Cases**:
- Payment method routing
- Multi-tenant workflows with different endpoints
- Status-based processing with various outcomes
- Complex workflow routing based on data values

**Execution Characteristics**:
- ✅ Multiple possible paths
- ✅ Exclusive execution
- ✅ Flexible endpoint routing
- ✅ Scalable branching
- ⚠️ Complex testing requirements


---

## 3. Convergent Execution Patterns

### 3.1 Diamond Pattern (Fork-Join)
**Pattern**: A → (B, C) → Merge → D
**Description**: Sequential branching followed by data merging (not waiting - that's handled by Wait-for-All pattern).

```
[Start] → [Node A] → ┌─ [Node B] ─┐
                     └─ [Node C] ─┘ → [Merge] → [Node D] → [End]
```

**Execution Requirements**:
- **Sequential Execution**: B and C execute sequentially, not in parallel
- **Merge Node Responsibility**: Merge node only handles data combination from completed branches
- **No Waiting Logic**: This pattern does not handle async waiting (see Wait-for-All Parallel pattern)
- **Fail-Fast Behavior**: If ANY branch (B or C) fails, entire pattern fails immediately

**Merge Node Configuration**:
```elixir
%Prana.Node{
  type: :action,
  integration_name: "core",
  action_name: "merge",
  settings: %{
    "strategy" => "combine_arrays"     # Data combination only
  }
}
```

**Use Cases**:
- Data aggregation from multiple sequential sources
- Sequential processing with result consolidation
- Data transformation pipelines with merge step

**Execution Characteristics**:
- ✅ Sequential processing
- ✅ Clear data merging
- ✅ Separation of concerns (merge vs wait)
- ✅ Simple execution model


---



## 4. Async Coordination Patterns

### 4.1 Wait-for-All Parallel (Async Synchronization)
**Pattern**: source → (F, F1) → Wait → doSomething
**Description**: Explicit synchronization point for async operations.

```
[Source] → ┌─ [F] (async) ─┐
           └─ [F1] (async) ─┘ → [Wait] → [doSomething] → [End]
```

**Execution Requirements**:
- **Async Branch Support**: F and F1 can trigger sub-workflows or long-running operations
- **Explicit Synchronization**: Wait node acts as coordination point
- **Timeout Handling**: Configurable timeout for async operations (future implementation)
- **All Branch Completion**: Wait for ALL async branches before proceeding

**Wait Node Configuration**:
```elixir
%Prana.Node{
  type: :wait,
  integration_name: "core",
  action_name: "wait_for_completion",
  settings: %{
    "timeout_ms" => 30000,
    "wait_strategy" => "all_branches",
    "on_timeout" => "fail"
  }
}
```

**Use Cases**:
- Async sub-workflow coordination
- External system integration
- Long-running operation synchronization

**Execution Characteristics**:
- ✅ Async operation support
- ✅ Explicit synchronization points
- ⚠️ Timeout handling (future)
- ⚠️ State persistence for long waits

**Implementation Status**: 🔄 **Partial** (timeout mechanism pending)

---

## 5. Complex Execution Patterns

### 5.1 Event-Driven Pattern
**Pattern**: A → WaitForEvent → B → C
**Description**: Workflow suspends waiting for external events.

```
[Start] → [Node A] → [Wait for Event] ──(event)──→ [Node B] → [Node C] → [End]
                           │
                           └── (suspended) ──→ [Resume Point]
```

**Use Cases**:
- Human approval workflows
- External system integration
- Time-based triggers

**Execution Characteristics**:
- ✅ External event integration
- ✅ Long-running workflows
- ⚠️ State persistence required
- ⚠️ Timeout handling needed

**Implementation Status**: 🔄 **Future** (requires Phase 2 suspension/resume)

---

### 5.2 Loop Over Items Pattern (n8n-style)
**Pattern**: A → LoopOverItems → (loop: B → C → back, done: D)
**Description**: Iterate over collection items with explicit loop/done outputs and automatic termination.

```
[Data Source] → [Loop Over Items] ┌─ loop → [Node A] → [Node B] ─┐
                     │            │                              │
                     │            └──────────── back ←──────────┘
                     │
                     └─ done → [Node C] → [Final Processing]
```

**Use Cases**:
- Processing collections with complex per-item logic
- Batch operations with item-level transformations
- Safe iteration with guaranteed termination

**Execution Characteristics**:
- ✅ Guaranteed termination (no infinite loops)
- ✅ Built-in data accumulation
- ✅ Clear iteration boundaries
- ⚠️ Requires special loop node implementation

**Implementation Status**: 📋 **Future**

---

## 6. Execution Pattern Complexity Matrix

| Pattern | Complexity | Parallelism | Debugging | GraphExecutor Support |
|---------|------------|-------------|-----------|----------------------|
| **Straight Sequential** | Low | None | Easy |  |
| **Linear Branching** | Low | Sequential | Easy |  |
| **Simple Condition** | Medium | Low | Medium |  |
| **Multi-branch Condition** | Medium | Low | Medium |  |
| **Diamond (Fork-Join)** | Low | Sequential | Easy |  |
| **Wait-for-All Parallel** | Medium | Async Only | Medium | 🔄 Partial |
| **Event-Driven** | High | Low | Hard | 🔄 Future |
| **Loop Over Items** | Medium | Low | Medium | 📋 Future |

### Matrix Legend
- **Complexity**: Implementation and design difficulty
- **Parallelism**: Level of concurrent execution possible
- **Debugging**: Difficulty of troubleshooting issues
- **GraphExecutor Support**: Current implementation status

---

## 7. Required Implementation Changes

### A. Core Data Structure Updates

#### Node Structure Enhancement
```elixir
%Prana.Node{
  # ... existing fields
  settings: map(),           # NEW: Flexible node-specific configuration
  # Keep all existing fields unchanged
}
```

#### Execution Context Enhancement
```elixir
%Prana.ExecutionContext{
  # ... existing fields
  executed_nodes: [String.t()],  # NEW: Track execution order
  # Keep other context fields unchanged
}
```

### B. GraphExecutor New Capabilities

#### Branch Coordination
- **coordinate_parallel_branches/3**: Handle fork-join patterns with fail-fast
- **handle_conditional_routing/3**: Route based on conditions, update context
- **manage_merge_node_inputs/3**: Aggregate inputs for merge nodes
- **detect_workflow_completion/2**: Check if all active leaf nodes complete

#### Context Management
- **track_execution_context/2**: Update executed_nodes list during execution
- **provide_context_access/2**: Make context available to node expressions

### C. Required Core Integrations

#### Core.Merge Integration
```elixir
%Prana.Integration{
  name: "core",
  actions: %{
    "merge" => %Prana.Action{
      name: "merge",
      # Handles multi-input aggregation with configurable strategies
    }
  }
}
```

#### Core.Condition Integration
```elixir
%Prana.Integration{
  name: "core",
  actions: %{
    "if_condition" => %Prana.Action{},
    "switch" => %Prana.Action{}
    # Handle conditional routing logic
  }
}
```

#### Core.Wait Integration
```elixir
%Prana.Integration{
  name: "core",
  actions: %{
    "wait_for_completion" => %Prana.Action{
      # Handle async synchronization
    }
  }
}
```

---

## 8. Implementation Phases

### Phase 3.1: Core Patterns (✅ COMPLETED)
- ✅ Node settings attribute
- ✅ Sequential execution implementation (`execute_nodes_sequentially/4`)
- ✅ Multi-branching with fail-fast behavior
- ✅ Linear branching pattern (A → B, C, D sequential)
- ✅ Leaf node completion detection
- ✅ Sequential fork pattern coordination

### Phase 3.2: Advanced Coordination (📋 TODO)
- ⏳ Execution context tracking (`executed_nodes`)
- ⏳ Conditional routing with context updates
- ⏳ Diamond pattern (fork-join) coordination
- ⏳ Merge node input aggregation implementation
- ⏳ Wait node async synchronization
- ⏳ Partial convergence pattern support
- ⏳ Enhanced error propagation

### Phase 3.3: Core Integrations (📋 TODO)
- ⏳ Core.Merge integration with strategy support
- ⏳ Core.Condition integration (if/switch)
- ⏳ Core.Wait integration with timeout handling

### Phase 4: Advanced Patterns (📋 TODO)
- 📋 Event-driven pattern with suspension/resume
- 📋 Loop over items pattern
- 📋 Enhanced circuit breaker patterns

---

## 9. Current Implementation Summary (June 23, 2025)

### ✅ **Completed Sequential Execution Support**

**Linear Execution Patterns**:
- ✅ **Pattern 1.1 (Sequential Chain)**: A → B → C → D
  - Natural sequential execution due to dependencies
  - **Status**: Fully Supported

- ✅ **Pattern 1.2 (Linear Branching)**: A → (B, C, D)
  - **NEW**: Sequential execution of branches (previously parallel)
  - Predictable execution order within batch
  - Fail-fast behavior on branch failure
  - **Status**: Fully Supported

**Key Benefits Achieved**:
- ✅ **Predictable Execution Order**: Debugging and testing simplified
- ✅ **Fail-Fast Error Handling**: Clear failure points and immediate workflow termination
- ✅ **Resource Efficiency**: Lower memory and process overhead
- ✅ **Deterministic Behavior**: Consistent execution patterns across runs

### 📋 **Next Implementation Priorities**

1. **Phase 3.2: Advanced Coordination Patterns**
   - Conditional routing (if/then/else, switch)
   - Diamond pattern (fork-join with merge)
   - Execution context tracking

2. **Phase 3.3: Core Integrations**
   - Core.Logic integration (conditions, switches)
   - Core.Transform integration (merge, data manipulation)
   - Core.Wait integration (async coordination)

3. **Phase 4: Advanced Patterns**
   - Event-driven workflows with suspension/resume
   - Loop iteration patterns
   - Advanced error handling and circuit breakers

---

**Document Status**: ✅ **Phase 3.1 Complete - Sequential Execution Implemented**
**Next Milestone**: Advanced Coordination Patterns (Phase 3.2)
**Last Updated**: June 23, 2025
