# Simple Loop Implementation Plan - Detailed

**Date**: July 2025
**Status**: Implementation Ready
**Scope**: Minimal changes to enable n8n-style simple loops in Prana

## Executive Summary

This plan implements simple loops using n8n's proven approach: **allow node re-execution with explicit termination conditions**. The implementation focuses on minimal, surgical changes to existing code while maintaining safety and backward compatibility.

## Implementation Strategy

### Core Philosophy Change
- **From**: "Prevent all node re-execution"
- **To**: "Allow controlled node re-execution with safety mechanisms"

### Key Design Principles
1. **Minimal Changes**: Modify existing code minimally
2. **Safety First**: Multiple termination mechanisms
3. **Backward Compatible**: Existing workflows unchanged
4. **n8n Inspired**: Follow proven patterns

## Phase 1: Enable Cycle Support (Week 1)

### 1.1 Workflow Validation Changes

**File**: `lib/prana/core/workflow.ex`

**Objective**: Allow simple loops while blocking complex cycles

```elixir
# Replace validate_no_cycles function
defp validate_no_cycles(%__MODULE__{} = workflow) do
  case detect_and_classify_cycles(workflow) do
    {:ok, :no_cycles} -> :ok
    {:ok, :simple_loops} -> :ok  # NEW: Allow simple loops
    {:error, reason} -> {:error, reason}
  end
end

# NEW: Implement real cycle detection
defp detect_and_classify_cycles(workflow) do
  cycles = detect_cycles_dfs(workflow.nodes, workflow.connections)

  case cycles do
    [] -> {:ok, :no_cycles}
    cycles -> classify_loop_safety(cycles, workflow.nodes)
  end
end

# NEW: Classify cycles as safe simple loops or dangerous
defp classify_loop_safety(cycles, nodes) do
  logic_node_ids =
    nodes
    |> Enum.filter(&(&1.integration_name == "logic"))
    |> MapSet.new(& &1.id)

  safe_cycles =
    Enum.filter(cycles, fn cycle ->
      # Safe if: contains logic node AND is simple (≤ 5 nodes)
      has_logic_node = Enum.any?(cycle, &MapSet.member?(logic_node_ids, &1))
      is_simple = length(cycle) <= 5

      has_logic_node and is_simple
    end)

  cond do
    length(safe_cycles) == length(cycles) -> {:ok, :simple_loops}
    true -> {:error, "Workflow contains unsafe cycles"}
  end
end

# NEW: Real DFS cycle detection
defp detect_cycles_dfs(nodes, connections) do
  graph = build_adjacency_list(connections)

  {_, cycles} =
    Enum.reduce(nodes, {MapSet.new(), []}, fn node, {visited, found_cycles} ->
      if MapSet.member?(visited, node.id) do
        {visited, found_cycles}
      else
        case dfs_find_cycles(graph, node.id, MapSet.new(), []) do
          {:cycle, cycle_path} ->
            new_visited = MapSet.union(visited, MapSet.new(cycle_path))
            {new_visited, [cycle_path | found_cycles]}
          :no_cycle ->
            {MapSet.put(visited, node.id), found_cycles}
        end
      end
    end)

  cycles
end

defp build_adjacency_list(connections) do
  Enum.reduce(connections, %{}, fn conn, acc ->
    Map.update(acc, conn.from, [conn.to], &[conn.to | &1])
  end)
end

defp dfs_find_cycles(graph, current, visited, path) do
  if current in path do
    # Found cycle - extract the cycle portion
    cycle_start_idx = Enum.find_index(path, &(&1 == current))
    cycle = Enum.drop(path, cycle_start_idx)
    {:cycle, [current | cycle]}
  else
    new_visited = MapSet.put(visited, current)
    new_path = [current | path]
    neighbors = Map.get(graph, current, [])

    Enum.reduce_while(neighbors, :no_cycle, fn neighbor, _acc ->
      if MapSet.member?(visited, neighbor) do
        {:cont, :no_cycle}
      else
        case dfs_find_cycles(graph, neighbor, new_visited, new_path) do
          {:cycle, cycle_path} -> {:halt, {:cycle, cycle_path}}
          :no_cycle -> {:cont, :no_cycle}
        end
      end
    end)
  end
end
```

