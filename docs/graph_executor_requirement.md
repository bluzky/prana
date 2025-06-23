# Prana GraphExecutor - Requirements Document

**Version**: 1.0
**Date**: June 23, 2025
**Status**: Phase 1 Complete, Phase 2-4 Planned

## 1. Overview

The **GraphExecutor** is the core workflow orchestration engine in the Prana automation platform. It executes pre-compiled workflow graphs by coordinating node execution, managing data flow between nodes, and handling workflow lifecycle events.

### 1.1 Purpose

- **Workflow Orchestration**: Execute workflows based on dependency graphs with parallel node coordination
- **Data Flow Management**: Route data between nodes through explicit port-based connections
- **Sub-workflow Support**: Handle nested workflow execution in multiple modes (sync, async, fire-and-forget)
- **Event Integration**: Emit lifecycle events for application integration via middleware
- **Error Handling**: Provide comprehensive error management and graceful failure handling

### 1.2 Key Principles

- **Separation of Concerns**: GraphExecutor handles orchestration; NodeExecutor handles individual nodes
- **Port-based Architecture**: Explicit data routing through named input/output ports
- **Dependency-driven Execution**: Nodes execute when their dependencies are satisfied
- **Parallel Execution**: Independent nodes execute concurrently using Elixir Tasks
- **Context Management**: Shared execution state for expression evaluation and data access

## 2. Phase 1 Requirements (✅ COMPLETE)

### 2.1 Scope: Core Execution (Sync/Fire-and-Forget Only)

**Focus**: Basic workflow orchestration without async suspension/resume complexity

### 2.2 Primary API

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

### 2.3 Core Functionality Implemented

#### 2.3.1 Graph Execution Orchestration
- ✅ Accept pre-compiled `ExecutionGraph` from `WorkflowCompiler`
- ✅ Execute nodes based on dependency order from ExecutionGraph
- ✅ Track execution progress in `Execution` struct
- ✅ Coordinate parallel execution of independent nodes using Tasks
- ✅ Detect workflow completion (no more ready nodes)

#### 2.3.2 Port-based Data Routing
- ✅ Route output from completed nodes to dependent nodes based on `output_port`
- ✅ Use `ExecutionGraph.workflow.connections` to determine data flow paths
- ✅ Prepare input for target nodes using `ExpressionEngine.process_map/2`
- ✅ Handle failed nodes (nodes with `output_port = nil`) - no data routing

#### 2.3.3 Context Management
- ✅ Maintain shared execution context across workflow execution
- ✅ Store node results under node `custom_id` for expression access (`$nodes.node_id.output`)
- ✅ Update context as nodes complete with their output data
- ✅ Support flexible context structure with input, variables, metadata, and nodes

#### 2.3.4 Node Execution Integration
- ✅ Use `NodeExecutor.execute_node/3` for individual node execution
- ✅ Handle node execution results and update execution state
- ✅ Track node executions in `Execution.node_executions`
- ✅ Convert simple map contexts to ExecutionContext structs for NodeExecutor

#### 2.3.5 Sub-workflow Support (Sync & Fire-and-Forget)
```elixir
# Sync mode: Execute sub-workflow and wait for completion
{:ok, child_result} = execute_sub_workflow_sync(child_graph, input_data, context)
# Merge child_result into parent context, continue execution

# Fire-and-forget mode: Trigger sub-workflow and continue immediately
:ok = execute_sub_workflow_fire_and_forget(child_graph, input_data, context)
# Parent continues without waiting
```

#### 2.3.6 Sub-workflow Loading via Callback
- ✅ Use `context.workflow_loader` callback to load sub-workflow ExecutionGraphs
- ✅ Handle loading errors gracefully
- ✅ Support application caching/precompilation strategies

