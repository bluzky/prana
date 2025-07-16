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
- **Action Behavior Pattern**: Actions implemented as modules following Prana.Behaviour.Action with prepare/execute/resume methods

### Key Components

#### Core Data Structures (`lib/prana/core/`)
- **`Prana.Workflow`**: Complete workflow with nodes and double-indexed connections
- **`Prana.Node`**: Individual workflow node with type, integration, action, and configuration
- **`Prana.Connection`**: Port-based connections between nodes with conditions and data mapping
- **`Prana.NodeExecution`**: Individual node execution state tracking

#### Optimized Connection Structure
```elixir
%Workflow{
  connections: %{
    "node_key" => %{
      "output_port" => [%Connection{...}, ...],
      "error_port" => [%Connection{...}, ...]
    }
  }
}
```

#### Execution Engine
- **`Prana.NodeExecutor`** (`node_executor.ex`): ✅ **PRODUCTION READY** - Executes individual nodes with expression-based input preparation, Action behavior execution, suspension/resume patterns, and comprehensive error handling
- **`Prana.GraphExecutor`** (`execution/graph_executor.ex`): ✅ **PRODUCTION READY** - Orchestrates workflow execution using NodeExecutor, handles conditional branching, port-based routing, sub-workflow coordination, and middleware integration
- **`Prana.ExpressionEngine`** (`expression_engine.ex`): ✅ **COMPLETE** - Path-based expression evaluation for dynamic data access

#### Registry & Extension System
- **`Prana.IntegrationRegistry`** (`registry/integration_registry.ex`): GenServer managing integrations and their actions
- **`Prana.Behaviour.Integration`**: Contract for workflow integrations
- **`Prana.Behaviour.Middleware`**: Contract for workflow lifecycle event handling

#### Built-in Integrations (`lib/prana/integrations/`)
- **`Prana.Integrations.Manual`** (`manual.ex`): Test actions for development and testing workflows
- **`Prana.Integrations.Logic`** (`logic.ex`): Conditional branching with IF/ELSE and switch/case routing
- **`Prana.Integrations.Data`** (`data.ex`): Data merging and combination operations for fork-join patterns
- **`Prana.Integrations.Workflow`** (`workflow.ex`): Sub-workflow orchestration with suspension/resume coordination

#### Middleware System
- **`Prana.Middleware`** (`middleware.ex`): Pipeline execution engine for lifecycle events
- Events: `:execution_started`, `:execution_completed`, `:execution_failed`, `:node_starting`, `:node_completed`, `:node_failed`, `:node_suspended`, `:execution_suspended`

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

#### ✅ VERIFIED COMPLETE - Phase 4.1 Sub-workflow Orchestration

**Phase 4.1 (Sub-workflow Orchestration)** - **COMPLETE**:
- ✅ **Workflow Integration** with three execution modes (sync, async, fire-and-forget)
- ✅ **Suspension/Resume Mechanisms** for parent-child workflow coordination
- ✅ **NodeExecutor.resume_node/4** for handling suspended node execution
- ✅ **Comprehensive Sub-workflow Tests** with 100+ test scenarios covering all patterns
- ✅ **Middleware Integration** with suspension/resume events

### Current Implementation Status

**Overall Progress**: ~95% Complete (Core execution engine and sub-workflow orchestration complete)

#### ✅ COMPLETED (Core Platform)
1. **All Core Data Structures** - Comprehensive struct-based design with proper type safety
2. **Behavior Definitions** - Simplified contracts (Integration, Middleware only)
3. **Expression Engine** - Complete path-based expression evaluation with wildcards and filtering
4. **Integration Registry** - Runtime integration management with health checking
5. **Middleware System** - Event-driven lifecycle handling with comprehensive test coverage
6. **Node Executor** - **PRODUCTION READY** individual node execution with suspension/resume support
7. **Workflow Compiler** - Complete workflow compilation into optimized ExecutionGraphs

#### ✅ CORE EXECUTION ENGINE - COMPLETE
1. **Graph Executor Phase 3.1** - Core Execution (Sequential, Sync/Fire-and-Forget) ✅ **COMPLETE**
2. **Graph Executor Phase 3.2** - Conditional Branching (IF/ELSE, Switch patterns) ✅ **COMPLETE**
3. **Graph Executor Phase 4.1** - Sub-workflow Orchestration (Parent-child coordination) ✅ **COMPLETE**

#### ✅ BUILT-IN INTEGRATIONS - COMPLETE
1. **Manual Integration** - Test actions and triggers for development workflows ✅ **COMPLETE**
2. **Logic Integration** - IF/ELSE and switch/case routing with dynamic ports ✅ **COMPLETE**
3. **Data Integration** - Merge operations for fork-join patterns (append, merge, concat) ✅ **COMPLETE**
4. **Workflow Integration** - Sub-workflow orchestration with suspension/resume ✅ **COMPLETE**

#### 🎯 CURRENT PRIORITY (Phase 4.2+ - Additional Integrations)
- **Wait Integration**: Delay actions and timeout handling for time-based workflows
- **HTTP Integration**: HTTP requests, webhooks, and API interactions
- **Transform Integration**: Data transformation, filtering, and mapping operations
- **Log Integration**: Structured logging actions for workflow debugging

#### 📋 FUTURE PHASES
- **Phase 5**: Main API - Public interface for workflow management
- **Phase 6**: Development Tools - Builder, validation, testing utilities
- **Phase 7**: Advanced Patterns - Loop constructs, complex coordination patterns

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
- **Core execution engine is production-ready** with comprehensive test coverage across all patterns
- **Built-in integrations are complete** - Manual, Logic, Data, and Workflow integrations fully implemented
- **Sub-workflow orchestration is complete** with suspension/resume mechanisms for parent-child coordination
- **NodeExecutor supports suspension/resume** with `execute_node/2` and `resume_node/4` methods
- **GraphExecutor handles all execution patterns** - sequential, conditional branching, fork-join, sub-workflows
- **Current focus** is additional integrations (Wait, HTTP, Transform, Log) for broader workflow capabilities
- **Major performance improvements**: Single trigger execution, graph pruning, O(1) connection lookups
- **Double-indexed connections**: Optimized `%{node_key => %{output_port => [connections]}}` structure for ultra-fast routing
- **Advanced execution patterns**: Conditional branching, diamond patterns, sub-workflow coordination

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
- **`docs/library_requirements.md`** - Final simplified requirements with struct-based design principles
- **`docs/implementation_plan.md`** - Detailed phase breakdown with current completion status
- **`docs/IMPLEMENTATION_SUMMARY.md`** - High-level project overview and architecture summary

#### Graph Executor Specifics
- **`docs/graph_executor_requirement.md`** - Comprehensive GraphExecutor requirements (v1.2, June 23, 2025)
- **`docs/graph_execution pattern.md`** - All execution patterns supported with conditional branching (v3.0)
- **`docs/execution_planning_update.md`** - Performance improvements: single trigger, graph pruning, O(1) lookups

#### Built-in Integrations & Workflow Building
- **`docs/built-in-integrations.md`** - Complete reference for Manual, Logic, Data, and Workflow integrations
- **`docs/guides/writing_integrations.md`** - Comprehensive guide for creating custom integrations
- **`docs/guides/building_workflows.md`** - Guide for composing workflows using built-in integrations