**Testing**:
```elixir
# Test cases for cycle detection
test "allows simple loops with logic nodes" do
  workflow = build_workflow_with_simple_loop()
  assert {:ok, :simple_loops} = validate_workflow(workflow)
end

test "rejects complex nested cycles" do
  workflow = build_workflow_with_nested_cycles()
  assert {:error, _reason} = validate_workflow(workflow)
end
```

### 1.2 Add Basic Iteration Support to NodeExecution

**File**: `lib/prana/core/node_execution.ex`

**Objective**: Track which iteration of a node this execution represents

```elixir
# Add to @type t definition
@type t :: %__MODULE__{
        # ... existing fields ...
        iteration: integer(),           # NEW: Which iteration (1, 2, 3...)
        run_index: integer()           # NEW: Global execution counter
      }

# Add to defstruct
defstruct [
  # ... existing fields ...
  iteration: 1,        # NEW: Default to first iteration
  run_index: 0         # NEW: Default to first run
]

# NEW: Helper to create iteration execution
def new_iteration(base_execution, iteration, run_index) do
  %__MODULE__{
    id: "#{base_execution.id}_iter_#{iteration}",
    execution_id: base_execution.execution_id,
    node_id: base_execution.node_id,
    status: "pending",
    iteration: iteration,
    run_index: run_index,
    params: base_execution.params,
    metadata: base_execution.metadata,
    context_data: base_execution.context_data
  }
end

# NEW: Check if this is a loop iteration
def is_loop_iteration?(%__MODULE__{iteration: iteration}) do
  iteration > 1
end
```

**Testing**:
```elixir
test "creates iteration executions correctly" do
  base = NodeExecution.new("exec_1", "node_1")
  iter2 = NodeExecution.new_iteration(base, 2, 5)

  assert iter2.iteration == 2
  assert iter2.run_index == 5
  assert NodeExecution.is_loop_iteration?(iter2)
end
```

## Phase 2: Enable Node Re-execution (Week 2)

### 2.1 Modify GraphExecutor Ready Node Detection

**File**: `lib/prana/execution/graph_executor.ex`

**Objective**: Allow nodes to execute multiple times with safety checks

