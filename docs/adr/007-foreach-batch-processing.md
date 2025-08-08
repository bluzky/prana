# ADR-007: For_Each Batch Processing Implementation

**Date**: August 2025  
**Status**: Proposed  
**Deciders**: Prana Core Team  
**Supersedes**: None  
**Related**: ADR-006 (Loop Integration Design)  

## Context

Prana workflow automation platform needs batch processing capabilities similar to n8n's "Split in Batches" (Loop Over Items) node. This functionality is essential for:

1. **Large Dataset Processing**: Handle arrays with hundreds or thousands of items efficiently
2. **API Rate Limiting**: Process items in controlled batches to respect external service limits
3. **Memory Management**: Avoid loading entire datasets into memory at once
4. **Progress Tracking**: Provide visibility into batch processing progress

### Current State Analysis

Prana already has the foundational infrastructure for implementing batch processing:

- **Node Re-execution**: Supports `run_index` tracking for multiple executions of the same node
- **Expression System**: Provides access to previous node outputs via `$nodes.node_key.output`
- **State Persistence**: Node outputs are automatically persisted with WorkflowExecution
- **Loop-back Connections**: Existing architecture supports connecting node outputs back to previous nodes

### Research: n8n's Split in Batches

n8n's implementation provides:
- Configurable batch sizes
- Automatic iteration through all items
- Progress tracking (current batch, total batches)
- Result collection and concatenation
- Loop termination when all items are processed

## Decision

We will implement a `for_each_batch` action in the existing `Prana.Integrations.Loop` module that leverages Prana's current node re-execution infrastructure to provide n8n-style batch processing.

### Critical Data Flow Solution

**Problem Identified**: When multiple connections target the same input port, Prana uses `execution_index` to select the most recent data source. This breaks the loop pattern because:

- **First iteration**: Loop node should receive initial data (from source node)  
- **Subsequent iterations**: Loop node should receive batch results (from processing node)

**Solution**: Use separate input ports to distinguish data sources:
- `items` port: Receives initial dataset (first iteration only)
- `batch_results` port: Receives processed batch results (loop-back iterations)

### Core Design Principles

1. **Leverage Existing Infrastructure**: Use `run_index` and node output storage for state management
2. **Performance Optimized**: Calculate expensive operations (array length, total batches) once
3. **Expression Accessible**: Expose all loop variables via expression system
4. **Memory Efficient**: Process items in configurable batch sizes
5. **Progress Transparent**: Provide clear visibility into processing progress

## Architecture Design

### Loop Integration Structure

```elixir
defmodule Prana.Integrations.Loop do
  @behaviour Prana.Behaviour.Integration

  def definition do
    %Prana.Integration{
      name: "loop",
      display_name: "Loop Processing",
      description: "Batch processing and iteration control",
      actions: %{
        "for_each_batch" => %Prana.Action{
          name: "for_each_batch",
          display_name: "For Each Batch",
          description: "Process array items in configurable batches with automatic iteration",
          input_ports: ["items", "batch_results"],  # ✅ Separate ports
          output_ports: ["batch", "done", "error"],
          module: __MODULE__,
          function: :for_each_batch
        }
      }
    }
  end
end
```

### State Management Strategy

**Core Insight**: Prana's `run_index` system provides natural iteration tracking, and node outputs provide persistent state storage between iterations. To handle complex scenarios like nested loops, we introduce an explicit `is_loopback` flag in the execution context.

```elixir
# Iteration 0 (First execution):
run_index = 0, is_loopback = false
# Initialize loop state, emit first batch

# Iteration 1 (Loop-back execution):  
run_index = 1, is_loopback = true
# Read previous state from node output, process next batch

# Iteration N (Final execution):
run_index = N, is_loopback = true
# Continue until all batches processed, emit final results through "done" port

# New dataset (e.g., nested loop reset):
run_index = M, is_loopback = false
# Reset loop state with new data, start fresh batch processing
```

### Optimized Implementation

