# Prana Architectural Refactoring Plan

**Version**: 1.3  
**Date**: January 2025  
**Status**: Updated - Confirmed Execution-ExecutionGraph Merger Strategy  
**Priority**: High Impact - Medium Urgency

## Executive Summary

This document outlines a comprehensive refactoring plan to address mixed responsibilities and data redundancy in Prana's core execution architecture. The current system suffers from blurred boundaries between orchestration logic, execution results, and runtime state management, leading to maintenance complexity and memory inefficiency.

**Goals**:
- Separate concerns between orchestration, runtime state, and persistent data
- Reduce memory overhead by 50-60% through targeted optimizations
- Improve code maintainability and testing
- Minimize complexity increase while maximizing benefits

**Update Notes (v1.3)**:
- **CONFIRMED**: Execution-ExecutionGraph merger strategy validated by external workflow platform analysis (n8n)
- **NEW INSIGHT**: n8n execution data shows identical architectural problems - mixed responsibilities, data redundancy, scattered suspension state
- **VALIDATION**: Real-world evidence confirms unified approach solves fundamental workflow platform challenges
- **ARCHITECTURE DECISION**: Proceed with complete merger eliminating artificial separation between static workflow definition and runtime execution state
- All previous v1.2 improvements maintained: removed unused fields, simplified suspension data, clean separation of concerns

## Current Architecture Problems

### 1. Mixed Responsibilities

```elixir
# PROBLEM: GraphExecutor handles too many concerns
defmodule Prana.GraphExecutor do
  # ✅ Should handle: Orchestration logic
  # ❌ Currently also handles: Runtime state management, data routing, context updates
end

# PROBLEM: Execution mixes persistent and runtime data  
defmodule Prana.Execution do
  defstruct [
    :id, :status,                    # ✅ Persistent data
    :node_executions, :output_data,  # ✅ Persistent data
    :__runtime                       # ❌ Runtime data mixed in
  ]
end

# PROBLEM: ExecutionGraph artificially separated from runtime context
# Every function needs both parameters: execute_node(node, execution_graph, execution)
```

### 2. Massive Data Redundancy

```elixir
# Node data stored 4+ times:
%Workflow{nodes: [node1, node2, ...]}                    # 1. Original definition
%ExecutionGraph{workflow: %{nodes: [node1, node2, ...]}} # 2. Duplicated in pruned workflow  
%ExecutionGraph{node_map: %{"node1" => node1, ...}}      # 3. Duplicated as map
# 4. Additional references in runtime state

# Connection data stored 3+ times:
%Workflow{connections: original_format}
%ExecutionGraph{workflow: %{connections: duplicate}}
%ExecutionGraph{connection_map: optimized_format}
%ExecutionGraph{reverse_connection_map: another_copy}
```

**Memory Impact**: 300%+ redundancy for typical workflows

### 3. Unused Data Fields

Analysis of the current codebase revealed additional inefficiencies:

```elixir
# PROBLEM: Documented but unused data fields
execution.__runtime["executed_nodes"]  # Mentioned in docs, never actually used
execution.output_data                 # Only written, never read for business logic
execution.error_data                  # Only used for middleware events, can be derived
execution.suspended_node_id           # Duplicated in NodeExecution
execution.suspension_type             # Duplicated in NodeExecution  
execution.suspension_data             # Application coordination data, not for persistent storage
execution.suspended_at                # Duplicated in NodeExecution
execution.resume_token                # Not used in current implementation

# ACTUAL USAGE ANALYSIS:
# ✅ execution.__runtime["nodes"]        - Used for data routing
# ✅ execution.__runtime["active_nodes"] - Used for branch execution  
# ✅ execution.__runtime["node_depth"]   - Used for branch following
# ❌ execution.__runtime["executed_nodes"] - UNUSED: Dead code
# ❌ execution.output_data               - REDUNDANT: Can be derived from node_executions
# ❌ execution.error_data                - REDUNDANT: Can be derived from failed nodes
# ❌ execution.suspended_node_id         - REDUNDANT: Suspension info stored in NodeExecution
# ❌ execution.suspension_type           - REDUNDANT: Suspension info stored in NodeExecution
# ❌ execution.suspension_data           - TRANSIENT: Application coordination data, not for storage
# ❌ execution.suspended_at              - REDUNDANT: Suspension info stored in NodeExecution
# ❌ execution.resume_token              - UNUSED: Not used in current implementation

# DERIVABLE INFORMATION:
# - Execution order: Available through node_executions audit trail
# - Final output: Can be computed from completed node outputs
# - Error details: Can be extracted from failed node executions
# - Suspension state: Can be derived from suspended NodeExecution records
# - Application coordination: suspension_data generated on-demand for middleware events

# SIMPLIFIED SUSPENSION DATA STRUCTURE (for application coordination):
# Type-specific minimal structures with explicit type identification

# Webhook: Timing-based suspension
%{type: :webhook, wait_till: DateTime.t()}

# Interval: Timing-based suspension  
%{type: :interval, wait_till: DateTime.t()}

# Schedule: Timing-based suspension
%{type: :schedule, wait_till: DateTime.t()}

# Sub-workflow: Workflow coordination
%{type: :sub_workflow, sub_workflow_id: String.t(), execution_mode: :sync | :async | :fire_and_forget}
```

