# ADR-006: Loop Integration Design

**Date**: July 2025
**Status**: Proposed
**Deciders**: Prana Core Team

## Context

Prana workflow automation platform needs loop capabilities to handle iterative processing patterns common in workflow automation:

1. **Simple Conditional Loops**: While/do-while patterns for retry logic, polling, and condition-based iteration
2. **Batch Processing Loops**: Processing large datasets in manageable chunks with result collection
3. **Integration with Existing Architecture**: Loops must work seamlessly with Prana's node-based, port-driven execution model

Research of n8n's loop implementation revealed two primary loop patterns:
- **Automatic iteration**: Built-in node behavior for processing arrays
- **Loop Over Items**: Explicit batch processing with result collection
- **Manual loops**: Using conditional logic to create while/do-while patterns

## Decision

We will implement **two distinct loop types** that align with Prana's architectural principles:

### 1. Simple Loop (Condition-Based)
- **Purpose**: Enable while/do-while patterns using existing conditional logic
- **Implementation**: Leverage existing `Logic` integration (IF/ELSE conditions) with port-based routing
- **Pattern**: Node connections create loop-back paths based on conditional outcomes
- **No new integration needed**: Uses existing `Prana.Integrations.Logic` for condition evaluation

### 2. Loop Over Items (Batch Processing)
- **Purpose**: Process arrays in configurable batches with automatic result collection
- **Implementation**: New `Prana.Integrations.Loop` with `for_each_batch` action
- **Pattern**: Emits batches to connected nodes, collects results, concatenates final output

## Architecture Design

### Simple Loop Pattern
```elixir
# Workflow structure:
A: Initialize state → 
B: Process step → 
C: Logic IF (condition: "$variables.counter < 10") → 
   - true → D: Update state → back to B (loop)
   - false → E: Complete (exit)
```

**Key Features**:
- Uses existing `Prana.Integrations.Logic` for condition evaluation
- Relies on connection routing for loop behavior
- No additional complexity in core execution engine
- Natural integration with existing conditional branching

### Loop Over Items Design
```elixir
# New Loop Integration
%Integration{
  name: "loop",
  display_name: "Loop",
  description: "Batch processing and result collection",
  actions: %{
    "for_each_batch" => %Action{
      name: "for_each_batch",
      display_name: "Loop Over Items",
      description: "Process array items in batches with result collection",
      input_ports: ["input"],  # Single input port for both initial and loop-back
      output_ports: ["batch", "done", "error"],
      default_success_port: "batch"
    }
  }
}
```

### Node Execution Pattern
The forEach loop leverages Prana's general node execution pattern:

**Port Satisfaction Rule**:
- A node executes when **all required input ports are satisfied**
- For a port with **multiple input sources**: the port is satisfied when **any one** of those sources provides input
- The node doesn't wait for ALL sources to that port - just the first one

**forEach Loop Execution Flow**:
```elixir
# Workflow structure:
Initial Node → 
              → Loop Node (input port) → batch → Process → 
Loop-back ────┘                                           │
                                                          │
Loop Node ← done ← Final Processing ← ────────────────────┘
```

**Execution Scenarios**:
1. **First Execution**: Loop node receives input from Initial Node
   - Initialize loop state
   - Process items, emit first batch
   - Store loop state for subsequent executions

2. **Loop Iterations**: Loop node receives input from Process node (loop-back)
   - Use existing loop state
   - Process batch results
   - Update loop state
   - Emit next batch OR final done result

### Configuration Schema
```elixir
# Simplified configuration
%{
  "items_expression" => "$input",     # Default to input, can be "$input.users"
  "batch_size" => 10                  # Only required config parameter
}
```

### Execution Flow
1. **Initialization**: Parse `items_expression`, calculate total batches
2. **Batch Emission**: Emit batch through `batch` port to connected nodes
3. **Result Collection**: Receive processed results via `batch_result` input port
4. **Iteration**: Continue until all batches processed
5. **Completion**: Concatenate all results, emit through `done` port

## Implementation Details

### Loop Over Items State Management
```elixir
# Internal loop state
%{
  items: [...],              # Original items array
  current_batch: 0,          # Current batch index  
  total_batches: 10,         # Total number of batches
  processed_results: [],     # Collected results from each batch
  is_completed: false        # Completion flag
}
```

### Loop Context Variables
Loop context is stored as node attributes, accessible via the node reference system:

```elixir
# Loop context stored in node attributes
%NodeExecution{
  node_id: "loop_node_123",
  output: %{...},                    # Node output data
  context: %{                        # Loop context data
    "batch_size" => 10,
    "has_more_item" => true,
    "index" => 2
  }
}
```

**Expression System Refactor**:
To support extensible node attributes, the expression system will be refactored:

```elixir
# Current pattern (will be deprecated)
"$node.api_call.user_id"              # Direct output access

# New pattern (after refactor)
"$node.api_call.output.user_id"       # Structured output access
"$node.loop_node.context.batch_size"  # Loop context access
"$node.loop_node.context.has_more_item"
"$node.loop_node.context.index"
```