```elixir
defmodule Prana.Integrations.Loop do
  def for_each_batch(input) do
    is_loopback = get_in(input, ["$execution", "is_loopback"]) || false
    
    case is_loopback do
      false -> initialize_first_batch(input)
      true -> process_next_batch(input)
    end
  end
  
  defp initialize_first_batch(input) do
    # ✅ First iteration: get items from "items" port
    items = get_items_from_port(input)
    batch_size = get_batch_size(input)
    items_count = length(items)  # ✅ Calculated ONCE
    total_batches = ceil(items_count / batch_size)
    
    # Store all computed values for reuse
    loop_state = %{
      "items" => items,
      "batch_size" => batch_size,
      "items_count" => items_count,      # ✅ Stored once
      "total_batches" => total_batches,  # ✅ Stored once
      "processed_results" => []
    }
    
    first_batch = Enum.take(items, batch_size)
    
    {:ok, %{
      "batch" => first_batch,
      "loop_state" => loop_state,        # Internal state
      "batch_index" => 0,                # ✅ Expression accessible
      "items_count" => items_count,      # ✅ Expression accessible
      "total_batches" => total_batches,  # ✅ Expression accessible
      "has_more_batches" => items_count > batch_size
    }, "batch"}
  end
  
  defp process_next_batch(input) do
    current_node_key = get_in(input, ["$execution", "current_node_key"])
    previous_output = get_in(input, ["$nodes", current_node_key])
    
    case previous_output["loop_state"] do
      nil -> 
        {:error, "No loop state found for loopback execution", "error"}
        
      loop_state ->
        # ✅ Get batch results from "batch_results" port
        batch_results = get_batch_results_from_port(input)
        
        # ✅ Reuse stored values - no recalculation
        items_count = loop_state["items_count"]
        batch_size = loop_state["batch_size"]
        total_batches = loop_state["total_batches"]
        run_index = get_in(input, ["$execution", "run_index"])
        
        updated_results = loop_state["processed_results"] ++ batch_results
        processed_count = run_index * batch_size
        remaining_count = items_count - processed_count
    
    case remaining_count do
      n when n <= 0 -> 
        # All batches processed - emit final results
        {:ok, %{
          "results" => updated_results,
          "total_processed" => items_count,
          "batches_completed" => total_batches
        }, "done"}
        
      remaining_count ->
        # More batches to process
        next_batch_size = min(remaining_count, batch_size)
        next_batch = previous_state["items"]
                    |> Enum.drop(processed_count)
                    |> Enum.take(next_batch_size)
        
        {:ok, %{
          "batch" => next_batch,
          "loop_state" => Map.put(loop_state, "processed_results", updated_results),
          "batch_index" => run_index,
          "items_count" => items_count,
          "total_batches" => total_batches,
          "processed_count" => processed_count + next_batch_size,
          "has_more_batches" => remaining_count > batch_size
        }, "batch"}
    end
  end

  # Helper functions
  
  defp get_items_from_port(input) do
    # ✅ Get items from "items" input port (first iteration only)
    case Map.get(input, "items") do
      nil -> []
      items when is_list(items) -> items
      items -> [items]  # Wrap single item in list
    end
  end
  
  defp get_batch_results_from_port(input) do
    # ✅ Get batch results from "batch_results" input port (loop-back iterations)
    case Map.get(input, "batch_results") do
      nil -> []
      results when is_list(results) -> results
      result -> [result]  # Wrap single result in list
    end
  end
  
  defp get_batch_size(input) do
    Map.get(input, "batch_size", 10)
  end
end
```

### Configuration Schema

```elixir
# Node parameters
%{
  "items_expression" => "$input.users",  # Source array expression
  "batch_size" => 25,                    # Items per batch (default: 10)
  "collect_results" => true              # Whether to collect batch results (default: true)
}
```

### Workflow Pattern

```elixir
# Updated pattern with separate input ports:
A: Data Source (e.g., API call returning 1000 users) →
B: For Each Batch (batch_size: 50) →
   - batch → C: Process Batch (e.g., send notifications) →
   - C.main → B.batch_results (loop-back connection)
   - B → done → D: Final Summary

# Connection structure:
# A.main → B.items (initial data - first iteration only)
# C.main → B.batch_results (loop-back results - subsequent iterations)
```

### Nested Loop Challenge and Solution

#### The Problem

When implementing nested loops (e.g., processing departments → users within each department), a critical issue arises:

