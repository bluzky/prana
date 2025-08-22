# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Prana** is an Elixir workflow automation platform built around a node-based graph execution model. It orchestrates workflows consisting of nodes (triggers, actions, logic, wait, output) connected through explicit ports with conditional routing and template-based data flow.

**Current Status**: **Production-Ready Core Platform** (~95% complete)
- ✅ Complete execution engine with conditional branching and sub-workflow support
- ✅ Comprehensive built-in integrations (Manual, Logic, Data, Workflow, Wait, HTTP, Code)
- ✅ Advanced features: Loop constructs, template engine integration, and performance optimizations
- 🎯 Current branch: `feature/for-each-loop` - Adding enhanced loop processing capabilities

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
- **Current test coverage**: 72.98% (below 90% threshold)
- **25 test files** with comprehensive coverage for core execution engine
- **Test coverage priorities**: HTTP integration (55-80%), Code integration (34-85%)
- Test files follow `*_test.exs` naming convention
- Use `mix test --trace` for detailed test output
- Use `mix test --cover` to generate coverage reports

## Architecture Overview

### Core Design Principles
- **Type Safety**: All data uses proper Elixir structs with compile-time checking
- **Behavior-Driven**: Clean contracts for integrations and middleware
- **Node-Port Model**: Explicit data flow through named ports between nodes
- **Template Integration**: Dynamic data access and templating using MAU library
- **Action Behavior Pattern**: Actions implemented as modules following Prana.Behaviour.Action with prepare/execute/resume methods

### Key Components

#### Core Data Structures (`lib/prana/core/`)
- **`Prana.Workflow`**: Complete workflow with nodes and double-indexed connections
- **`Prana.Node`**: Individual workflow node with type, integration, action, and configuration
- **`Prana.Connection`**: Port-based connections between nodes with conditions and data mapping
- **`Prana.WorkflowExecution`**: Complete execution instance with runtime state and audit trail
- **`Prana.NodeExecution`**: Individual node execution state tracking

**Serialization Support**: All core structs implement `from_map/1` and `to_map/1` for JSON-compatible persistence with automatic type conversion and nested struct handling.

```elixir
# Serialize workflow to JSON-compatible map
workflow_map = Prana.Workflow.to_map(workflow)
json_string = Jason.encode!(workflow_map)

# Restore from JSON with proper types
workflow_data = Jason.decode!(json_string)
restored_workflow = Prana.Workflow.from_map(workflow_data)
```

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
- **`Prana.NodeExecutor`** (`node_executor.ex`): ✅ **PRODUCTION READY** - Executes individual nodes with template-based input preparation, Action behavior execution, suspension/resume patterns, and comprehensive error handling
- **`Prana.GraphExecutor`** (`execution/graph_executor.ex`): ✅ **PRODUCTION READY** - Orchestrates workflow execution using NodeExecutor, handles conditional branging, port-based routing, sub-workflow coordination, and middleware integration
- **`Prana.Template`** (`template.ex`): ✅ **COMPLETE** - Template processing using MAU library for dynamic data access

#### Registry & Extension System
- **`Prana.IntegrationRegistry`** (`registry/integration_registry.ex`): GenServer managing integrations and their actions
- **`Prana.Behaviour.Integration`**: Contract for workflow integrations
- **`Prana.Behaviour.Middleware`**: Contract for workflow lifecycle event handling

#### Built-in Integrations (`lib/prana/integrations/`)
- **`Prana.Integrations.Manual`** (`manual.ex`): Test actions for development and testing workflows (100% coverage)
- **`Prana.Integrations.Logic`** (`logic.ex`): Conditional branching with IF/ELSE and switch/case routing (100% coverage)
- **`Prana.Integrations.Data`** (`data.ex`): Data merging and combination operations for fork-join patterns (100% coverage)
- **`Prana.Integrations.Workflow`** (`workflow.ex`): Sub-workflow orchestration with suspension/resume coordination (100% coverage)
- **`Prana.Integrations.Wait`** (`wait.ex`): Delay actions and timeout handling for time-based workflows (96% coverage)
- **`Prana.Integrations.HTTP`** (`http.ex`): HTTP requests, webhooks, and API interactions (55-80% coverage)
- **`Prana.Integrations.Code`** (`code.ex`): Secure Elixir code execution with sandboxing (34-85% coverage)
- **`Prana.Integrations.Schedule`** (`schedule.ex`): Cron-based scheduling and time triggers (100% coverage)