```elixir
# REPLACE the current find_ready_nodes function
def find_ready_nodes(%ExecutionGraph{} = execution_graph, completed_node_executions, execution) do
  # Group executions by node_id
  executions_by_node = Enum.group_by(completed_node_executions, & &1.node_id)

  # Get latest execution status for dependency checking
  latest_execution_status =
    Enum.map(executions_by_node, fn {node_id, executions} ->
      latest = Enum.max_by(executions, & &1.iteration, fn -> nil end)
      {node_id, latest}
    end)
    |> Map.new()

  execution_graph.workflow.nodes
  |> Enum.filter(fn node ->
    should_execute_node?(node, executions_by_node, execution)
  end)
  |> Enum.filter(fn node ->
    dependencies_satisfied_with_iterations?(node, execution_graph.dependency_graph, latest_execution_status)
  end)
  |> filter_conditional_branches(execution_graph, execution.__runtime)
end

# NEW: Determine if a node should execute using metadata-based loop state
defp should_execute_node?(node, executions_by_node, execution) do
  # Check if node is part of an active loop (from metadata)
  active_loops = get_in(execution.metadata, ["loop_state", "active_loops"]) || %{}

  participating_loop =
    Enum.find(active_loops, fn {_loop_id, loop_data} ->
      node.id in loop_data["nodes"]
    end)

  case participating_loop do
    nil ->
      # Not in a loop - execute if not already executed
      not Map.has_key?(executions_by_node, node.id)

    {loop_id, _loop_data} ->
      # In a loop - check if should continue using metadata
      Prana.LoopStateManager.should_continue_loop?(execution, loop_id)
  end
end

# NEW: Check if node is part of a loop pattern
defp is_loop_node?(node, executions_by_node, execution_context) do
  # Simple heuristic: a node is part of a loop if it has been executed before
  # and there are active loop indicators in the execution context
  node_executions = Map.get(executions_by_node, node.id, [])
  has_been_executed = not Enum.empty?(node_executions)

  # Check if any completed execution indicates loop continuation
  if has_been_executed do
    last_execution = List.last(node_executions)
    # Logic nodes with "true" output indicate loop continuation
    last_execution.output_port == "true" and
    is_logic_integration_node?(node)
  else
    false
  end
end

defp is_logic_integration_node?(node) do
  node.integration_name == "logic"
end

# NEW: Determine if loop should continue
defp should_continue_loop?(node, node_executions, execution_context) do
  current_iteration = length(node_executions)
  max_iterations = get_max_iterations(execution_context)
  last_execution = List.last(node_executions)

  cond do
    # Safety: Check max iterations
    current_iteration >= max_iterations -> false

    # Check if last execution indicated termination
    should_terminate_based_on_output?(node, last_execution) -> false

    # Check if there's input ready for next iteration
    has_loop_input_ready?(node, execution_context) -> true

    # Default: don't continue
    true -> false
  end
end

defp should_terminate_based_on_output?(node, last_execution) do
  case {node.integration_name, node.action_name} do
    {"logic", "if_condition"} ->
      # IF condition with false output indicates loop termination
      last_execution.output_port == "false"

    _ ->
      # Non-logic nodes don't control termination
      false
  end
end

defp has_loop_input_ready?(node, execution_context) do
  # Check if there's data available for the next loop iteration
  # This is a simplified implementation - in practice, you'd check
  # if the loop-back connections have provided new data
  true  # For now, assume input is ready
end

defp get_max_iterations(execution_context) do
  Map.get(execution_context, "max_iterations", 10)  # Conservative default
end

# NEW: Modified dependency satisfaction for iterations
defp dependencies_satisfied_with_iterations?(node, dependencies, latest_execution_status) do
  node_dependencies = Map.get(dependencies, node.id, [])

  Enum.all?(node_dependencies, fn dep_node_id ->
    case Map.get(latest_execution_status, dep_node_id) do
      nil -> false  # Dependency never executed
      %{status: "completed"} -> true  # Dependency completed
      _ -> false  # Dependency not completed
    end
  end)
end
```

### 2.2 Add Loop State Persistence in Execution Metadata