```elixir
# Nested loop scenario:
A: Get Departments → [Dept1, Dept2, Dept3] →
B: Outer For_Each (departments) →
   - batch → C: Get Users for Department →  
   - C → D: Inner For_Each (users) →
     - batch → E: Process Users →
     - E connects back to D (inner loop)
   - D → done → back to B (outer loop)

# Problem: When processing Dept2
# D accesses $nodes.inner_loop_node and finds loop state from Dept1 processing!
# This causes D to continue Dept1's loop instead of starting fresh for Dept2
```

#### The Solution: `$execution.is_loopback` Flag

We introduce an explicit `is_loopback` boolean flag in the execution context that tells nodes whether they should:
- **`false`**: Initialize fresh loop state (first execution or new dataset)
- **`true`**: Continue existing loop state (loop-back execution)

```elixir
# How GraphExecutor sets the flag:
defp detect_loopback_execution(node, execution) do
  # Check if this node has been executed before in current execution context
  node_executions = Map.get(execution.node_executions, node.key, [])
  length(node_executions) > 0
end

# Updated execution context:
"$execution" => %{
  "current_node_key" => node_execution.node_key,
  "run_index" => node_execution.run_index,
  "execution_index" => node_execution.execution_index,
  "is_loopback" => is_loopback,  # ✅ NEW FLAG
  # ... other fields
}
```

#### Nested Loop Flow with `is_loopback`

```elixir
# First outer loop iteration (Dept1):
B: (is_loopback: false) → processes [Dept1] →
C: → D: (is_loopback: false) → initializes fresh loop for Dept1 users →
D: processes [User1, User2] → E → back to D: (is_loopback: true) →
D: continues Dept1 loop, processes [User3, User4] → done → back to B

# Second outer loop iteration (Dept2):  
B: (is_loopback: true) → processes [Dept2] →
C: → D: (is_loopback: false) ✅ → initializes fresh loop for Dept2 users
D: processes [User5, User6] correctly, ignoring stale Dept1 state
```

#### Benefits

1. **Explicit Control**: No guessing about execution context
2. **Nested Loop Support**: Inner loops properly reset for each outer iteration
3. **Future-Proof**: Handles any complex loop scenario
4. **Simple Logic**: Clear boolean flag eliminates ambiguity

### Expression System Integration

Loop variables accessible via expressions:

```elixir
# Current batch information
"$nodes.batch_processor.batch_index"      # 0, 1, 2, 3...
"$nodes.batch_processor.items_count"      # Total items (computed once) 
"$nodes.batch_processor.total_batches"    # Total batches (computed once)
"$nodes.batch_processor.processed_count"  # Items processed so far
"$nodes.batch_processor.has_more_batches" # Boolean flag

# From execution context
"$execution.run_index"                    # Same as batch_index
"$execution.is_loopback"                  # Boolean: true for loop-back, false for fresh start

# Conditional logic examples  
"$nodes.batch_processor.batch_index < 5"  # First 5 batches only
"$nodes.batch_processor.processed_count / $nodes.batch_processor.items_count * 100"  # Progress %
"$execution.is_loopback ? 'Continuing' : 'Starting'"  # Dynamic behavior based on loop state
```

### Error Handling Strategy

```elixir
defp validate_batch_configuration(input) do
  with {:ok, items} <- extract_and_validate_items(input),
       {:ok, batch_size} <- validate_batch_size(input),
       :ok <- validate_memory_limits(items, batch_size) do
    {:ok, items, batch_size}
  else
    {:error, reason} -> {:error, reason, "error"}
  end
end

defp validate_batch_size(input) do
  batch_size = get_batch_size(input)
  
  cond do
    batch_size <= 0 -> {:error, "Batch size must be positive"}
    batch_size > 1000 -> {:error, "Batch size too large (max: 1000)"}
    true -> {:ok, batch_size}
  end
end

defp validate_memory_limits(items, batch_size) do
  items_count = length(items)
  
  cond do
    items_count > 100_000 -> {:error, "Too many items (max: 100,000)"}
    batch_size * 10 > items_count -> {:warn, "Batch size larger than recommended"}
    true -> :ok
  end
end
```

## Implementation Details

### Performance Optimizations