**Impact**: Removes unnecessary memory overhead and eliminates potential confusion about data duplication

### Benefits of Simplified Suspension Data Structure

**Minimal Storage**: Only essential fields stored, no redundant timing or metadata
**Unified Timing**: Webhook, interval, and schedule all use `wait_till` for consistent time-based resumption
**Type-Specific**: Each suspension type defines only the fields it actually needs
**Clean Separation**: Timing data (`started_at`) extracted from NodeExecution, not duplicated
**Simplified Processing**: Two main patterns - timing-based (`wait_till`) and workflow-based (`sub_workflow_id`, `execution_mode`)

## Proposed Architecture

### Core Principle: ExecutionGraph as Execution Attribute

**ARCHITECTURAL DECISION REFINED**: Keep ExecutionGraph and Execution separate for clean responsibilities, but embed ExecutionGraph as an attribute of Execution for clean APIs. This leverages Elixir's immutable data sharing while maintaining separation of concerns.

```elixir
# 🏗️ ExecutionGraph: Static, Cacheable, Pre-compiled
defmodule Prana.ExecutionGraph do
  @moduledoc """
  Compiled workflow definition with optimization maps.
  
  STATIC: Never changes after compilation
  CACHEABLE: Shared across multiple executions via immutable data sharing
  RESPONSIBILITY: Workflow structure and routing optimization
  """
  
  defstruct [
    # 📊 STATIC WORKFLOW DATA (immutable after compilation)
    :workflow_id, :workflow_version, :trigger_node_key,
    :nodes,                    # %{node_key => Node.t()} - compiled nodes (replaces node_map)
    :connection_map,           # %{{from, port} => [Connection.t()]} - O(1) lookups
    :reverse_connection_map,   # %{node_key => [Connection.t()]} - incoming connections
    :dependency_graph          # map() - dependency resolution optimization
  ]
end

# ⚡ Execution: Runtime State + Embedded ExecutionGraph
defmodule Prana.Execution do
  @moduledoc """
  Execution instance with embedded ExecutionGraph for clean single-parameter APIs.
  
  CONTAINS: ExecutionGraph (loaded from application cache)
  RESPONSIBILITY: Runtime state, audit trail, execution coordination  
  PERSISTENCE: Only execution fields stored (execution_graph excluded)
  """
  
  defstruct [
    # 🏗️ EMBEDDED STATIC WORKFLOW (loaded by application from cache)
    :execution_graph,          # ExecutionGraph.t() - compiled workflow definition
    
    # 📋 EXECUTION METADATA
    :id, :status, :started_at, :completed_at,
    :parent_execution_id, :execution_mode,
    :trigger_type, :trigger_data, :current_execution_index,
    
    # ⚡ RUNTIME EXECUTION STATE (ephemeral, rebuilt on load)
    :active_nodes,             # MapSet.t(String.t()) - nodes ready for execution
    :node_depth,              # %{node_key => depth} - for branch following  
    :completed_nodes,         # %{node_key => output_data} - results cache
    :iteration_count,         # integer() - loop protection
    
    # 📝 PERSISTENT AUDIT TRAIL
    :node_executions,         # %{node_key => [NodeExecution.t()]} - complete history
    
    # 🔄 SUSPENSION STATE (transient coordination)
    :suspension,               # %{node_id: String.t(), type: atom(), data: map(), suspended_at: DateTime.t()} | nil
    
    # 🌍 EXECUTION CONTEXT
    :variables,               # %{} - workflow variables
    :environment,             # %{} - external context data
    :preparation_data,        # %{} - action preparation cache  
    :metadata                 # %{} - execution metadata
  ]
end
```