#### Node Retry System ✅ **NEW**
- **`Prana.NodeSettings`** (`core/node_settings.ex`): Per-node retry configuration with delay and attempt limits
- **Suspension-based retry**: Failed nodes return `{:suspend, :retry, suspension_data}` for application scheduling
- **Smart retry logic**: Distinguishes between execution failures (retryable) and resume failures (not retryable)
- **Full integration**: Works with existing suspension/resume infrastructure and middleware events

#### Middleware System
- **`Prana.Middleware`** (`middleware.ex`): Pipeline execution engine for lifecycle events
- Events: `:execution_started`, `:execution_completed`, `:execution_failed`, `:node_starting`, `:node_completed`, `:node_failed`, `:node_suspended`, `:execution_suspended`

### Template System Integration

The platform uses MAU library for template processing and dynamic data access:
```elixir
# Template expressions are processed by MAU library
# Refer to MAU documentation for syntax and capabilities
# Context includes: input, nodes, variables, and execution state
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

**Overall Progress**: ~95% Complete (Production-ready platform with advanced features)
**Test Coverage**: 72.98% (below 90% threshold - focus area for improvement)
**Current Development**: Loop constructs and for-each batch processing capabilities

#### ✅ COMPLETED (Core Platform)
1. **All Core Data Structures** - Comprehensive struct-based design with proper type safety
2. **Behavior Definitions** - Simplified contracts (Integration, Middleware only)
3. **Template Integration** - MAU library integration for dynamic content processing
4. **Integration Registry** - Runtime integration management with health checking
5. **Middleware System** - Event-driven lifecycle handling with comprehensive test coverage
6. **Node Executor** - **PRODUCTION READY** individual node execution with suspension/resume support
7. **Workflow Compiler** - Complete workflow compilation into optimized ExecutionGraphs

#### ✅ CORE EXECUTION ENGINE - COMPLETE
1. **Graph Executor Phase 3.1** - Core Execution (Sequential, Sync/Fire-and-Forget) ✅ **COMPLETE**
2. **Graph Executor Phase 3.2** - Conditional Branching (IF/ELSE, Switch patterns) ✅ **COMPLETE**
3. **Graph Executor Phase 4.1** - Sub-workflow Orchestration (Parent-child coordination) ✅ **COMPLETE**

#### ✅ BUILT-IN INTEGRATIONS - COMPREHENSIVE SUITE
1. **Manual Integration** - Test actions and triggers for development workflows ✅ **COMPLETE** (100% coverage)
2. **Logic Integration** - IF/ELSE and switch/case routing with dynamic ports ✅ **COMPLETE** (100% coverage)
3. **Data Integration** - Merge operations for fork-join patterns (append, merge, concat) ✅ **COMPLETE** (100% coverage)
4. **Workflow Integration** - Sub-workflow orchestration with suspension/resume ✅ **COMPLETE** (100% coverage)
5. **Wait Integration** - Delay actions and timeout handling ✅ **COMPLETE** (96% coverage)
6. **HTTP Integration** - Request/webhook actions and API interactions ✅ **COMPLETE** (55-80% coverage)
7. **Code Integration** - Secure Elixir execution with sandboxing ✅ **COMPLETE** (34-85% coverage)
8. **Schedule Integration** - Cron triggers and time-based scheduling ✅ **COMPLETE** (100% coverage)

#### ✅ RECENTLY COMPLETED
- **Node Retry System**: Suspension-based retry mechanism with configurable delay and attempt limits ✅ **COMPLETE** (100% coverage)

#### 🎯 CURRENT PRIORITY (Advanced Features & Quality)
- **Loop Integration**: For-each batch processing and iteration patterns (in development)
- **Test Coverage Improvement**: Increase coverage from 72.98% to 90%+ threshold
- **Template Engine Integration**: MAU library integration for advanced templating
- **Performance Optimization**: Further execution engine enhancements

#### 📋 FUTURE ENHANCEMENTS
- **Main API**: Public interface for workflow management
- **Development Tools**: Visual workflow builder, validation utilities, testing frameworks
- **Advanced Patterns**: Complex coordination patterns, parallel execution optimizations
- **Integration Ecosystem**: Plugin system for third-party integrations

### Key Design Decisions

1. **Struct-Only Data** - No dynamic maps, all typed structs for compile-time safety
2. **Module-Based Integrations** - Only support behavior-implementing modules, no map definitions
3. **Middleware for Application Logic** - Clean separation between library (execution) and application (persistence)
4. **Port-Based Routing** - Explicit named ports for data flow instead of implicit connections
5. **Third-Party Template Engine** - Uses MAU library instead of built-in expression system
6. **Failed Executions Design** - Failed nodes have `output_port = nil`, error routing handled at graph level
7. **Simplified Behaviors** - Removed storage adapters, hook system; middleware provides better composability
8. **No Complex Validation** - Trust integration structs, simplified registry without normalization

### Working with the Codebase

#### Important Context for Development
- **Production-ready platform** with comprehensive execution engine and 8 built-in integrations
- **Advanced execution patterns**: Conditional branching, diamond patterns, sub-workflow coordination, loop constructs
- **Comprehensive integration suite**: Manual, Logic, Data, Workflow, Wait, HTTP, Code, Schedule integrations
- **Template integration**: Uses MAU library for template processing and dynamic data access
- **Current development focus**: Loop integration for for-each batch processing (feature/for-each-loop branch)
- **Test coverage priority**: Improving from 72.98% to 90%+ threshold, especially HTTP/Code integrations
- **Performance optimizations**: Single trigger execution, graph pruning, O(1) connection lookups
- **Double-indexed connections**: Optimized `%{node_key => %{output_port => [connections]}}` structure for ultra-fast routing
- **Suspension/resume support**: Full parent-child workflow coordination with NodeExecutor methods

#### Adding New Features
- Follow existing struct patterns in `lib/prana/core/`
- Use behaviors for extensibility (`lib/prana/behaviours/`)
- Add comprehensive tests following existing patterns (see `node_executor_test.exs` for examples)
- Aim for 90%+ test coverage on new integrations
- Use `mix credo` to ensure code quality and maintain consistency
- All new components should integrate with the middleware event system
- Use MAU library for any template processing or dynamic content needs

#### Testing Patterns
- **Template processing**: MAU library integration for dynamic content and data access
- **Node execution**: Multiple return formats, error handling, context management, suspension/resume
- **Integration patterns**: Action execution, error handling, port routing, schema validation
- **Middleware**: Event handling, pipeline execution, error resilience
- **Performance testing**: Use `benchee` for execution engine benchmarking
- Use `mix test --trace` for detailed test output during development
- Focus on improving coverage for HTTP and Code integrations
- MAU library handles all template processing - no need for expression engine tests

#### Node Retry Configuration
```elixir
# Create a node with retry settings
node_with_retry = %Prana.Node{
  key: "http_request",
  type: "http.request",
  params: %{url: "https://api.example.com/data"},
  settings: %Prana.NodeSettings{
    retry_on_failed: true,
    max_retries: 3,
    retry_delay_ms: 5000  # 5 second delay between retries
  }
}