1. **Single Length Calculation**: `length(items)` computed once in first iteration
2. **Stored Computed Values**: All expensive calculations cached in loop state
3. **Efficient Slicing**: Use `Enum.drop/2` + `Enum.take/2` instead of `Enum.slice/3`
4. **Arithmetic Operations**: Use math instead of list operations where possible

### Memory Management

```elixir
# For very large datasets, consider streaming approach:
defp process_large_dataset(items, batch_size) when length(items) > 10_000 do
  # Convert to stream for memory efficiency
  items
  |> Stream.chunk_every(batch_size)
  |> Stream.with_index()
  |> Enum.reduce_while({:cont, []}, fn {batch, index}, {_status, results} ->
    case process_batch(batch, index) do
      {:ok, result} -> {:cont, {_status, [result | results]}}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end)
end
```

### Integration with Existing Features

#### Middleware Integration
```elixir
# Loop-specific middleware events
defmodule Prana.LoopMiddleware do
  @behaviour Prana.Behaviour.Middleware
  
  def call(:node_completed, %{node_type: "loop.for_each_batch"} = data, next) do
    # Log batch completion
    batch_index = get_in(data.output_data, ["batch_index"])
    total_batches = get_in(data.output_data, ["total_batches"])
    
    Logger.info("Batch #{batch_index + 1}/#{total_batches} completed")
    
    next.(data)
  end
  
  def call(event, data, next), do: next.(data)
end
```

#### Sub-workflow Integration
```elixir
# For each batch can trigger sub-workflows
A: For Each Batch →
   - batch → B: Execute Sub-workflow →
   - B → done → back to A
```

## Consequences

### Positive

1. **Leverage Existing Infrastructure**: Uses proven `run_index` and node output systems
2. **Performance Optimized**: Single calculation of expensive operations
3. **Expression Rich**: Full integration with Prana's expression system
4. **Memory Efficient**: Configurable batch sizes prevent memory issues
5. **Progress Transparent**: Clear visibility into processing status
6. **n8n Compatible**: Familiar pattern for users migrating from n8n

### Negative

1. **Loop State Complexity**: Managing state across iterations adds complexity
2. **Expression Dependencies**: Relies on node output accessibility via expressions
3. **Memory Overhead**: Storing entire item arrays in loop state
4. **Limited to Arrays**: Only supports array/list iteration patterns

### Risks

1. **Large Dataset Memory**: Very large arrays could consume significant memory
2. **Expression Evaluation**: Complex item expressions could impact performance
3. **State Corruption**: Malformed loop state could break iteration
4. **Infinite Loops**: Missing termination conditions could cause endless execution

## Risk Mitigation

### Memory Management
- **Array Size Limits**: Maximum 100,000 items per batch operation
- **Batch Size Validation**: Reasonable batch size limits (1-1000)
- **Streaming Option**: For very large datasets, consider streaming approach

### Safety Mechanisms
- **Iteration Limits**: Maximum iteration safety check (leverages existing loop safety)
- **Timeout Protection**: Batch processing timeout limits
- **State Validation**: Validate loop state structure before processing

### Error Recovery
- **Graceful Degradation**: Continue processing even if some batches fail
- **Partial Results**: Return processed results even on partial failure
- **State Reconstruction**: Ability to rebuild state from node executions

## Alternatives Considered

### 1. Dedicated Loop State Storage
**Rejected**: Would require new infrastructure when node outputs work perfectly

### 2. Single-Shot Processing
**Rejected**: Doesn't provide batch processing benefits for large datasets

### 3. External Iterator Pattern
**Rejected**: Would break Prana's node-based execution model

## Testing Strategy