```elixir
# NEW: Loop state manager for metadata persistence
defmodule Prana.LoopStateManager do
  @moduledoc """
  Manages loop state persistence in execution metadata
  """

  @doc """
  Initialize loop state in execution metadata
  """
  def initialize_loop_state(%WorkflowExecution{} = execution) do
    loop_state = %{
      "active_loops" => %{},
      "node_iterations" => %{},
      "loop_termination_flags" => %{},
      "global_run_counter" => 0,
      "max_iterations" => 10
    }

    put_in(execution.metadata["loop_state"], loop_state)
  end

  @doc """
  Start a new loop
  """
  def start_loop(execution, loop_id, participating_nodes, termination_node) do
    loop_data = %{
      "loop_id" => loop_id,
      "nodes" => participating_nodes,
      "current_iteration" => 1,
      "termination_node" => termination_node,
      "loop_context" => %{},
      "created_at" => DateTime.utc_now()
    }

    put_in(execution.metadata["loop_state"]["active_loops"][loop_id], loop_data)
  end

  @doc """
  Increment loop iteration
  """
  def increment_loop_iteration(execution, loop_id, node_id) do
    execution
    |> update_in(["metadata", "loop_state", "active_loops", loop_id, "current_iteration"], &(&1 + 1))
    |> update_in(["metadata", "loop_state", "node_iterations", node_id], fn
      nil -> 1
      count -> count + 1
    end)
    |> update_in(["metadata", "loop_state", "global_run_counter"], &(&1 + 1))
  end

  @doc """
  Terminate a loop
  """
  def terminate_loop(execution, loop_id) do
    execution
    |> put_in(["metadata", "loop_state", "loop_termination_flags", loop_id], true)
    |> update_in(["metadata", "loop_state", "active_loops"], &Map.delete(&1, loop_id))
  end

  @doc """
  Check if a loop should continue
  """
  def should_continue_loop?(execution, loop_id) do
    loop_state = get_in(execution.metadata, ["loop_state", "active_loops", loop_id])
    termination_flag = get_in(execution.metadata, ["loop_state", "loop_termination_flags", loop_id])

    cond do
      is_nil(loop_state) -> false
      termination_flag == true -> false
      loop_state["current_iteration"] >= get_max_iterations(execution) -> false
      true -> true
    end
  end

  defp get_max_iterations(execution) do
    get_in(execution.metadata, ["loop_state", "max_iterations"]) || 10
  end
end

# SIMPLIFIED runtime restoration (no complex rebuilding needed!)
defp initialize_runtime_state(execution, env_data) do
  base_runtime = %{
    "nodes" => extract_nodes_from_executions(execution.node_executions),
    "env" => env_data,
    "active_paths" => %{},
    "executed_nodes" => Enum.map(execution.node_executions, & &1.node_id)
  }

  # Simply copy loop state from metadata (no reconstruction!)
  loop_state = get_in(execution.metadata, ["loop_state"]) || %{}
  Map.merge(base_runtime, loop_state)
end
```

**Testing**:
```elixir
test "persists loop state in execution metadata" do
  # Setup workflow with simple loop
  workflow = create_simple_loop_workflow()
  execution = initialize_execution_with_loops(workflow, %{})

  # Verify loop state is initialized in metadata
  loop_state = get_in(execution.metadata, ["loop_state"])
  assert map_size(loop_state["active_loops"]) == 1
  assert loop_state["node_iterations"] == %{}

  # Execute first iteration
  {:ok, after_first} = execute_workflow_step(execution)

  # Verify loop state is updated in metadata
  updated_loop_state = get_in(after_first.metadata, ["loop_state"])
  assert updated_loop_state["node_iterations"]["increment"] == 1
  assert updated_loop_state["global_run_counter"] == 1

  # Simulate persistence save/load cycle
  persisted_execution = save_and_load_execution(after_first)

  # Verify loop state survives persistence
  restored_loop_state = get_in(persisted_execution.metadata, ["loop_state"])
  assert restored_loop_state == updated_loop_state

  # Continue execution
  {:ok, after_second} = execute_workflow_step(persisted_execution)

  # Verify loop continued correctly
  final_loop_state = get_in(after_second.metadata, ["loop_state"])
  assert final_loop_state["node_iterations"]["increment"] == 2
end
```

### 2.3 Loop Detection and Initialization