#### 2.3.7 Middleware Event Emission
```elixir
# Emit lifecycle events during execution
Middleware.call(:execution_started, %{execution: execution})
Middleware.call(:node_started, %{execution: execution, node: node})
Middleware.call(:node_completed, %{execution: execution, node_execution: node_execution})
Middleware.call(:node_failed, %{execution: execution, node_execution: node_execution})
Middleware.call(:execution_completed, %{execution: execution})
Middleware.call(:execution_failed, %{execution: execution, reason: reason})
```

#### 2.3.8 Error Handling
- ✅ Workflow-level error management and propagation
- ✅ Sub-workflow loading error handling
- ✅ Node execution error handling (delegated to NodeExecutor)
- ✅ Graceful workflow termination on critical errors
- ✅ Task cleanup on parallel execution failures

### 2.4 Integration Points

- ✅ **Input**: `ExecutionGraph` from `WorkflowCompiler.compile/2`
- ✅ **Node Execution**: `NodeExecutor.execute_node/3`
- ✅ **Expression Evaluation**: `ExpressionEngine.process_map/2` (via NodeExecutor)
- ✅ **Events**: `Middleware.call/2` for lifecycle events
- ✅ **Sub-workflow Loading**: `context.workflow_loader.(workflow_id)`

### 2.5 Key Internal Functions Implemented

```elixir
# Main execution orchestration
execute_graph(execution_graph, input_data, context) :: {:ok, Execution.t()} | {:error, reason}

# Graph traversal and coordination
find_ready_nodes(execution_graph, completed_nodes, context) :: [Node.t()]
execute_nodes_batch(ready_nodes, execution_graph, context) :: [NodeExecution.t()]

# Data routing between nodes
route_node_output(node_execution, execution_graph, context) :: map()

# Sub-workflow execution modes
execute_sub_workflow_sync(node, context) :: {:ok, context} | {:error, reason}
execute_sub_workflow_fire_and_forget(node, context) :: {:ok, context} | {:error, reason}

# Execution state management
update_execution_progress(execution, completed_nodes) :: Execution.t()
workflow_complete?(execution, execution_graph) :: boolean()
```

### 2.6 Phase 1 Success Criteria Met

1. ✅ Execute simple workflows end-to-end successfully
2. ✅ Handle parallel node execution correctly
3. ✅ Route data between nodes via ports properly
4. ✅ Execute sync sub-workflows with result merging
5. ✅ Execute fire-and-forget sub-workflows independently
6. ✅ Emit proper middleware events for application integration
7. ✅ Handle errors gracefully without crashing
8. ✅ Support workflow loader callback pattern

## 3. Phase 2 Requirements (📋 PLANNED)

### 3.1 Scope: Async Execution with Suspension/Resume

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

#### 4.2.1 Node-level Retry Policies
```elixir
# Retry configuration per node
retry_policy = %RetryPolicy{
  max_attempts: 3,
  backoff_strategy: :exponential,
  base_delay_ms: 1000,
  max_delay_ms: 30000,
  retry_on: [:network_error, :timeout]
}
```

#### 4.2.2 Retry Coordination
- **GraphExecutor-NodeExecutor Integration**: Coordinate retry attempts
- **Exponential Backoff**: Intelligent delay between retry attempts
- **Retry State Tracking**: Monitor retry counts and failures
- **Selective Retry**: Retry only on specific error types

#### 4.2.3 Timeout Management
- **Node-level Timeouts**: Individual node execution timeouts
- **Workflow-level Timeouts**: Overall workflow execution limits
- **Sub-workflow Timeouts**: Timeout handling for nested workflows
- **Graceful Timeout**: Clean resource cleanup on timeout

#### 4.2.4 Circuit Breaker Patterns
- **Failure Thresholds**: Automatic circuit opening on repeated failures
- **Recovery Detection**: Automatic circuit closing when service recovers
- **Fallback Strategies**: Alternative execution paths when circuits are open

#### 4.2.5 Advanced Error Handling
- **Error Classification**: Categorize errors for appropriate handling
- **Error Aggregation**: Collect and analyze error patterns
- **Graceful Degradation**: Continue execution with reduced functionality

## 5. API Specification

