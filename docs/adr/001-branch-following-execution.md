# ADR-001: Branch-Following Execution Strategy

**Status**: Accepted  
**Date**: 2025-06-26  
**Deciders**: Prana Core Team  
**Technical Story**: GraphExecutor execution model optimization  

## Context

The GraphExecutor was initially implemented with a batch-based execution model where all ready nodes were executed simultaneously in batches. This approach had several issues:

1. **Inefficient branch execution**: In workflows with multiple branches (e.g., conditional IF/ELSE, parallel processing), nodes from different branches would execute simultaneously rather than following natural execution paths.

2. **Poor resource utilization**: Batch execution could lead to resource contention when multiple nodes competed for the same resources.

3. **Suboptimal conditional branching**: Conditional workflows would execute nodes from both branches even when only one branch should be active.

4. **Debugging complexity**: Understanding execution flow was difficult when nodes executed in arbitrary batch orders.

### Example Problem

**Workflow**: `trigger → (branch_a1 → branch_a2, branch_b1 → branch_b2) → merge`

**Batch Execution (Old)**:
```
Iteration 1: [trigger]
Iteration 2: [branch_a1, branch_b1]  # Both branches start simultaneously
Iteration 3: [branch_a2, branch_b2]  # Both branches continue simultaneously  
Iteration 4: [merge]
```

**Expected Behavior**:
```
trigger → branch_a1 → branch_a2 → branch_b1 → branch_b2 → merge
(Complete one branch before starting another)
```

## Decision

We decided to implement a **branch-following execution strategy** that executes nodes one at a time, prioritizing the completion of active branches before starting new branches.

### Key Components

1. **Single-Node Execution**: Execute one node per iteration instead of batches
2. **Branch Prioritization**: Continue active execution paths before starting new ones
3. **Smart Node Selection**: Use `select_node_for_branch_following()` to choose optimal next node
4. **Immediate Output Routing**: Route node outputs immediately after execution

### Selection Algorithm

```elixir
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

## Consequences

### Positive

1. **Improved Execution Flow**: Branches execute to completion, creating more natural execution patterns
2. **Better Resource Utilization**: Reduced resource contention by avoiding simultaneous execution of competing nodes
3. **Enhanced Conditional Branching**: More predictable behavior in IF/ELSE and switch/case patterns
4. **Easier Debugging**: Clear execution order makes workflow debugging more intuitive
5. **Performance Optimization**: Combined with O(1) connection lookups, execution is both efficient and logical

### Negative

1. **Reduced Parallelism**: True parallel execution is sacrificed for deterministic behavior
2. **Potential Latency**: Sequential execution may be slower for truly independent parallel tasks
3. **Complexity**: Node selection logic adds computational overhead

### Neutral

1. **Backward Compatibility**: Existing workflows continue to work but with different execution order
2. **Test Updates**: Some tests needed updates to account for new execution patterns

## Implementation Details

### Modified Functions

1. **`find_and_execute_ready_nodes/3`**: Changed from batch to single-node execution
2. **`select_node_for_branch_following/3`**: New function for intelligent node selection  
3. **Output routing**: Moved from batch processing to immediate routing after each node

### Performance Impact

- **100-node workflow**: ~11ms execution time maintained
- **Connection lookups**: 0.179μs per lookup (O(1) performance)
- **Context updates**: 0.25μs per update (optimized)
- **Branch following overhead**: Negligible impact on overall performance

### Verification

Test results confirming correct behavior:
```
✓ Branch following detected. Execution order: 
["trigger", "branch_a1", "branch_a2", "branch_b1", "branch_b2", "merge"]
```

## Alternatives Considered

### 1. Configurable Execution Mode
**Option**: Allow switching between batch and branch-following modes
**Rejected**: Added complexity without clear benefit; branch-following is superior in most cases

### 2. Hybrid Approach  
**Option**: Use batch execution for independent nodes, branch-following for dependent nodes
**Rejected**: Complex to implement and reason about; unclear performance benefits

### 3. True Parallel Execution
**Option**: Use Elixir processes for genuine parallel execution
**Rejected**: Would break execution ordering guarantees needed for conditional workflows

## Related Decisions

- **ADR-000**: Original batch execution model (now superseded)
- **Performance Optimization Phase 3.2.5**: O(1) connection lookups that complement branch following

## Monitoring and Review

### Success Metrics
- ✅ All conditional branching tests pass (24 tests)
- ✅ Branch following behavior verified in integration tests
- ✅ Performance maintained within acceptable thresholds
- ✅ No regressions in existing functionality

### Review Criteria
- If parallel execution becomes a performance bottleneck, reconsider hybrid approach
- Monitor execution patterns in production workflows
- Evaluate need for configurable execution strategies based on user feedback

## Notes

This decision represents a shift from "parallel by default" to "sequential by design" execution. While this reduces theoretical maximum throughput, it provides:

1. **Predictable execution patterns** for conditional workflows
2. **Better resource management** for resource-constrained operations  
3. **Improved debuggability** for complex workflow analysis
4. **Foundation for advanced patterns** like diamond merging and wait coordination

The trade-off between parallelism and predictability was deemed acceptable given Prana's focus on reliable workflow automation over maximum throughput.