```elixir
# NEW: Loop detection during workflow compilation
defmodule Prana.LoopDetector do
  @doc """
  Detect loops in workflow and prepare metadata for initialization
  """
  def detect_and_prepare_loops(workflow) do
    cycles = detect_cycles_dfs(workflow.nodes, workflow.connections)

    loop_metadata =
      cycles
      |> Enum.with_index()
      |> Enum.map(fn {cycle_nodes, index} ->
        loop_id = "loop_#{index + 1}"
        termination_node = find_logic_node_in_cycle(cycle_nodes, workflow.nodes)

        {loop_id, %{
          "nodes" => cycle_nodes,
          "termination_node" => termination_node
        }}
      end)
      |> Map.new()

    %{"detected_loops" => loop_metadata}
  end

  defp find_logic_node_in_cycle(cycle_nodes, all_nodes) do
    # Find the Logic integration node in the cycle (loop controller)
    Enum.find(cycle_nodes, fn node_id ->
      node = Enum.find(all_nodes, &(&1.id == node_id))
      node && node.integration_name == "logic"
    end)
  end
end

# NEW: Initialize execution with loop metadata
def initialize_execution_with_loops(workflow, trigger_data) do
  loop_compile_metadata = Prana.LoopDetector.detect_and_prepare_loops(workflow)

  execution =
    %WorkflowExecution{
      id: generate_id(),
      workflow_id: workflow.id,
      status: "running",
      metadata: %{
        "loop_compile_info" => loop_compile_metadata
      }
    }
    |> Prana.LoopStateManager.initialize_loop_state()

  # Auto-start detected loops
  detected_loops = loop_compile_metadata["detected_loops"] || %{}

  Enum.reduce(detected_loops, execution, fn {loop_id, loop_info}, acc ->
    Prana.LoopStateManager.start_loop(
      acc,
      loop_id,
      loop_info["nodes"],
      loop_info["termination_node"]
    )
  end)
end

# NEW: Update node execution to handle loop state changes
defp execute_single_node_with_loop_tracking(selected_node, execution_graph, execution) do
  # Find if this node is part of a loop
  loop_id = find_node_loop_id(selected_node, execution)

  case execute_single_node_with_events(selected_node, execution_graph, execution) do
    {%NodeExecution{status: "completed"} = node_execution, updated_execution} ->
      # Update loop state if this is a loop node
      final_execution =
        if loop_id do
          handle_loop_node_completion(updated_execution, selected_node, node_execution, loop_id)
        else
          updated_execution
        end

      {:ok, final_execution}

    other_result ->
      other_result
  end
end

defp handle_loop_node_completion(execution, node, node_execution, loop_id) do
  # Update loop iteration count
  updated_execution =
    Prana.LoopStateManager.increment_loop_iteration(execution, loop_id, node.id)

  # Check if this node terminates the loop
  if should_terminate_loop_after_execution?(node, node_execution) do
    Prana.LoopStateManager.terminate_loop(updated_execution, loop_id)
  else
    updated_execution
  end
end

defp should_terminate_loop_after_execution?(node, node_execution) do
  # Logic nodes with "false" output terminate loops
  node.integration_name == "logic" and node_execution.output_port == "false"
end

defp find_node_loop_id(node, execution) do
  active_loops = get_in(execution.metadata, ["loop_state", "active_loops"]) || %{}

  Enum.find_value(active_loops, fn {loop_id, loop_data} ->
    if node.id in loop_data["nodes"], do: loop_id, else: nil
  end)
end
```

## Phase 3: Safety Mechanisms (Week 3)

### 3.1 Add Safety Checks and Limits