### 5.1 Public API Functions

```elixir
# Main execution API
@spec execute_graph(ExecutionGraph.t(), map(), map()) ::
  {:ok, Execution.t()} | {:error, any()}

# Utility functions
@spec find_ready_nodes(ExecutionGraph.t(), [NodeExecution.t()], map()) :: [Node.t()]
@spec workflow_complete?(Execution.t(), ExecutionGraph.t()) :: boolean()
@spec route_node_output(NodeExecution.t(), ExecutionGraph.t(), map()) :: map()

# Sub-workflow execution
@spec execute_sub_workflow_sync(Node.t(), map()) :: {:ok, map()} | {:error, any()}
@spec execute_sub_workflow_fire_and_forget(Node.t(), map()) :: {:ok, map()} | {:error, any()}

# State management
@spec update_execution_progress(Execution.t(), [NodeExecution.t()]) :: Execution.t()
```

### 5.2 Context Structure

```elixir
# Input context
%{
  workflow_loader: (workflow_id -> {:ok, ExecutionGraph.t()} | {:error, reason}),
  variables: %{},     # Optional workflow variables
  metadata: %{}       # Optional execution metadata
}

# Execution context (internal)
%{
  "input" => map(),      # Initial workflow input
  "variables" => map(),  # Workflow variables
  "metadata" => map(),   # Execution metadata
  "nodes" => %{          # Node execution results
    node_id => %{
      "status" => :completed | :failed,
      "error" => map() | nil,
      # ... node-specific output data
    }
  }
}
```

### 5.3 Event Specification

```elixir
# Middleware events emitted during execution
:execution_started   -> %{execution: Execution.t()}
:execution_completed -> %{execution: Execution.t()}
:execution_failed    -> %{execution: Execution.t(), reason: any()}
:node_started        -> %{node: Node.t(), node_execution: NodeExecution.t()}
:node_completed      -> %{node: Node.t(), node_execution: NodeExecution.t()}
:node_failed         -> %{node: Node.t(), node_execution: NodeExecution.t()}
```

## 6. Testing Requirements

### 6.1 Unit Testing
- ✅ **Core Functions**: Test all public API functions
- ✅ **Edge Cases**: Test error conditions and boundary cases
- ✅ **Integration**: Test integration with NodeExecutor and Middleware
- ✅ **Context Management**: Test context updates and data routing

### 6.2 Integration Testing
- **End-to-End Workflows**: Test complete workflow execution scenarios
- **Sub-workflow Testing**: Test all sub-workflow execution modes
- **Error Scenarios**: Test error handling and recovery
- **Performance Testing**: Test under load and concurrent execution

### 6.3 Property-Based Testing
- **Workflow Invariants**: Test that workflows always reach completion or error
- **Context Consistency**: Test that context updates are always consistent
- **Data Flow**: Test that data routing preserves data integrity

## 7. Implementation Notes

### 7.1 Current Implementation Status
- ✅ **Phase 1**: Complete with comprehensive test coverage
- ✅ **File Structure**: `lib/prana/execution/graph_executor.ex`
- ✅ **Test Coverage**: `test/prana/execution/graph_executor_test.exs`
- ✅ **Test Support**: `test/support/test_integration.ex`

### 7.2 Architecture Decisions
- **Simple Map Context**: Use simple maps for execution context to avoid complex struct dependencies
- **String Keys**: Use string keys consistently throughout context for expression engine compatibility
- **Task-based Parallelism**: Use Elixir Tasks for concurrent node execution
- **Middleware Integration**: Emit events for application integration without tight coupling

### 7.3 Future Considerations
- **State Persistence**: Design context structure for easy serialization in Phase 2
- **Performance Optimization**: Consider using GenStage for high-throughput scenarios
- **Distributed Execution**: Plan for distributed workflow execution across nodes

---

**Document Status**: ✅ Complete for Phase 1
**Next Review**: Before Phase 2 implementation
**Maintainer**: Prana Core Team