### Clean Architecture with Embedded ExecutionGraph

**ARCHITECTURE REFINED**: ExecutionGraph embedded as Execution attribute provides clean single-parameter APIs while maintaining separation of concerns.

```elixir
# 🎯 GraphExecutor: Clean Single-Parameter APIs
defmodule Prana.GraphExecutor do
  @doc "Execute workflow with embedded ExecutionGraph - single parameter everywhere!"
  def execute_workflow(execution) do
    # All workflow definition available via execution.execution_graph
    execute_loop(execution)
  end
  
  defp execute_loop(execution) do
    case get_ready_nodes(execution) do
      [] -> {:ok, Execution.complete(execution)}
      ready_nodes ->
        selected_node = select_next_node(ready_nodes, execution)
        
        case execute_single_node(selected_node, execution) do
          {:ok, updated_execution} -> execute_loop(updated_execution)
          {:suspend, suspended_execution} -> {:suspend, suspended_execution}
          {:error, failed_execution} -> {:error, failed_execution}
        end
    end
  end
  
  # All functions now take single execution parameter
  defp execute_single_node(node, execution) do
    input_data = get_node_input(execution, node.key)
    
    case NodeExecutor.execute_node(node, input_data) do
      {:ok, output_data, output_port} ->
        {:ok, Execution.complete_node(execution, node.key, output_data, output_port)}
      
      {:suspend, suspend_data} ->
        {:suspend, Execution.suspend(execution, node.key, suspend_data)}
      
      {:error, error_data} ->
        {:error, Execution.fail(execution, node.key, error_data)}
    end
  end
end

# ⚡ Execution: All Operations on Single Structure
defmodule Prana.Execution do
  @doc "All execution operations work on single execution struct with embedded graph"
  
  def get_ready_nodes(execution) do
    # Access workflow structure via embedded execution_graph
    execution.active_nodes
    |> Enum.map(&execution.execution_graph.nodes[&1])
    |> Enum.filter(&dependencies_satisfied?(&1, execution))
  end
  
  def complete_node(execution, node_key, output_data, output_port) do
    execution
    |> update_completed_nodes(node_key, output_data)
    |> update_node_executions(node_key, :completed, output_data, output_port)
    |> route_to_next_nodes(node_key, output_port)
    |> update_active_nodes_and_depths()
  end
  
  def get_node_input(execution, node_key) do
    # All routing using embedded execution_graph
    resolve_multi_port_input(execution, node_key)
  end
  
  # Application lifecycle functions
  def new(execution_graph, context \ %{}) do
    %__MODULE__{
      execution_graph: execution_graph,  # Embedded from application cache
      id: generate_id(),
      status: :pending,
      active_nodes: MapSet.new([execution_graph.trigger_node_key]),
      variables: context[:variables] || %{},
      environment: context[:environment] || %{},
      # ... other initialization
    }
  end
  
  def to_storage_format(execution) do
    # Exclude execution_graph from persistence - only store execution state
    Map.drop(execution, [:execution_graph])
  end
  
  def from_storage_format(stored_execution, execution_graph) do
    # Rebuild execution with embedded execution_graph from cache
    Map.put(stored_execution, :execution_graph, execution_graph)
  end
end

# 🏗️ Application Integration Pattern
defmodule MyApp.WorkflowExecutor do
  def start_execution(workflow_id, context) do
    # 1. Load ExecutionGraph from cache
    execution_graph = MyApp.ExecutionGraphCache.get(workflow_id)
    
    # 2. Create execution with embedded graph
    execution = Execution.new(execution_graph, context)
    
    # 3. Clean single-parameter execution
    GraphExecutor.execute_workflow(execution)
  end
  
  def resume_execution(execution_id, resume_data) do
    # 1. Load stored execution state
    stored_execution = MyApp.Repo.get_execution(execution_id)
    
    # 2. Load ExecutionGraph from cache  
    execution_graph = MyApp.ExecutionGraphCache.get(stored_execution.workflow_id)
    
    # 3. Rebuild with embedded graph
    execution = Execution.from_storage_format(stored_execution, execution_graph)
    
    # 4. Resume with clean API
    GraphExecutor.resume_workflow(execution, resume_data)
  end
end
```

