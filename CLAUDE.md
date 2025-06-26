# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Prana** is an Elixir workflow automation platform built around a node-based graph execution model. It orchestrates workflows consisting of nodes (triggers, actions, logic, wait, output) connected through explicit ports with conditional routing and expression-based data flow.

## Key Commands

### Development
- `mix compile` - Compile the project
- `mix test` - Run all tests
- `mix test test/path/to/specific_test.exs` - Run a specific test file
- `mix credo` - Run static code analysis
- `mix format` - Format code using built-in formatter
- `mix deps.get` - Get dependencies
- `mix deps.update --all` - Update all dependencies

### Interactive Development
- `iex -S mix` - Start interactive Elixir shell with project loaded
- `mix run` - Run the default application (currently basic)

### Testing Patterns
- Tests use ExUnit framework
- Comprehensive test coverage exists for core modules
- Test files follow `*_test.exs` naming convention
- Use `mix test --trace` for detailed test output

## Architecture Overview

### Core Design Principles
- **Type Safety**: All data uses proper Elixir structs with compile-time checking
- **Behavior-Driven**: Clean contracts for integrations and middleware
- **Node-Port Model**: Explicit data flow through named ports between nodes
- **Expression System**: Built-in path evaluation (`$input.field`, `$nodes.api.response`) for dynamic data access
- **MFA Action Pattern**: Actions defined as `{module, function, args}` tuples

### Key Components

#### Core Data Structures (`lib/prana/core/`)
- **`Prana.Workflow`**: Complete workflow with nodes and connections
- **`Prana.Node`**: Individual workflow node with type, integration, action, and configuration
- **`Prana.Connection`**: Port-based connections between nodes with conditions and data mapping
- **`Prana.NodeExecution`**: Individual node execution state tracking
- **`Prana.ExecutionContext`**: Shared execution context across workflow

#### Execution Engine
- **`Prana.NodeExecutor`** (`node_executor.ex`): ✅ **PRODUCTION READY** - Executes individual nodes with expression-based input preparation, MFA action invocation, and comprehensive error handling
- **`Prana.GraphExecutor`** (`execution/graph_executor.ex`): 🚧 **IN PROGRESS** - Orchestrates workflow execution using NodeExecutor, handles parallel execution, port-based routing, and middleware integration
- **`Prana.ExpressionEngine`** (`expression_engine.ex`): ✅ **COMPLETE** - Path-based expression evaluation for dynamic data access

#### Registry & Extension System
- **`Prana.IntegrationRegistry`** (`registry/integration_registry.ex`): GenServer managing integrations and their actions
- **`Prana.Behaviour.Integration`**: Contract for workflow integrations
- **`Prana.Behaviour.Middleware`**: Contract for workflow lifecycle event handling

#### Middleware System
- **`Prana.Middleware`** (`middleware.ex`): Pipeline execution engine for lifecycle events
- Events: `:execution_started`, `:execution_completed`, `:execution_failed`, `:node_started`, `:node_completed`, `:node_failed`

### Expression System Usage

The expression engine supports:
```elixir
# Simple field access
"$input.email"                    # Single value
"$nodes.api_call.response.user_id" # Nested access
"$variables.api_url"               # Variables

# Array access
"$input.users[0].name"             # Index access

# Wildcard extraction (returns arrays)
"$input.users.*.name"              # All names
"$input.users.*.skills.*"          # Nested wildcards

# Filtering (returns arrays)
"$input.users.{role: \"admin\"}.email"        # Simple filter
"$input.orders.{status: \"completed\", user_id: 123}" # Multiple conditions
```

### Conditional Execution Patterns

The Graph Executor now supports advanced conditional branching:

#### IF/ELSE Branching
```elixir
# Only one branch executes based on condition
A → Condition → (B OR C) → different or convergent paths
```

#### Switch/Case Routing
```elixir
# Named port routing with exclusive execution
A → Switch → (premium OR standard OR basic OR default)
```

#### Active Path Tracking
- Context tracks `active_paths` to prevent both branches from executing
- Context includes `executed_nodes` for path-aware processing downstream
- Workflows complete when no ready nodes exist (not all possible nodes)

### Detailed Implementation Status

