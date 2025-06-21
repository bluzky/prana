# ExecutionPlanner

The ExecutionPlanner transforms raw workflow definitions into optimized execution plans that the GraphExecutor can efficiently execute.

## Purpose

ExecutionPlanner serves as the **preparation phase** before workflow execution, performing:
- Trigger node selection and validation
- Graph reachability analysis and pruning  
- Dependency graph construction
- Performance optimization with pre-built lookup structures

## Public API

### `plan_execution/2`

Creates an optimized execution plan from a workflow definition.

```elixir
@spec plan_execution(Workflow.t(), String.t() | nil) :: {:ok, ExecutionPlan.t()} | {:error, term()}
def plan_execution(workflow, trigger_node_id \\ nil)
```

**Parameters:**
- `workflow` - Complete workflow definition with nodes and connections
- `trigger_node_id` - Optional specific trigger node ID to use as entry point

**Returns:**
- `{:ok, ExecutionPlan.t()}` - Optimized execution plan ready for GraphExecutor
- `{:error, reason}` - Planning failed with specific error

**Example:**
```elixir
# Plan execution with auto-detected trigger
{:ok, plan} = ExecutionPlanner.plan_execution(workflow)

# Plan execution with specific trigger
{:ok, plan} = ExecutionPlanner.plan_execution(workflow, "webhook_trigger")

# Handle planning errors
case ExecutionPlanner.plan_execution(workflow) do
  {:ok, plan} -> GraphExecutor.execute_workflow_loop(plan, context)
  {:error, :no_trigger_nodes} -> {:error, "Workflow has no trigger nodes"}
  {:error, {:multiple_triggers_found, names}} -> {:error, "Multiple triggers: #{inspect(names)}"}
end
```

### `find_ready_nodes/4`

Finds nodes that are ready for execution based on dependency satisfaction.

```elixir
@spec find_ready_nodes(ExecutionPlan.t(), MapSet.t(), MapSet.t(), MapSet.t()) :: [Node.t()]
def find_ready_nodes(plan, completed_nodes, failed_nodes, pending_nodes)
```

**Parameters:**
- `plan` - Execution plan created by `plan_execution/2`
- `completed_nodes` - MapSet of node IDs that have completed successfully
- `failed_nodes` - MapSet of node IDs that have failed execution
- `pending_nodes` - MapSet of node IDs currently being executed

**Returns:**
- List of Node structs that are ready for execution

**Example:**
```elixir
# Find initial ready nodes (usually just trigger)
ready_nodes = ExecutionPlanner.find_ready_nodes(
  plan, 
  MapSet.new(),      # No completed nodes yet
  MapSet.new(),      # No failed nodes yet  
  MapSet.new()       # No pending nodes yet
)
# => [trigger_node]

# Find next ready nodes after trigger completes
completed = MapSet.new(["trigger_id"])
ready_nodes = ExecutionPlanner.find_ready_nodes(plan, completed, MapSet.new(), MapSet.new())
# => [node1, node2]  # Nodes that depend only on trigger
```

## ExecutionPlan Structure

The ExecutionPlan contains optimized data structures for efficient execution:

```elixir
%ExecutionPlan{
  workflow: pruned_workflow,           # Only reachable nodes/connections
  trigger_node: trigger_node,          # Starting point for execution
  dependency_graph: dependency_map,    # node_id -> [prerequisite_node_ids]
  connection_map: connection_lookup,   # {node_id, port} -> [connections]
  node_map: node_lookup,              # node_id -> node_struct
  total_nodes: node_count             # For completion tracking
}
```

**Key Optimizations:**
- **Pruned workflow** - Removes unreachable nodes for faster execution
- **O(1) lookups** - Pre-built maps eliminate runtime searches
- **Dependency analysis** - Enables parallel execution planning

## Planning Process

### 1. Trigger Selection
- **Single trigger** - Use as entry point
- **Multiple triggers** - Require explicit specification
- **No triggers** - Return error

### 2. Graph Traversal
- Use breadth-first search from trigger node
- Identify all reachable nodes
- Mark unreachable nodes for removal

### 3. Workflow Pruning
- Keep only reachable nodes
- Filter connections between reachable nodes
- Reduce memory and execution overhead

### 4. Optimization
- Build dependency graph for execution ordering
- Create connection map for O(1) output routing
- Create node map for O(1) node lookup

## Error Handling

### Common Errors

**No Trigger Nodes:**
```elixir
{:error, :no_trigger_nodes}
```
Workflow has no nodes of type `:trigger`.