**Benefits of Refactored Approach**:
- **Extensible**: Can add more node attributes (status, metadata, etc.)
- **Nested Loop Support**: Each loop node has its own context
- **Consistent**: Structured access pattern for all node data
- **Clear Separation**: Output data vs. context data vs. other attributes

### Result Collection Strategy
- **Single Strategy**: Concatenate all batch results into flat array
- **Implementation**: `List.flatten([batch1_results, batch2_results, ...])`
- **Rationale**: Keeps implementation simple, covers most use cases

### Error Handling
- **Batch Processing Errors**: Emit through `error` port with batch context
- **Configuration Errors**: Invalid expressions or batch sizes → `error` port
- **Array Limits**: Built-in 100-item limit prevents excessive processing

## Workflow Examples

### Simple Loop Example
```elixir
# Retry API call until success or max attempts
A: Set retry_count (0) → 
B: HTTP Request → 
C: Logic IF (condition: "$input.success == false && $variables.retry_count < 3") → 
   - true → D: Increment retry_count → back to B
   - false → E: Complete
```

### Loop Over Items Example  
```elixir
# Process 100 users in batches of 10
A: Get users (100 items) → 
B: Loop Over Items (batch_size: 10) → 
   - batch → C: Send notifications (can access $node.B.context.batch_size) → 
   - C connects back to B (input port)
   - B → done → D: Summary report
```

### Nested Loop Example
```elixir
# Process departments, then users within each department
A: Get departments → 
B: Loop Over Departments (batch_size: 5) → 
   - batch → C: Get users for department → 
   - C → D: Loop Over Users (batch_size: 10) → 
     - batch → E: Process user (can access both $node.B.context.index and $node.D.context.index) → 
     - E connects back to D
   - D → done → F: Department summary → 
   - F connects back to B
   - B → done → G: Final report
```

## Integration with Existing Features

### Expression Engine Integration
- Loop variables accessible via expressions: `$node.loop_node.context.batch_size`, `$node.loop_node.context.has_more_item`, `$node.loop_node.context.index`
- Dynamic configuration: `"batch_size": "$input.batch_size"`
- **Breaking Change**: Existing expressions using `$node.{node_id}.field` must be updated to `$node.{node_id}.output.field`

### Middleware Integration
- Loop lifecycle events: `:loop_started`, `:batch_processed`, `:loop_completed`
- Progress tracking and monitoring capabilities

### Sub-workflow Integration
- Loop nodes work within sub-workflows
- Support for suspension/resumption during batch processing

## Consequences

### Positive
- **Architectural Alignment**: Fits naturally with Prana's node-based execution model
- **Simplicity**: Two clear loop types cover most use cases
- **Reuse**: Simple loops leverage existing Logic integration
- **Performance**: Batch processing with built-in limits prevents resource exhaustion
- **Flexibility**: Expression-based configuration enables dynamic loop behavior

### Negative
- **Breaking Change**: Expression system refactor requires updating all existing expressions
- **Limited Loop Types**: Only supports two specific patterns
- **Manual Wiring**: Simple loops require manual connection setup
- **Single Result Strategy**: Only concatenation supported initially

### Risks
- **Infinite Loops**: Simple loops need careful condition design
- **Memory Usage**: Large batch processing may consume significant memory
- **Complexity**: Loop-back connections may confuse workflow builders

## Alternatives Considered

### 1. Complex Loop Integration
**Rejected**: Multiple loop types (while, do-while, for, foreach) would add unnecessary complexity

### 2. Automatic Loop Detection
**Rejected**: Automatic detection of loop patterns would require complex graph analysis

### 3. Single Loop Type
**Rejected**: Wouldn't cover both conditional and batch processing patterns effectively

## Acceptance Criteria

### Expression System Refactor
- [ ] Expression engine updated to support `$node.{node_id}.output.field` syntax
- [ ] Backwards compatibility maintained during transition period
- [ ] All existing expressions updated to new format
- [ ] Node context attributes accessible via `$node.{node_id}.context.field`

### Loop Implementation
- [ ] `Prana.Integrations.Loop` module implements `for_each_batch` action
- [ ] Loop action processes arrays in configurable batches
- [ ] Results are collected and concatenated correctly
- [ ] Loop state management works with suspension/resumption
- [ ] Loop context stored in node attributes (batch_size, has_more_item, index)
- [ ] Nested loops supported with individual node contexts
- [ ] Error handling covers configuration and processing errors
- [ ] Middleware events fire for loop lifecycle
- [ ] Comprehensive test coverage for all loop scenarios
- [ ] Documentation and examples provided

## References

- [n8n Loop Documentation](https://docs.n8n.io/flow-logic/looping/)
- [Logic Integration](../integrations/logic.md)
- [Expression Engine](../../lib/prana/expression_engine.ex)
- [Graph Execution Patterns](../graph_execution%20pattern.md)

---

**Status**: 📋 Proposed - Ready for implementation
**Next Steps**: Implement `Prana.Integrations.Loop` module and comprehensive tests