```elixir
# NEW: Safety validation using metadata-based loop state
defp validate_loop_safety(node, execution) do
  loop_id = find_node_loop_id(node, execution)

  if loop_id do
    loop_state = get_in(execution.metadata, ["loop_state", "active_loops", loop_id])
    current_iteration = loop_state["current_iteration"]
    max_iterations = get_in(execution.metadata, ["loop_state", "max_iterations"]) || 10

    cond do
      # Check maximum iterations
      current_iteration > max_iterations ->
        {:error, "Loop #{loop_id} exceeded maximum iterations (#{max_iterations})"}

      # Check loop timeout
      loop_timeout_exceeded?(loop_state) ->
        {:error, "Loop #{loop_id} execution timeout exceeded"}

      true ->
        :ok
    end
  else
    :ok
  end
end

defp loop_timeout_exceeded?(loop_state) do
  created_at = loop_state["created_at"]
  max_duration_ms = 60_000  # 1 minute

  if created_at do
    DateTime.diff(DateTime.utc_now(), created_at, :millisecond) > max_duration_ms
  else
    false
  end
end

defp rapid_execution_detected?(node_executions) do
  if length(node_executions) >= 3 do
    recent_executions = Enum.take(node_executions, -3)

    # Check if executions are happening too quickly
    time_spans =
      recent_executions
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [first, second] ->
        if first.completed_at and second.started_at do
          DateTime.diff(second.started_at, first.completed_at, :millisecond)
        else
          1000  # Default to safe interval
        end
      end)

    avg_interval = Enum.sum(time_spans) / length(time_spans)
    avg_interval < 50  # Less than 50ms between executions
  else
    false
  end
end

defp loop_timeout_exceeded?(node_executions) do
  case {List.first(node_executions), List.last(node_executions)} do
    {%{started_at: first_start}, %{completed_at: last_end}}
    when not is_nil(first_start) and not is_nil(last_end) ->
      total_duration = DateTime.diff(last_end, first_start, :millisecond)
      total_duration > 60_000  # 1 minute max for loop

    _ ->
      false
  end
end

# NEW: Integration with existing execute_single_node function
defp execute_single_node_with_loop_safety(selected_node, execution_graph, execution) do
  node_executions =
    execution.node_executions
    |> Enum.filter(&(&1.node_id == selected_node.id))

  case validate_loop_safety(selected_node, node_executions, execution.__runtime) do
    :ok ->
      execute_single_node_with_events(selected_node, execution_graph, execution)

    {:error, reason} ->
      # Create failed execution
      failed_execution = create_failed_node_execution(selected_node, execution, reason)
      updated_execution = Execution.add_node_execution(execution, failed_execution)
      {:error, updated_execution}
  end
end
```

## Phase 4: Testing and Integration (Week 4)

### 4.1 Comprehensive Test Suite

```elixir
defmodule Prana.SimpleLoopIntegrationTest do
  use ExUnit.Case, async: false

  alias Prana.GraphExecutor
  alias Prana.WorkflowCompiler

  describe "simple counter loop" do
    test "executes counter loop correctly" do
      # Create workflow: Init(0) → Increment → IF(< 3) → (true: Increment, false: End)
      workflow = build_counter_loop_workflow(max_count: 3)
      {:ok, execution_graph} = WorkflowCompiler.compile(workflow)

      context = %{
        workflow_loader: fn _id -> {:error, "not implemented"} end,
        variables: %{},
        metadata: %{}
      }

      {:ok, execution, last_output} = GraphExecutor.execute_workflow(execution_graph, context)

      # Verify increment node executed 3 times
      increment_executions = get_node_executions(execution, "increment")
      assert length(increment_executions) == 3

      # Verify iterations are tracked correctly
      assert Enum.map(increment_executions, & &1.iteration) == [1, 2, 3]

      # Verify final state
      assert execution.status == "completed"
    end

    test "respects maximum iteration limit" do
      workflow = build_infinite_loop_workflow()  # No termination condition
      {:ok, execution_graph} = WorkflowCompiler.compile(workflow)

      context = %{"max_iterations" => 5}

      {:ok, execution, last_output} = GraphExecutor.execute_workflow(execution_graph, context)

      # Should stop at max iterations and have error
      assert execution.status == "failed"
      failed_execution = get_failed_node_execution(execution)
      assert failed_execution.error_data["message"] =~ "exceeded maximum iterations"
    end
  end

  describe "retry pattern loop" do
    test "retries until success" do
      # Create workflow: Init → Attempt → IF(success) → (false: Increment + Attempt, true: End)
      workflow = build_retry_loop_workflow(fail_count: 2)
      {:ok, execution_graph} = WorkflowCompiler.compile(workflow)

      context = %{workflow_loader: fn _id -> {:error, "not implemented"} end}

      {:ok, execution, last_output} = GraphExecutor.execute_workflow(execution_graph, context)

      # Verify attempt node executed 3 times (fail, fail, success)
      attempt_executions = get_node_executions(execution, "attempt")
      assert length(attempt_executions) == 3

      # Verify final success
      assert execution.status == "completed"
    end
  end

  describe "safety mechanisms" do
    test "detects rapid execution" do
      # Create workflow with very fast loop
      workflow = build_rapid_loop_workflow()
      {:ok, execution_graph} = WorkflowCompiler.compile(workflow)

      # Mock very fast execution times
      context = %{mock_fast_execution: true}

      {:ok, execution, last_output} = GraphExecutor.execute_workflow(execution_graph, context)

      # Should detect rapid execution and fail
      assert execution.status == "failed"
      failed_execution = get_failed_node_execution(execution)
      assert failed_execution.error_data["message"] =~ "rapid execution detected"
    end
  end

  # Helper functions
  defp build_counter_loop_workflow(max_count: max_count) do
    # Implementation details for test workflow creation
  end

  defp get_node_executions(execution, node_id) do
    Enum.filter(execution.node_executions, &(&1.node_id == node_id))
  end

  defp get_failed_node_execution(execution) do
    Enum.find(execution.node_executions, &(&1.status == "failed"))
  end
end
```