Based on thorough examination of the docs/* files and testing, here's the accurate current implementation status:

#### ✅ VERIFIED COMPLETE - Graph Executor Phases 3.1 + 3.2

**Phase 3.1 (Core Execution)**:
- ✅ Single trigger node execution (improved from multiple entry nodes)
- ✅ Graph pruning - only reachable nodes from trigger execute
- ✅ O(1) connection map lookups for performance
- ✅ Sequential execution with fail-fast behavior
- ✅ Sync and fire-and-forget sub-workflow execution
- ✅ Comprehensive middleware event emission
- ✅ Dynamic workflow completion detection

**Phase 3.2 (Conditional Branching)** - **VERIFIED COMPLETE**:
- ✅ **24 passing conditional branching tests** (1358 lines of test code)
- ✅ **Logic integration fully implemented** (351 lines) with if_condition, switch, merge actions
- ✅ IF/ELSE branching with exclusive path execution
- ✅ Switch/Case multi-branch routing (premium, standard, basic, default ports)
- ✅ Active path tracking prevents dual branch execution
- ✅ Executed node tracking for path-aware downstream processing
- ✅ Conditional workflow completion (based on active paths, not total nodes)
- ✅ Context enhancements: `executed_nodes` and `active_paths` tracking

#### 🎯 CURRENT IMPLEMENTATION TARGET

**Phase 3.3 (Advanced Coordination)** - *Partially Complete*:
- ✅ Merge action exists in Logic integration
- ⚠️ **Needs**: Diamond pattern coordination (fork-join)
- ⚠️ **Needs**: Wait integration for async synchronization
- ⚠️ **Needs**: Wait-for-All parallel pattern support
- ⚠️ **Needs**: Timeout handling mechanisms

#### Implementation Accuracy Note
The docs show some inconsistency - `graph_execution pattern.md` section 8 shows Phase 3.2 as TODO, but section 7 and the actual implementation confirm it's complete. The **tests and code confirm Phase 3.2 is fully implemented and working**.

### Current Implementation Status

**Overall Progress**: ~85% Complete (Phase 3.1 + 3.2 Complete, 3.3 in progress)

#### ✅ COMPLETED (Phase 1 + 2)
1. **All Core Data Structures** - Comprehensive struct-based design with proper type safety
2. **Behavior Definitions** - Simplified contracts (Integration, Middleware only)
3. **Expression Engine** - Complete path-based expression evaluation with wildcards and filtering
4. **Integration Registry** - Runtime integration management with health checking
5. **Middleware System** - Event-driven lifecycle handling with 100+ test scenarios
6. **Node Executor** - **PRODUCTION READY** individual node execution with comprehensive testing
7. **Workflow Compiler** - Complete workflow compilation into optimized ExecutionGraphs

#### ✅ CURRENT STATUS (Phase 3.1 + 3.2 - COMPLETE)
1. **Graph Executor Phase 3.1** - Core Execution (Sync/Fire-and-Forget) ✅ **COMPLETE**

2. **Graph Executor Phase 3.2** - Conditional Branching ✅ **COMPLETE**

#### 🎯 CURRENT PRIORITY (Phase 3.3 - Advanced Coordination)
- **Enhanced Merge Integration**: Core merge action already exists in Logic integration, needs diamond pattern coordination
- **Wait Integration**: Async synchronization and timeout handling for Wait patterns
- **Advanced Coordination**: Complex execution patterns like Wait-for-All parallel
- **Performance Optimization**: Monitor and optimize sequential vs parallel execution patterns

#### 📋 FUTURE PHASES (Graph Executor)
- **Phase 3.4**: Telemetry and advanced tracking
- **Phase 4**: Event-driven patterns with suspension/resume
- **Phase 5**: Loop patterns and advanced coordination

#### 📋 REMAINING (Later Phases)
1. **Built-in Integrations** (Phase 4) - HTTP, Transform, Logic, Log, Wait
2. **Main API** (Phase 5) - Public interface for workflow management
3. **Development Tools** (Phase 6) - Builder, validation, testing utilities

### Key Design Decisions

1. **Struct-Only Data** - No dynamic maps, all typed structs for compile-time safety
2. **Module-Based Integrations** - Only support behavior-implementing modules, no map definitions
3. **Middleware for Application Logic** - Clean separation between library (execution) and application (persistence)
4. **Port-Based Routing** - Explicit named ports for data flow instead of implicit connections
5. **MFA Action Pattern** - Actions defined as `{module, function, args}` tuples
6. **Failed Executions Design** - Failed nodes have `output_port = nil`, error routing handled at graph level
7. **Simplified Behaviors** - Removed storage adapters, hook system; middleware provides better composability
8. **No Complex Validation** - Trust integration structs, simplified registry without normalization

### Working with the Codebase

#### Important Context for Development
- **Node Executor is production-ready** with 100+ comprehensive test scenarios
- **Workflow Compiler** handles compilation from workflows to ExecutionGraphs with optimization
- **Graph Executor Phase 3.1** (Core Execution) ✅ **COMPLETE** - sequential execution, sync/fire-and-forget modes
- **Graph Executor Phase 3.2** (Conditional Branching) ✅ **COMPLETE** - IF/ELSE, Switch patterns with path tracking
- **Current focus** is Phase 3.3 (Merge + Wait integrations for diamond/coordination patterns)
- **Major performance improvements**: Single trigger execution, graph pruning, O(1) connection lookups
- **Advanced conditional execution**: Active path tracking prevents dual branch execution

#### Adding New Features
- Follow existing struct patterns in `lib/prana/core/`
- Use behaviors for extensibility (`lib/prana/behaviours/`)
- Add comprehensive tests following existing patterns (see `node_executor_test.exs` for examples)
- Use `mix credo` to ensure code quality
- All new components should integrate with the middleware event system

#### Testing Patterns
- Expression engine: `"$input.field"`, `"$nodes.api.response"`, wildcards, filtering
- Node execution: Multiple return formats, error handling, context management
- Middleware: Event handling, pipeline execution, error resilience
- Use `mix test --trace` for detailed test output during development

#### Integration Development
```elixir
defmodule MyApp.SlackIntegration do
  @behaviour Prana.Behaviour.Integration

  def definition do
    %Prana.Integration{
      name: "slack",
      display_name: "Slack",
      actions: %{
        "send_message" => %Prana.Action{
          name: "send_message",
          module: __MODULE__,
          function: :send_message,
          input_ports: ["input"],
          output_ports: ["success", "error"]
        }
      }
    }
  end

  def send_message(input) do
    {:ok, %{message_id: "123"}}
  end
end
```

#### Middleware Development
```elixir
defmodule MyApp.DatabaseMiddleware do
  @behaviour Prana.Behaviour.Middleware

  def call(event, data, next) do
    # Handle event (e.g., persist to database)
    result = next.(data)
    # Post-process if needed
    result
  end
end
```

### Dependencies

- **Elixir**: ~> 1.16
- **nested2**: Path traversal and data extraction
- **styler** (dev/test): Code formatting
- **credo** (dev/test): Static analysis

### Key Documentation References

For detailed implementation context, refer to these documents:

#### Core Requirements & Architecture
- **`library_requirements.md`** - Final simplified requirements with struct-based design principles
- **`implementation_plan.md`** - Detailed phase breakdown with current completion status
- **`IMPLEMENTATION_SUMMARY.md`** - High-level project overview and architecture summary

#### Graph Executor Specifics
- **`docs/graph_executor_requirement.md`** - Comprehensive GraphExecutor requirements (v1.2, June 23, 2025)
- **`docs/graph_execution pattern.md`** - All execution patterns supported with conditional branching (v3.0)
- **`docs/execution_planning_update.md`** - Performance improvements: single trigger, graph pruning, O(1) lookups

#### Testing & Implementation
- **`test/prana/execution/graph_executor_test.exs`** - Core graph execution tests
- **`test/prana/execution/graph_executor_conditional_branching_test.exs`** - 24 passing conditional branching tests (1358 lines)
- **`test/prana/execution/workflow_compiler_test.exs`** - Workflow compilation tests
- **`lib/prana/integrations/logic.ex`** - Logic integration with if_condition, switch, merge actions (351 lines)
- **`lib/prana/integrations/manual.ex`** - Manual integration for testing workflows

### Git Status Context
Currently on `feature/phase2-graph-execution-if-condition` branch with significant advancements:
- Graph Executor Phase 3.1 (Core Execution) complete with sequential execution and performance optimizations
- Graph Executor Phase 3.2 (Conditional Branching) complete with IF/ELSE and Switch patterns
- Active path tracking and conditional workflow completion implemented
- Comprehensive test coverage for conditional branching scenarios
- Performance improvements: single trigger execution, graph pruning, O(1) connection lookups
