# Prana GraphExecutor - Requirements Document

**Version**: 1.3
**Date**: June 26, 2025
**Status**: Phase 3.2 Complete with Branch-Following Execution, Phase 3.3+ Planned

## 1. Overview

The **GraphExecutor** is the core workflow orchestration engine in the Prana automation platform. It executes pre-compiled workflow graphs by coordinating node execution, managing data flow between nodes, and handling workflow lifecycle events.

### Key Principles

- **Branch-Following Execution**: Prioritize completing active execution paths before starting new branches
- **Performance Optimization**: O(1) connection lookups and optimized context management
- **Separation of Concerns**: GraphExecutor handles orchestration; NodeExecutor handles individual nodes
- **Port-based Architecture**: Explicit data routing through named input/output ports
- **Dependency-driven Execution**: Nodes execute when their dependencies are satisfied
- **Conditional Path Tracking**: Active path management for proper conditional branching behavior

## 2. Current Implementation Status

**✅ Phase 3.1**: Core Execution with Performance Optimization
**✅ Phase 3.2**: Conditional Branching with Branch-Following Execution

### Branch-Following Execution Model

**Core Innovation**: Single-node execution with branch prioritization

**Execution Strategy**:
```
Find ready nodes → Select ONE node → Execute it → Route output → Repeat
Result: [trigger] → [branch_a1] → [branch_a2] → [branch_b1] → [branch_b2] → [merge]
```

**Benefits**:
- Predictable execution order with branches completing fully before others start
- Proper IF/ELSE and switch/case conditional behavior
- Enhanced debuggability with clear execution flow

## 3. Core Features

### Primary API

```elixir
execute_graph(execution_graph, input_data, context \\ %{})
  :: {:ok, Execution.t()} | {:error, reason}

# Required context structure
context = %{
  workflow_loader: (workflow_id -> {:ok, ExecutionGraph.t()} | {:error, reason}),
  variables: %{},     # optional
  metadata: %{}       # optional
}
```

### Key Capabilities

- **Graph Execution**: Execute pre-compiled ExecutionGraphs with dependency-driven execution
- **Branch-Following**: Single-node execution with intelligent branch prioritization
- **Data Routing**: Port-based data flow with O(1) connection lookups
- **Sub-workflows**: Sync and fire-and-forget execution modes
- **Event Integration**: Comprehensive middleware event emission
- **Error Handling**: Fail-fast behavior with structured error responses
- **Context Management**: Shared execution state with expression engine integration

## 4. Phase 3.2 Requirements (✅ COMPLETE)

### 4.1 Scope: Conditional Branching with Branch-Following Execution

**Focus**: Advanced conditional execution patterns with branch-following strategy for predictable workflow behavior

### 4.2 Core Functionality Implemented

#### 4.2.1 Branch-Following Execution Strategy
- ✅ **Single-node execution**: Execute one node per iteration instead of batches
- ✅ **Intelligent node selection**: `select_node_for_branch_following()` prioritizes active branches
- ✅ **Active branch continuation**: Complete execution paths before starting new ones
- ✅ **Dependency-based fallback**: Select nodes with fewer dependencies when no active branches

#### 4.2.2 Conditional Branching Support
- ✅ **IF/ELSE patterns**: Exclusive branch execution based on conditions
- ✅ **Switch/Case routing**: Multi-branch routing with named ports (premium, standard, basic, default)
- ✅ **Active path tracking**: Context tracks `active_paths` to prevent dual branch execution
- ✅ **Conditional completion**: Workflows complete based on active paths, not total nodes

#### 4.2.3 Logic Integration
- ✅ **if_condition action**: Evaluate boolean expressions for IF/ELSE branching
- ✅ **switch action**: Multi-way routing based on value matching
- ✅ **merge action**: Foundation for diamond pattern coordination
- ✅ **Comprehensive testing**: 24 passing conditional branching tests (1358 lines)

#### 4.2.4 Performance Optimization (Phase 3.2.5)
- ✅ **O(1) connection lookups**: Pre-built `connection_map` for instant access
- ✅ **Reverse connection map**: `reverse_connection_map` for incoming connection queries
- ✅ **Optimized context updates**: Batch map updates to reduce memory allocations
- ✅ **Performance benchmarks**: Sub-microsecond lookup times, 100-node workflows in ~11ms

#### 4.2.5 Execution Model Features
```elixir
# Branch-following node selection
def select_node_for_branch_following(ready_nodes, execution_graph, execution_context) do
  # Priority 1: Nodes continuing active branches
  continuing_nodes = filter_nodes_continuing_active_branches(ready_nodes)

  if not empty?(continuing_nodes) do
    # Among continuing nodes, prefer those with fewer dependencies
    select_by_dependency_count(continuing_nodes)
  else
    # Priority 2: Start new branches, prefer fewer dependencies
    select_by_dependency_count(ready_nodes)
  end
end
```