## Memory Optimization Strategy

### Complete Redundancy Elimination (60-70% Memory Reduction)

**ENHANCED TARGET**: Complete merger enables even greater memory savings than originally estimated.

```elixir
# ✅ COMPLETE ELIMINATION: Dual structure redundancy
# BEFORE: Two separate structures with massive duplication
%Execution{
  id: "exec_123",
  workflow_id: "wf_456", 
  node_executions: %{...},     # Audit trail
  __runtime: %{...},           # Runtime state mixed in
  vars: %{...},                # Context data
  # + 15 other fields mixing concerns
} 
+
%ExecutionGraph{
  workflow: %Workflow{...},    # Workflow definition duplicated
  node_map: %{...},            # Same nodes, different format  
  connection_map: %{...},      # Optimized connections
  reverse_connection_map: %{...} # Duplicate connection data
}

# AFTER: Single unified structure - ZERO duplication
%ExecutionGraph{
  # Everything in one place, logically organized:
  execution_id: "exec_123",
  workflow_id: "wf_456",
  nodes: %{...},               # SINGLE node storage
  connection_map: %{...},      # SINGLE connection storage
  node_executions: %{...},     # Audit trail
  active_nodes: MapSet.new(),  # Runtime state
  completed_nodes: %{...},     # Results cache
  variables: %{...},           # Context data
  # Clean, single responsibility
}

# ✅ ELIMINATE: Function parameter duplication
# BEFORE: Every function needs both structures
def execute_node(node, execution_graph, execution) do
  input = extract_multi_port_input(node, execution_graph, execution)
  # ... complex parameter passing
end

# AFTER: Single parameter - clean APIs
def execute_node(node, graph) do
  input = graph.get_node_input(node.key)  
  # ... simple, clean
end

# ✅ ELIMINATE: Context conversion overhead  
# BEFORE: Constant conversion between structures
execution = update_runtime(execution, new_data)
execution_graph = update_connections(execution_graph, routing)
# Memory allocations for every operation

# AFTER: Single atomic updates
graph = graph
|> complete_node(node_key, output_data)
|> route_to_next_nodes()
# Single structure, optimized updates
```

**Enhanced Memory Impact Analysis**:
- **Structure elimination**: 100% reduction in dual-structure overhead (Execution + ExecutionGraph → unified ExecutionGraph)
- **Node storage**: 100% reduction in duplication (workflow.nodes + node_map + references → single nodes map)
- **Connection storage**: 75% reduction (workflow.connections + connection_map + reverse_map → single connection_map)
- **Runtime state**: 100% elimination of mixed data concerns (__runtime removed, clean separation)
- **Function parameters**: 50% reduction in parameter passing (two structs → one struct)
- **Context conversion**: 100% elimination of conversion overhead between structures
- **Memory allocations**: 40-60% reduction from atomic updates vs dual-structure synchronization
- **Total estimated savings**: 60-70% for typical workflows (significantly improved from original 45-55% estimate)

## Refactoring Plan

### Phase 1: Foundation (Week 1-2)

**Goal**: Create new unified ExecutionGraph without breaking existing functionality

```elixir
# 1.1 Create new ExecutionGraph module
defmodule Prana.ExecutionGraph do
  defstruct [
    # Core unified structure
    :nodes, :connection_map, :trigger_node_key,
    :active_nodes, :completed_nodes,
    :environment, :variables, :execution_id, :status
  ]
  
  def new(workflow, execution_id, context \\ %{})
  def complete_node(graph, node_key, output_data, output_port)
  def get_ready_nodes(graph)
  def get_node_input(graph, node_key)
end

# 1.2 Create conversion utilities for gradual migration
defmodule Prana.ExecutionGraph.Migration do
  @doc "Convert current execution + graph to unified structure"
  def from_legacy(execution, execution_graph) do
    ExecutionGraph.new(execution_graph.workflow, execution.id)
    |> restore_runtime_state(execution.__runtime)
  end
  
  @doc "Convert unified structure back to legacy format for compatibility"
  def to_legacy(graph) do
    execution = create_execution_from_graph(graph)
    execution_graph = create_graph_from_unified(graph)
    {execution, execution_graph}
  end
end

# 1.3 Add comprehensive tests for new structure
test "unified execution graph maintains same behavior" do
  # Test all operations produce identical results
end
```