**Multiple Triggers Without Specification:**
```elixir
{:error, {:multiple_triggers_found, ["trigger1", "trigger2"]}}
```
Workflow has multiple triggers but no specific trigger_node_id provided.

**Invalid Trigger Node:**
```elixir
{:error, {:trigger_node_not_found, "invalid_id"}}
{:error, {:node_not_trigger, "node_id", :action}}
```
Specified trigger node doesn't exist or isn't a trigger type.

## Usage Patterns

### GraphExecutor Integration
```elixir
# Planning phase
{:ok, plan} = ExecutionPlanner.plan_execution(workflow, trigger_node_id)

# Execution phase  
{:ok, result} = GraphExecutor.execute_workflow_loop(plan, context)
```

### Ready Node Detection Loop
```elixir
defp execution_loop(plan, context) do
  ready_nodes = ExecutionPlanner.find_ready_nodes(
    plan,
    context.completed_nodes,
    context.failed_nodes, 
    context.pending_nodes
  )
  
  case ready_nodes do
    [] -> check_completion(plan, context)
    nodes -> execute_and_continue(nodes, plan, context)
  end
end
```

### Plan Caching
```elixir
def get_execution_plan(workflow_id) do
  case Cache.get(workflow_id) do
    nil ->
      workflow = load_workflow(workflow_id)
      {:ok, plan} = ExecutionPlanner.plan_execution(workflow)
      Cache.put(workflow_id, plan)
      plan
      
    cached_plan ->
      cached_plan
  end
end
```

## Performance Characteristics

### Time Complexity
- **Graph traversal**: O(V + E) where V = nodes, E = connections
- **Dependency building**: O(E) where E = connections
- **Ready node detection**: O(N) where N = nodes in workflow

### Space Complexity
- **Memory usage**: O(R) where R = reachable nodes (after pruning)
- **Lookup structures**: O(E + N) for connection and node maps

### Optimization Benefits
- **O(1) connection lookup** vs O(E) linear search
- **O(1) node lookup** vs O(N) linear search
- **Reduced execution overhead** through graph pruning

## Best Practices

### 1. Plan Once, Execute Many
```elixir
# Good: Plan once, cache for reuse
{:ok, plan} = ExecutionPlanner.plan_execution(workflow)
Cache.store(workflow_id, plan)

# Bad: Planning on every execution
def execute_workflow(workflow) do
  {:ok, plan} = ExecutionPlanner.plan_execution(workflow)  # Expensive!
  GraphExecutor.execute_workflow_loop(plan, context)
end
```

### 2. Handle Planning Errors
```elixir
# Always handle planning errors gracefully
case ExecutionPlanner.plan_execution(workflow, trigger_id) do
  {:ok, plan} -> 
    execute_workflow(plan)
    
  {:error, reason} ->
    Logger.error("Planning failed: #{inspect(reason)}")
    {:error, {:planning_failed, reason}}
end
```

### 3. Use Specific Triggers
```elixir
# Good: Explicit trigger selection for multi-trigger workflows
ExecutionPlanner.plan_execution(workflow, "api_webhook")

# Bad: Ambiguous trigger selection
ExecutionPlanner.plan_execution(workflow)  # Error if multiple triggers
```

## Integration Points

### With GraphExecutor
- **Planning**: GraphExecutor calls `plan_execution/2` to prepare execution
- **Ready Detection**: GraphExecutor calls `find_ready_nodes/4` during execution loop
- **Optimization**: GraphExecutor uses ExecutionPlan's lookup structures for performance

### With Workflow Management
- **Validation**: Planning validates workflow structure and connectivity
- **Optimization**: Planning identifies unreachable nodes for workflow optimization
- **Analysis**: Planning provides dependency analysis for workflow understanding

## Limitations

### Current Constraints
- **Single trigger execution** - Each execution uses one trigger node
- **Static planning** - Plan doesn't adapt during execution
- **No dynamic dependencies** - Dependencies fixed at planning time

### Future Enhancements
- **Multi-trigger support** - Concurrent trigger execution
- **Dynamic replanning** - Adapt plan based on runtime conditions
- **Advanced optimizations** - Further performance improvements

## See Also

- [GraphExecutor Documentation](graph_executor.md) - Execution engine that uses ExecutionPlan
- [Workflow Structure](workflow.md) - Input workflow definition format
- [ExecutionPlan Reference](execution_plan.md) - Detailed ExecutionPlan structure