### 4.3 Success Criteria Met

1. ✅ **Branch-following execution**: Verified execution order `[trigger, branch_a1, branch_a2, branch_b1, branch_b2, merge]`
2. ✅ **Conditional branching**: IF/ELSE and switch/case patterns work correctly
3. ✅ **Performance optimization**: O(1) lookups and optimized context management
4. ✅ **Active path tracking**: Proper conditional path management prevents dual execution
5. ✅ **Comprehensive testing**: 34 total tests (7 core + 24 conditional + 3 branch following)
6. ✅ **Code quality**: Clean implementation with no unused code or warnings
7. ✅ **Documentation**: Updated ADR and requirements reflecting current architecture

### 4.4 Architecture Decisions

- **ADR-001**: Branch-Following Execution Strategy (documented in `docs/adr/`)
- **Trade-off**: Sacrificed theoretical parallelism for predictable execution patterns
- **Performance**: Maintained excellent performance while gaining execution predictability
- **Maintainability**: Cleaner codebase with focused, single-purpose functions

## 5. Future Phases (📋 PLANNED)

### 5.1 Phase 3.3: Advanced Coordination (Next Priority)

**Focus**: Diamond pattern coordination and Wait integration for complex synchronization patterns

#### 5.1.1 Enhanced Merge Integration
- **Diamond pattern coordination**: Fork-join patterns where multiple branches converge
- **Wait-for-all patterns**: Synchronization points that wait for multiple inputs
- **Timeout handling**: Graceful timeout management for coordination points

#### 5.1.2 Wait Integration
- **Async synchronization**: Sophisticated waiting mechanisms for complex workflows
- **Conditional waiting**: Wait based on expressions or external events
- **Timeout patterns**: Configurable timeouts with fallback behaviors

### 5.2 Phase 4: Async Execution with Suspension/Resume

**Focus**: Advanced sub-workflow execution with workflow suspension capabilities

### 3.2 Core Functionality

#### 3.2.1 Async Sub-workflow Execution
```elixir
# Async mode: Execute sub-workflow with suspension/resume
{:suspended, resume_token} = execute_sub_workflow_async(child_graph, input_data, context)
# Parent workflow suspends, returns control to application
# Later: resume_workflow(resume_token, sub_workflow_result)
```

#### 3.2.2 Workflow Suspension/Resume Mechanisms
- **Suspension Points**: When async sub-workflows are triggered
- **Resume Tokens**: Unique identifiers for suspended executions
- **State Persistence**: Save execution state via middleware events
- **Resume Logic**: Restore execution state and continue from suspension point

#### 3.2.3 Advanced Sub-workflow Support
- **Multiple Async Sub-workflows**: Coordinate multiple concurrent sub-workflows
- **Nested Async Execution**: Support async sub-workflows within async sub-workflows
- **Result Aggregation**: Merge multiple sub-workflow results into parent context
- **Timeout Handling**: Handle sub-workflow timeouts and cleanup

#### 3.2.4 Enhanced Context Management
- **Suspension State**: Track suspended nodes and their dependencies
- **Resume Context**: Restore execution context from persisted state
- **Sub-workflow Coordination**: Manage parent-child execution relationships

### 3.2.5 Application Integration
- **Persistence Events**: Emit events for application to save/restore execution state
- **Resume API**: Application-triggered workflow resumption
- **Status Tracking**: Monitor suspended and active executions

## 4. Phase 3 Requirements (📋 PLANNED)

### 4.1 Scope: Retry and Timeout Mechanisms

**Focus**: Resilience and reliability features for production workflows

### 4.2 Core Functionality


#### 4.2.3 Timeout Management
- **Node-level Timeouts**: Individual node execution timeouts
- **Workflow-level Timeouts**: Overall workflow execution limits
- **Sub-workflow Timeouts**: Timeout handling for nested workflows
- **Graceful Timeout**: Clean resource cleanup on timeout

#### 4.2.4 Circuit Breaker Patterns
- **Failure Thresholds**: Automatic circuit opening on repeated failures
- **Recovery Detection**: Automatic circuit closing when service recovers
- **Fallback Strategies**: Alternative execution paths when circuits are open

- **Error Classification**: Categorize errors for appropriate handling
- **Error Aggregation**: Collect and analyze error patterns
- **Graceful Degradation**: Continue execution with reduced functionality