**Deliverables**:
- ✅ New `Prana.ExecutionGraph` module with unified structure
- ✅ Migration utilities for gradual transition
- ✅ Comprehensive test suite ensuring behavioral compatibility
- ✅ Documentation for new structure

### Phase 2: GraphExecutor Migration (Week 2-3)

**Goal**: Update GraphExecutor to use unified structure internally while maintaining external APIs

```elixir
# 2.1 Create new execute_graph function using unified structure
defmodule Prana.GraphExecutor do
  # NEW: Unified execution
  def execute_graph_v2(workflow, execution_id, context \\ %{}) do
    graph = ExecutionGraph.new(workflow, execution_id, context)
    execute_loop(graph)
  end
  
  # LEGACY: Keep existing function for compatibility
  def execute_graph(execution_graph, context \\ %{}) do
    # Convert to new format, execute, convert back
    workflow = execution_graph.workflow
    execution_id = generate_execution_id()
    
    case execute_graph_v2(workflow, execution_id, context) do
      {:ok, final_graph} -> 
        {execution, _} = ExecutionGraph.Migration.to_legacy(final_graph)
        {:ok, execution}
      other -> other
    end
  end
  
  defp execute_loop(graph) do
    case ExecutionGraph.get_ready_nodes(graph) do
      [] -> {:ok, finalize_execution(graph)}
      ready_nodes ->
        selected_node = select_node_for_execution(ready_nodes, graph)
        
        case execute_single_node(selected_node, graph) do
          {:ok, updated_graph} -> execute_loop(updated_graph)
          {:suspend, suspended_graph} -> {:suspend, suspended_graph}
          {:error, failed_graph} -> {:error, failed_graph}
        end
    end
  end
end

# 2.2 Update all internal functions to use unified graph
defp execute_single_node(node, graph) do
  input_data = ExecutionGraph.get_node_input(graph, node.key)
  
  case NodeExecutor.execute_node(node, input_data) do
    {:ok, output_data, output_port} ->
      updated_graph = ExecutionGraph.complete_node(graph, node.key, output_data, output_port)
      {:ok, updated_graph}
      
    {:suspend, suspend_data} ->
      suspended_graph = ExecutionGraph.suspend_execution(graph, node.key, suspend_data)
      {:suspend, suspended_graph}
      
    {:error, error_data} ->
      failed_graph = ExecutionGraph.fail_execution(graph, node.key, error_data)
      {:error, failed_graph}
  end
end
```

**Deliverables**:
- ✅ New unified execution logic in GraphExecutor
- ✅ Backward compatibility layer for existing APIs
- ✅ Migration of all internal functions to use unified structure
- ✅ Updated tests to cover both legacy and new execution paths

### Phase 3: Clean Execution Struct (Week 3-4)

**Goal**: Remove `__runtime` from Execution and clean up persistent data structure

```elixir
# 3.1 Create new clean Execution struct
defmodule Prana.Execution.V2 do
  defstruct [
    # Core metadata
    :id, :workflow_id, :workflow_version, :status,
    :started_at, :completed_at,
    
    # Execution hierarchy
    :parent_execution_id, :root_execution_id, :execution_mode,
    
    # Results and audit trail (contains ALL execution data)
    :trigger_type, :trigger_data,
    :node_executions, :current_execution_index,
    
    # Metadata
    :metadata
    
    # REMOVED: __runtime, vars, context_data, preparation_data, output_data, error_data
    # REMOVED: suspended_node_id, suspension_type, suspended_at (duplicated in NodeExecution)
    # REMOVED: suspension_data (transient application coordination data), resume_token (unused)
  ]
end

# 3.2 Create migration path for persistent storage
defmodule Prana.Execution.Migration do
  def migrate_to_v2(%Prana.Execution{} = old_execution) do
    %Prana.Execution.V2{
      id: old_execution.id,
      workflow_id: old_execution.workflow_id,
      # ... copy all fields except __runtime
    }
  end
  
  def extract_graph_context(execution) do
    %{
      variables: execution.vars || %{},
      environment: execution.context_data || %{},
      preparation_data: execution.preparation_data || %{}
    }
  end
end

# 3.3 Update all Execution functions to work with clean structure
defmodule Prana.Execution.V2 do
  def complete(execution, output_data) do
    %{execution | 
      status: :completed,
      completed_at: DateTime.utc_now(),
      output_data: output_data
    }
  end
  
  def suspend(execution, _node_key, _suspension_type, _suspension_data, _resume_token \\ nil) do
    # Suspension info now stored only in NodeExecution - just update status
    # suspension_data is for application coordination, not persistent storage
    %{execution | status: :suspended}
  end
  
  def get_suspended_node_execution(execution) do
    # Find suspended NodeExecution from node_executions
    execution.node_executions
    |> Map.values()
    |> List.flatten()
    |> Enum.find(&(&1.status == :suspended))
  end
  
  def generate_suspension_data(suspended_node_execution) do
    # Generate minimal application coordination data on-demand from NodeExecution
    case suspended_node_execution.suspension_type do
      type when type in [:webhook, :interval, :schedule] ->
        # Timing-based suspension with explicit type
        %{
          type: type,
          wait_till: suspended_node_execution.suspension_data.wait_till
        }
        
      :sub_workflow ->
        # Workflow coordination suspension with explicit type
        %{
          type: :sub_workflow,
          sub_workflow_id: suspended_node_execution.suspension_data.sub_workflow_id,
          execution_mode: suspended_node_execution.suspension_data.execution_mode
        }
    end
  end
  
  # Remove all __runtime manipulation functions
end
```