### 4.2 Integration with Existing Features

```elixir
# Ensure compatibility with existing features
test "loops work with conditional branching" do
  # Test loop + IF/ELSE combinations
end

test "loops work with sub-workflows" do
  # Test loop containing sub-workflow calls
end

test "loops work with middleware" do
  # Test middleware events during loop execution
end

test "expression engine supports loop context" do
  # Test $runIndex and iteration variables
end
```

## Phase 5: Documentation and Examples (Week 5)

### 5.1 Update Documentation

```markdown
# Simple Loops in Prana

## Overview
Prana now supports simple loops using the same pattern as n8n: connect the output of a later node back to an earlier node to create a loop, and use Logic IF conditions to control termination.

## Basic Loop Pattern

```
Initialize → Process → Logic IF → (true: back to Process)
                               → (false: Complete)
```

## Safety Features
- Maximum 10 iterations by default (configurable)
- Automatic infinite loop detection
- Time-based termination (1 minute max)
- Rapid execution detection

## Expression Support
- `$runIndex`: Current iteration number
- `$iteration`: Node-specific iteration count
```

### 5.2 Example Workflows

```elixir
# Create example workflows demonstrating:
# 1. Counter loop
# 2. Retry pattern
# 3. Polling loop
# 4. Batch processing simulation
```

## Implementation Checklist

### Week 1: Foundation
- [ ] Update workflow validation to allow simple cycles
- [ ] Add iteration fields to NodeExecution
- [ ] Implement cycle detection algorithm
- [ ] Add basic tests

### Week 2: Core Functionality
- [ ] Modify GraphExecutor ready node detection
- [ ] Add loop continuation logic
- [ ] Update runtime state management
- [ ] Test basic loop execution

### Week 3: Safety
- [ ] Implement iteration limits
- [ ] Add rapid execution detection
- [ ] Add timeout mechanisms
- [ ] Add configuration support

### Week 4: Testing
- [ ] Comprehensive integration tests
- [ ] Safety mechanism tests
- [ ] Performance tests
- [ ] Backward compatibility tests

### Week 5: Polish
- [ ] Documentation updates
- [ ] Example workflows
- [ ] Performance optimizations
- [ ] Final testing

## Risk Mitigation

### Technical Risks
- **Infinite loops**: Multiple safety mechanisms prevent this
- **Performance impact**: Minimal changes to hot paths
- **Breaking changes**: All changes are backward compatible

### Mitigation Strategies
- **Feature flags**: Allow disabling loops if needed
- **Monitoring**: Add metrics for loop execution
- **Rollback plan**: Can revert by restoring cycle prevention

## Success Criteria

1. **Functional**: Simple loops work like n8n
2. **Safe**: No infinite loops possible
3. **Compatible**: Existing workflows unchanged
4. **Tested**: Comprehensive test coverage
5. **Documented**: Clear usage examples

This plan provides a clear path to implement n8n-style simple loops in Prana with minimal risk and maximum safety.
