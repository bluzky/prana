# Prana Implementation Summary
*Generated: June 20, 2025*

## Project Overview

**Prana** is an Elixir/Phoenix workflow automation platform built around a node-based graph execution model. Each workflow consists of nodes (triggers, actions, logic, wait, output) connected through explicit ports with conditional routing and data flow mapping.

**Current Status**: Phase 1 Complete (Data Structures & Behaviors) - Ready for Phase 2 (Execution Engine)

---

## Architecture Summary

### Core Design Principles
- **Type Safety**: All data uses proper Elixir structs with compile-time checking
- **Behavior-Driven**: Clean contracts for integrations and middleware
- **Separation of Concerns**: Library handles execution, applications handle persistence via middleware
- **Node-Port Model**: Explicit data flow through named ports between nodes
- **Expression System**: Built-in template evaluation (`{{ $node.field }}`) for dynamic data access

### Project Structure
```
prana/
├── lib/
│   ├── prana/
│   │   ├── core/              # ✅ Data structures (structs)
│   │   ├── behaviours/        # ✅ Behavior definitions
│   │   ├── registry/          # ✅ Integration registry
│   │   ├── middleware.ex      # ✅ Middleware pipeline
│   │   ├── integrations/      # 🚧 Built-in integrations (TODO)
│   │   ├── execution/         # 🚧 Execution engine (TODO)
│   │   └── expression_engine.ex # 🚧 Expression evaluator (TODO)
│   └── prana.ex               # 🚧 Main API (TODO)
├── test/                      # Basic test setup
└── mix.exs                    # Project configuration
```

---

## Implemented Modules (✅ Phase 1 Complete)

### Core Data Structures (`lib/prana/core/`)

#### `Prana.Workflow` (`workflow.ex`)
**Purpose**: Represents a complete workflow with nodes and connections
**Key Functions**:
- `new/2` - Create new workflow
- `from_map/1` - Load workflow from data
- `get_entry_nodes/1` - Find nodes with no incoming connections
- `get_connections_from/3` - Get connections from specific node/port
- `get_node_by_id/2`, `get_node_by_custom_id/2` - Node lookup
- `add_node/2`, `add_node!/2` - Add nodes with uniqueness validation
- `add_connection/2` - Add connections
- `valid?/1` - Validate workflow structure

**Key Fields**:
```elixir
%Prana.Workflow{
  id: String.t(),
  name: String.t(),
  description: String.t() | nil,
  version: integer(),
  nodes: [Prana.Node.t()],
  connections: [Prana.Connection.t()],
  variables: map(),
  settings: Prana.WorkflowSettings.t(),
  metadata: map()
}
```

#### `Prana.Node` (`node.ex`)
**Purpose**: Individual workflow node with type, integration, action, and configuration
**Key Functions**:
- `new/6` - Create new node
- `from_map/1` - Load node from data
- `valid?/1` - Validate node structure

**Key Fields**:
```elixir
%Prana.Node{
  id: String.t(),
  custom_id: String.t(),           # User-friendly unique identifier
  name: String.t(),
  type: :trigger | :action | :logic | :wait | :output,
  integration_name: String.t(),
  action_name: String.t(),
  input_map: map(),                # Configuration/input data
  output_ports: [String.t()],      # Available output ports
  input_ports: [String.t()],       # Available input ports
  error_handling: Prana.ErrorHandling.t(),
  retry_policy: Prana.RetryPolicy.t() | nil,
  timeout_seconds: integer() | nil,
  metadata: map()
}
```

#### `Prana.Connection` (`connection.ex`)
**Purpose**: Connection between nodes with port-based routing
**Key Functions**:
- `new/4` - Create new connection
- `from_map/1` - Load connection from data
- `valid?/1` - Validate connection structure

**Key Fields**:
```elixir
%Prana.Connection{
  id: String.t(),
  from_node_id: String.t(),
  from_port: String.t(),           # "success", "error", "true", "false"
  to_node_id: String.t(),
  to_port: String.t(),             # "input"
  conditions: [Prana.Condition.t()],
  data_mapping: map(),
  metadata: map()
}
```

#### Supporting Structures
- `Prana.Condition` (`condition.ex`) - Connection routing conditions
- `Prana.Integration` (`integration.ex`) - Integration definition struct
- `Prana.Action` (`action.ex`) - Action definition struct
- `Prana.Execution` (`execution.ex`) - Workflow execution instance
- `Prana.NodeExecution` (`node_execution.ex`) - Individual node execution state
- `Prana.ExecutionContext` (`execution_context.ex`) - Shared execution context
- `Prana.ErrorHandling` (`error_handling.ex`) - Error handling configuration
- `Prana.RetryPolicy` (`retry_policy.ex`) - Retry policy configuration
- `Prana.WorkflowSettings` (`workflow_settings.ex`) - Workflow-level settings

### Behavior Definitions (`lib/prana/behaviours/`)