**Deliverables**:
- ✅ Clean Execution.V2 struct without mixed runtime data
- ✅ Migration utilities for existing persistent storage
- ✅ Updated all Execution functions to work with clean structure
- ✅ Database migration scripts for persistent storage

### Phase 4: Test Migration and Cleanup (Week 4-5)

**Goal**: Migrate all tests and remove legacy code

```elixir
# 4.1 Update test helpers for new structure
defmodule TestHelpers.ExecutionGraph do
  def create_test_graph(workflow, execution_id \\ "test_execution") do
    ExecutionGraph.new(workflow, execution_id, %{})
  end
  
  def assert_node_completed(graph, node_key, expected_output) do
    actual_output = Map.get(graph.completed_nodes, node_key)
    assert actual_output == expected_output
  end
  
  def assert_nodes_ready(graph, expected_node_keys) do
    ready_nodes = ExecutionGraph.get_ready_nodes(graph)
    ready_keys = MapSet.new(ready_nodes, & &1.key)
    expected_set = MapSet.new(expected_node_keys)
    assert ready_keys == expected_set
  end
end

# 4.2 Convert all existing tests to use new structure
# BEFORE: Complex test setup with separate structures
test "executes conditional branching correctly" do
  execution = create_execution()
  execution_graph = compile_workflow(workflow)
  context = build_runtime_context()
  
  case GraphExecutor.execute_graph(execution_graph, context) do
    {:ok, final_execution} ->
      assert final_execution.__runtime["executed_nodes"] == ["trigger", "condition", "branch_a"]
  end
end

# AFTER: Simple unified test
test "executes conditional branching correctly" do
  graph = TestHelpers.ExecutionGraph.create_test_graph(workflow)
  
  case GraphExecutor.execute_graph_v2(workflow, "test_id") do
    {:ok, final_graph} ->
      assert Map.keys(final_graph.completed_nodes) == ["trigger", "condition", "branch_a"]
  end
end

# 4.3 Remove legacy code and compatibility layers
# - Remove old Execution.__runtime functions
# - Remove ExecutionGraph.Migration module
# - Remove GraphExecutor.execute_graph (legacy version)
# - Update all documentation to reference new structure
```

**Deliverables**:
- ✅ All tests migrated to new structure
- ✅ Legacy compatibility code removed
- ✅ Updated documentation and examples
- ✅ Performance benchmarks confirming memory savings

## Risk Mitigation

### High Risk: Test Failures During Migration

**Risk**: 25+ test files with `__runtime` assertions will fail during migration

**Mitigation Strategy**:
```elixir
# Phase 1: Parallel implementation keeps existing tests working
# Phase 2: Gradual migration with compatibility layer  
# Phase 3: Batch test updates with helper functions
# Phase 4: Final cleanup after all tests pass

# Test migration helper to minimize manual updates
defmodule TestMigrationHelper do
  def convert_runtime_assertion(test_code) do
    test_code
    |> String.replace("execution.__runtime[\"nodes\"]", "graph.completed_nodes")
    |> String.replace("execution.__runtime[\"active_nodes\"]", "graph.active_nodes") 
    |> String.replace("execution.__runtime[\"executed_nodes\"]", "Map.keys(graph.completed_nodes)")
  end
end
```