### Unit Tests
```elixir
describe "for_each_batch action" do
  test "processes small arrays in single batch" do
    input = %{"$input" => %{"main" => [1, 2, 3]}, "batch_size" => 10}
    assert {:ok, output, "batch"} = Loop.for_each_batch(input)
    assert output["batch"] == [1, 2, 3]
    assert output["has_more_batches"] == false
  end

  test "processes large arrays in multiple batches" do
    items = 1..100 |> Enum.to_list()
    input = %{"$input" => %{"main" => items}, "batch_size" => 25}
    
    # First batch
    assert {:ok, output1, "batch"} = Loop.for_each_batch(input)
    assert length(output1["batch"]) == 25
    assert output1["total_batches"] == 4
    assert output1["has_more_batches"] == true
    
    # Simulate loop-back with batch results
    loop_back_input = build_loop_back_input(output1, processed_results)
    assert {:ok, output2, "batch"} = Loop.for_each_batch(loop_back_input)
    assert output2["batch_index"] == 1
  end

  test "calculates expensive operations once" do
    large_items = 1..10_000 |> Enum.to_list()
    input = %{"$input" => %{"main" => large_items}, "batch_size" => 100}
    
    # Mock length calculation to verify it's called once
    with_mock(Enum, [:passthrough], [length: fn(_) -> 10_000 end]) do
      # Process multiple iterations
      process_full_loop(input, 100)  # 100 batches
      
      # Verify length was called only once (in first iteration)
      assert called(Enum.length(:_), 1)
    end
  end
end
```

### Integration Tests
```elixir
test "end-to-end batch processing workflow" do
  workflow = build_batch_processing_workflow()
  {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "start")
  
  context = %{variables: %{}}
  {:ok, execution, _} = GraphExecutor.execute_workflow(execution_graph, context)
  
  # Verify all batches were processed
  loop_executions = Map.get(execution.node_executions, "batch_processor", [])
  assert length(loop_executions) == expected_batch_count
  
  # Verify final results
  final_output = get_final_node_output(execution, "summary")
  assert final_output["total_processed"] == total_items_count
end

test "nested loops with proper reset behavior" do
  # Build workflow: Departments → Users processing
  workflow = build_nested_loop_workflow()
  {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "start")
  
  context = %{variables: %{}}
  {:ok, execution, _} = GraphExecutor.execute_workflow(execution_graph, context)
  
  # Verify outer loop processed all departments
  outer_loop_executions = Map.get(execution.node_executions, "dept_loop", [])
  assert length(outer_loop_executions) == 3  # 3 departments
  
  # Verify inner loop reset for each department
  inner_loop_executions = Map.get(execution.node_executions, "user_loop", [])
  
  # Should have multiple executions but with proper resets
  # First execution for each department should have is_loopback: false
  fresh_starts = Enum.filter(inner_loop_executions, fn exec ->
    exec.context_data["is_loopback"] == false
  end)
  assert length(fresh_starts) == 3  # One fresh start per department
  
  # Verify total users processed across all departments
  final_summary = get_final_node_output(execution, "summary")
  assert final_summary["total_users_processed"] > 0
end
```

## Implementation Plan

### Phase 1: Core Implementation (Week 1)
- [ ] Add `is_loopback` flag to `$execution` context in NodeExecutor
- [ ] Update GraphExecutor to detect loop-back executions
- [ ] Implement `for_each_batch` action in `Prana.Integrations.Loop`
- [ ] Add configuration validation and error handling
- [ ] Implement optimized state management with single length calculation
- [ ] Add comprehensive unit tests

### Phase 2: Integration (Week 2)  
- [ ] Test with existing workflow execution engine
- [ ] Verify expression system integration
- [ ] Add loop-back connection testing
- [ ] Performance testing with large datasets

### Phase 3: Safety & Polish (Week 3)
- [ ] Implement memory limits and safety checks
- [ ] Add middleware integration for progress tracking
- [ ] Comprehensive integration testing
- [ ] Documentation and examples

## Success Criteria

1. **Functional**: Process arrays in configurable batches with automatic iteration
2. **Performant**: Single calculation of expensive operations, efficient memory usage
3. **Integrated**: Full expression system integration with loop variable access
4. **Nested Loop Support**: Proper reset behavior for complex nested loop scenarios
5. **Safe**: Memory limits, iteration limits, and error handling
6. **Compatible**: Works with existing Prana features (middleware, sub-workflows, etc.)
7. **Tested**: Comprehensive test coverage for all scenarios including nested loops

## References

- [n8n Split in Batches Documentation](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.splitinbatches/)
- [ADR-006: Loop Integration Design](./006-loop-integration-design.md)
- [Prana Expression Engine](../../lib/prana/expression_engine.ex)
- [Loop Implementation Plan](../loop_implementation_plan.md)

---

**Status**: 📋 Proposed  
**Next Steps**: Begin Phase 1 implementation with `Prana.Integrations.Loop` module