#### `Prana.Behaviour.Integration` (`integration.ex`)
**Purpose**: Contract for workflow integrations
**Callbacks**:
- `@callback definition() :: Prana.Integration.t()`

**Integration Example**:
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

#### `Prana.Behaviour.Middleware` (`middleware.ex`)
**Purpose**: Contract for workflow lifecycle event handling
**Callbacks**:
- `@callback call(event(), data(), next_function()) :: data()`

**Events**: `:execution_started`, `:execution_completed`, `:execution_failed`, `:execution_suspended`, `:node_started`, `:node_completed`, `:node_failed`, `:sub_workflow_requested`

### Registry System (`lib/prana/registry/`)

#### `Prana.IntegrationRegistry` (`integration_registry.ex`)
**Purpose**: GenServer for managing integrations and their actions
**Key Functions**:
- `register_integration/1` - Register integration module
- `get_action/2` - Get action by integration and action name
- `list_integrations/0` - List all registered integrations
- `get_integration/1` - Get complete integration definition
- `unregister_integration/1` - Remove integration
- `integration_registered?/1` - Check if integration exists
- `get_statistics/0` - Registry statistics
- `health_check/0` - Health check for all integrations

### Middleware System (`lib/prana/`)

#### `Prana.Middleware` (`middleware.ex`)
**Purpose**: Middleware pipeline execution engine
**Key Functions**:
- `call/2` - Execute middleware pipeline for event and data
- `get_middleware_modules/0` - Get configured middleware
- `execute_pipeline/3` - Execute pipeline with modules
- `add_middleware/1`, `remove_middleware/1`, `clear_middleware/0` - Runtime management
- `get_stats/0` - Pipeline statistics

**Configuration**:
```elixir
config :prana, middleware: [
  MyApp.DatabaseMiddleware,
  MyApp.NotificationMiddleware
]
```

### Main API (`lib/`)

#### `Prana` (`prana.ex`)
**Status**: 🚧 Placeholder - needs implementation
**Current**: Only has `hello/0` function
**Planned**: Main public API for workflow creation, execution, and management

---

## Not Yet Implemented (🚧 Phase 2+)

### Execution Engine Components
- **Expression Evaluator** - Parse and evaluate `{{ $node.field }}` templates
- **Graph Executor** - Workflow traversal and parallel execution
- **Node Executor** - Individual action invocation and port routing
- **Error Handling** - Retry logic and error propagation

### Built-in Integrations
- **HTTP Integration** - Request actions and webhook triggers
- **Transform Integration** - Data extraction, mapping, filtering
- **Logic Integration** - Conditions, switches, merging
- **Log Integration** - Debug output and logging
- **Wait Integration** - Delays and execution suspension

### API & Tools
- **Main API Module** - Workflow creation and execution interface
- **Workflow Builder** - Fluent API for building workflows
- **Validation Tools** - Workflow structure validation
- **Testing Helpers** - Test utilities for workflows and integrations
- **Development Tools** - Debugging and profiling utilities

---

## Dependencies & Configuration

### `mix.exs`
- **Elixir Version**: ~> 1.16
- **Dependencies**: 
  - `styler` (dev/test) - Code formatting
  - `credo` (dev/test) - Static analysis
- **Application**: Only `:logger` extra application

### Current Limitations
- No OTP application supervision tree
- No built-in integrations
- No execution engine
- Placeholder main API

---

## Next Implementation Steps (Phase 2)

1. **Expression Evaluator** (`Prana.ExpressionEngine`)
   - Parse template expressions `{{ $node.field }}`
   - Evaluate with context (nodes, variables, input)
   - Handle nested data access and basic functions

2. **Node Executor** (`Prana.NodeExecutor`)
   - Action invocation via MFA pattern
   - Input preparation and expression evaluation
   - Output port determination
   - Retry logic implementation

3. **Graph Executor** (`Prana.GraphExecutor`)
   - Graph traversal and execution planning
   - Parallel node execution with Tasks
   - Port-based data routing
   - Context management and middleware event emission

4. **Main API** (`Prana`)
   - `create_workflow/2`, `add_node/6`, `connect_nodes/5`
   - `execute_workflow/3`
   - Integration registration helpers

---

## Key Design Decisions Made

1. **Struct-Only Data** - No dynamic maps, all typed structs for compile-time safety
2. **Module-Based Integrations** - Only support behavior-implementing modules, no map definitions
3. **Middleware for Application Logic** - Clean separation between library (execution) and application (persistence)
4. **Port-Based Routing** - Explicit named ports for data flow instead of implicit connections
5. **Built-in Expression Engine** - Simple template system instead of external DSL
6. **MFA Action Pattern** - Actions defined as `{module, function, args}` tuples

---

## Testing Strategy

- **Current**: Basic test setup with placeholder test
- **Planned**: 
  - Integration behavior testing
  - Middleware pipeline testing
  - Workflow validation testing
  - Expression evaluation testing
  - End-to-end workflow execution testing

---

*This document should be updated as implementation progresses through subsequent phases.*