### Medium Risk: Performance Regression

**Risk**: On-demand reverse connection lookup might be slower than pre-computed maps

**Mitigation Strategy**:
```elixir
# Benchmark critical paths to ensure acceptable performance
# If needed, add caching for frequently accessed reverse connections

defmodule Prana.ExecutionGraph do
  # Add optional reverse connection caching if performance requires
  def get_incoming_connections(graph, node_key, port) do
    cache_key = {node_key, port}
    
    case Map.get(graph.reverse_connection_cache || %{}, cache_key) do
      nil ->
        connections = compute_incoming_connections(graph, node_key, port)
        updated_graph = put_in(graph.reverse_connection_cache[cache_key], connections)
        {connections, updated_graph}
        
      cached_connections ->
        {cached_connections, graph}
    end
  end
end
```

### Low Risk: API Breaking Changes

**Risk**: External code depends on current Execution.__runtime structure

**Mitigation Strategy**:
- Maintain backward compatibility in Phase 1-2
- Provide clear migration guide for external dependencies
- Use deprecation warnings before removing legacy APIs

## Success Metrics

### Memory Efficiency
- **Target**: 50-60% memory reduction for typical 100-node workflows (updated after clarifying suspension data purpose)
- **Measurement**: Memory profiling before/after with representative workflows
- **Baseline**: Current 100-node workflow with conditional branching and sub-workflows

### Code Quality  
- **Target**: Reduce complexity in core execution functions by 30%
- **Measurement**: Cyclomatic complexity analysis of GraphExecutor functions
- **Baseline**: Current GraphExecutor.execute_workflow_loop complexity

### Maintainability
- **Target**: Single responsibility principle enforced across all modules
- **Measurement**: Code review checklist confirming clean separation of concerns
- **Success**: GraphExecutor only handles orchestration, Execution only handles results

### Performance
- **Target**: No performance regression, potential 10-20% improvement from better cache locality
- **Measurement**: Benchmark suite covering typical workflow execution patterns
- **Baseline**: Current execution performance on representative workflows

## Timeline Summary

| Phase | Duration | Key Deliverable | Risk Level |
|-------|----------|----------------|------------|
| 1 | Week 1-2 | Unified ExecutionGraph with compatibility | Low |
| 2 | Week 2-3 | GraphExecutor using unified structure | Medium |  
| 3 | Week 3-4 | Clean Execution struct migration | Medium |
| 4 | Week 4-5 | Test migration and legacy cleanup | High |

**Total Duration**: 4-5 weeks for complete migration

## Long-term Benefits

### Improved Developer Experience
- **Single source of truth**: No more passing `(execution_graph, execution)` everywhere
- **Intuitive APIs**: `ExecutionGraph.get_ready_nodes(graph)` vs `find_ready_nodes(graph, execution.node_executions, execution.__runtime)`
- **Better debugging**: Runtime state co-located with static workflow structure

### Enhanced Performance
- **Memory efficiency**: 50-60% reduction in memory usage (improved after clarifying suspension data purpose)
- **Cache locality**: Smaller, more focused data structures
- **Reduced allocations**: No context conversion overhead between structures

### Future-Proof Architecture
- **Clean extension points**: Adding new runtime state is straightforward
- **Testability**: Mocking ExecutionGraph is simpler than mocking multiple structures  
- **Maintainability**: Single responsibility principle enforced across all components

## Conclusion

This refactoring plan addresses the core architectural issues identified in Prana's execution engine while maintaining a pragmatic balance between benefits and complexity. The unified ExecutionGraph approach eliminates artificial separation between static and runtime data, providing significant memory savings and improved maintainability.

Key improvements include standardized suspension data structures for consistent application coordination, elimination of redundant fields, and clear separation between persistent audit trails and transient coordination data.

The phased approach ensures minimal disruption to existing functionality while providing clear migration paths for all affected components. The estimated 50-60% memory reduction (improved from initial 40-50% after eliminating all redundant fields), combined with improved code organization and standardized data structures, makes this refactoring a high-value investment for the long-term health of the Prana platform.