# Application handles retry suspensions like other suspensions
case Prana.GraphExecutor.execute_workflow(execution, input) do
  {:suspend, suspended_execution, %{"resumed_at" => resumed_at}} ->
    # Schedule retry using timestamp instead of delay
    delay_ms = DateTime.diff(resumed_at, DateTime.utc_now(), :millisecond) |> max(0)
    Process.send_after(self(), {:resume_execution, suspended_execution}, delay_ms)
    
  {:suspend, suspended_execution, other_data} ->
    # Handle other suspension types normally
    handle_other_suspension(suspended_execution, other_data)
end
```

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
- **mau**: ~> 0.3 - Template engine for dynamic content processing
- **nestex**: ~> 0.2 - Path traversal and data extraction for template processing
- **req**: ~> 0.5 - HTTP client for HTTP integration
- **skema**: ~> 1.0 - Schema validation and data transformation
- **uuid**: ~> 1.1 - UUID generation for workflow and execution IDs
- **styler** (dev/test): ~> 1.5 - Code formatting
- **credo** (dev/test): ~> 1.7 - Static analysis
- **benchee** (dev): ~> 1.3 - Performance benchmarking

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
- **`docs/guides/serialization_guide.md`** - Complete guide for serializing/deserializing workflows and executions for persistence and APIs

- use mix run -e "code" to run custom code or short snipped
- use mix test test_file_path.exs --trace for verbose output log, there is no -v option
- you have to setup IntegrationRegistry before test. So add this to setup ` {:ok, registry_pid} = IntegrationRegistry.start_link()`
and remember to terminate process on exit
 on_exit(fn ->
        if Process.alive?(registry_pid) do
          GenServer.stop(registry_pid)
        end
      end)

- Using `tree` command to check directory structure