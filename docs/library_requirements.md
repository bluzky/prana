#+title:      Prana Core Library - Revised Requirements
#+date:       [2025-06-20 Fri 16:00]
#+filetags:   :prana:
#+identifier: 20250620T160000

# Prana Core Library - Final Requirements (Revised)

## 1. Core Architecture

### 1.1 Node-Based Graph Structure
- **Graph Model**: Directed graph of nodes and connections with data flow mapping
- **Node Types**: trigger, action, logic, wait, output
- **Connections**: Explicit connections between node ports with conditional routing
- **Execution Flow**: Graph traversal with parallel execution support

### 1.2 Integration System
- **Simple Registration**: Runtime registration of integrations
- **MFA Executor Pattern**: Each action defined as `{module, function, args}` tuple
- **Struct Definitions**: `Prana.Integration` and `Prana.Action` structs for type safety
- **Action Metadata**: Name, description, ports for discoverability

## 2. Node System Design

### 2.1 Node Structure
```elixir
%Prana.Node{
  id: String.t(),
  custom_id: String.t(),
  name: String.t(),
  type: :trigger | :action | :logic | :wait | :output,
  integration_name: String.t(),
  action_name: String.t(),
  params: map(),
  output_ports: [String.t()],
  input_ports: [String.t()],
  position: {x, y}
}
```

### 2.2 Connection System
```elixir
%Prana.Connection{
  from: String.t(),
  from_port: String.t(), # "success", "error", "true", "false"
  to: String.t(),
  to_port: String.t(),   # "input"
  mapping: map()
}
```

### 2.3 Node Categories

#### Trigger Nodes
- **HTTP Webhook**: Receive HTTP requests
- **Schedule**: Time-based triggers (cron, interval)
- **Manual**: User-initiated execution

#### Action Nodes
- **HTTP Request**: REST API operations
- **Transform**: Data transformation utilities
- **File Operations**: Basic file read/write
- **Custom Actions**: User-defined actions via integrations

#### Logic Nodes
- **IF Condition**: Conditional branching (true/false outputs)
- **Switch**: Multi-branch routing based on values
- **Merge**: Combine data from multiple inputs

#### Wait Nodes
- **Delay**: Time-based delays
- **Wait for Execution**: Suspend until child pipelines complete

#### Output Nodes
- **Log**: Output data for debugging/monitoring
- **HTTP Response**: Send HTTP responses
- **File Output**: Save data to files

## 3. Workflow Execution System

### 3.1 Simple Async Execution
- **Parallel Execution**: Execute independent nodes concurrently
- **Sequential Dependencies**: Respect node dependencies through connections
- **Error Isolation**: Errors in one branch don't affect others

### 3.2 Execution Modes
- **Synchronous**: Parent waits for child completion
- **Asynchronous**: Fire-and-forget execution
- **Test Mode**: Step-by-step execution for debugging

### 3.3 Data Flow Management
- **Context Passing**: Shared context across pipeline execution
- **Port-based Routing**: Data flows through explicit ports
- **Simple Data Types**: Focus on JSON-compatible data structures

## 4. Sub-Pipeline Integration

### 4.1 Pipeline Trigger Nodes
- **Reference by ID**: Trigger pipelines by identifier
- **Parameter Mapping**: Simple input/output parameter mapping
- **Execution Modes**: sync, async

### 4.2 Simple Wait Implementation
- **Basic Suspension**: Simple wait for completion
- **Timeout Handling**: Basic timeout with fallback

## 5. Error Handling & Resilience

### 5.1 Node-Level Error Handling
- **Port-based Error Routing**: Route errors through error ports
- **Simple Retry Policies**: Basic retry count and backoff
- **Continue on Error**: Option to continue execution

### 5.2 Pipeline-Level Error Handling
- **Error Propagation**: Bubble up critical errors
- **Error Data Capture**: Store error information for debugging

## 6. Expression System

### 6.1 Built-in Path Expressions
```javascript
// Simple field access
$input.email
$nodes.api_call.response.user_id
$variables.api_url

// Array access
$input.users[0].name
$nodes.search_results.items[1].title

// Wildcard extraction (returns arrays)
$input.users.*.name
$input.users.*.skills.*

// Filtering (returns arrays)
$input.users.{role: "admin"}.email
$input.orders.{status: "completed", user_id: 123}.amount
$input.users.{is_active: true, role: "admin"}
```

### 6.2 Expression Output Behavior
- **Simple paths**: Return single values (string, number, boolean, object)
- **Wildcard paths**: Always return arrays (even if empty or single item)
- **Filter paths**: Always return arrays (even if empty or single match)
- **Non-expressions**: Returned as-is without processing

### 6.3 Filter Value Types
- **Strings**: `{role: "admin"}` or `{role: 'user'}`
- **Booleans**: `{is_active: true}`, `{is_verified: false}`
- **Numbers**: `{age: 25}`, `{price: 29.99}`
- **Unquoted**: `{status: pending}` (treated as string)

### 6.4 Expression Context
- **Flexible Context**: Simple map structure, no enforced schema
- **Common Keys**: `"input"`, `"nodes"`, `"variables"` (by convention)
- **Application-Defined**: Applications can use any context structure

## 7. Core Library Architecture

### 7.1 Behavior-Driven Design
```elixir
# Core behaviors for extensibility
@behaviour Prana.Behaviour.Integration
@behaviour Prana.Behaviour.Middleware
```

### 7.2 Struct-Based Design
- **Type Safety**: All core entities use proper Elixir structs
- **No Dynamic Maps**: Structured data with compile-time checking
- **Clear Contracts**: Well-defined data structures

## 8. Middleware System

### 8.1 Middleware Behavior
```elixir
@behaviour Prana.Behaviour.Middleware

# Handle workflow lifecycle events
@callback call(event(), data(), next_function()) :: data()
```

### 8.2 Event-Driven Architecture
- **Lifecycle Events**: execution_started, execution_completed, node_failed, etc.
- **Composable Pipeline**: Multiple middleware can handle same events
- **Error Resilience**: Middleware failures don't break the pipeline

## 9. Integration System

### 9.1 Simple Integration Definition
```elixir
defmodule MyApp.SlackIntegration do
  @behaviour Prana.Behaviour.Integration

  def definition do
    %Prana.Integration{
      name: "slack",
      display_name: "Slack",
      description: "Send messages to Slack channels",
      version: "1.0.0",
      category: "communication",
      actions: %{
        "send_message" => %Prana.Action{
          name: "send_message",
          display_name: "Send Message",
          module: __MODULE__,
          function: :send_message,
          input_ports: ["input"],
          output_ports: ["success", "error"],


        }
      }
    }
  end

  # Action implementation
  def send_message(input), do: {:ok, %{message_id: "123"}}
end
```

### 9.2 Action Return Formats
- **Explicit Port**: `{:ok, data, "success"}` or `{:error, error, "timeout"}`
- **Default Port**: `{:ok, data}` → default success port, `{:error, error}` → default error port

## 10. Built-in Integrations

### 10.1 Core Integrations
- **HTTP**: Request actions and webhook triggers
- **Transform**: Data extraction, mapping, filtering
- **Logic**: Conditions, switches, merging
- **Log**: Simple logging and debugging
- **Wait**: Delays and execution waiting
- **File**: Basic file operations

### 10.2 Integration Features
- **Struct-Based**: All integrations return proper struct definitions
- **Multiple Actions**: Each integration provides multiple related actions
- **Port Definitions**: Clear input/output port specifications

## 11. Middleware Event System

### 11.1 Configurable Middleware
```elixir
# Application configuration
config :prana, middleware: [
  MyApp.DatabaseMiddleware,
  MyApp.NotificationMiddleware,
  MyApp.AnalyticsMiddleware
]
```

### 11.2 Core Events
- **Pipeline Events**: started, completed, failed
- **Node Events**: started, completed, failed, retried
- **System Events**: integration_registered

## 12. Development Tools

### 12.1 Testing & Validation
- **Pipeline Validation**: Static analysis of pipeline structure
- **Node Testing**: Test individual nodes in isolation
- **Integration Testing**: Test custom integrations
- **Middleware Testing**: Test middleware pipeline

### 12.2 Development Helpers
- **Integration Registry**: Runtime registration and discovery
- **Pipeline Builder**: Fluent API for building pipelines
- **Debug Mode**: Step-through execution with logging

## 13. Simple API Interface

### 13.1 Core API
```elixir
# Main library interface
Prana.create_workflow(name, description)
Prana.add_node(workflow, name, type, integration, action, config)
Prana.connect_nodes(workflow, from_node, from_port, to_node, to_port)
Prana.execute_workflow(workflow, input_data, context)

# Registry operations
Prana.IntegrationRegistry.register_integration(integration_module)
Prana.IntegrationRegistry.get_action(integration_name, action_name)

# Middleware operations
Prana.Middleware.call(event, data)
```

### 13.2 Configuration
```elixir
# Application configuration
config :prana,
  middleware: [MyApp.DatabaseMiddleware, MyApp.NotificationMiddleware],
  integrations: [MyApp.SlackIntegration, MyApp.EmailIntegration]
```

## 14. Library Structure

```
prana/
├── lib/
│   ├── prana/
│   │   ├── core/              # Core data structures (structs)
│   │   ├── behaviours/        # Behavior definitions
│   │   ├── integrations/      # Built-in integrations
│   │   ├── execution/         # Execution engine
│   │   ├── registry/          # Integration registry
│   │   ├── middleware.ex      # Middleware pipeline
│   │   └── expression_engine.ex # Built-in expression evaluator
│   └── prana.ex               # Main API
├── examples/                  # Usage examples
├── test/                      # Test suite
└── docs/                      # Documentation
```

## 15. Key Design Principles

### 15.1 Simplicity
- **Struct-only data**: Well-defined, type-safe data structures
- **Built-in expressions**: Simple template substitution engine
- **Minimal dependencies**: Keep external dependencies to minimum
- **Clear APIs**: Intuitive, well-documented interfaces

### 15.2 Extensibility
- **Behavior-driven**: Clear contracts for integration and middleware
- **Self-contained**: Integrations manage their own concerns
- **Multiple actions**: Rich integrations with many related actions
- **Middleware pipeline**: Flexible event handling system

### 15.3 Developer Experience
- **Easy setup**: Works out of the box with minimal configuration
- **Type safety**: Compile-time checking with proper structs
- **Good errors**: Clear error messages and debugging info
- **Testing support**: Built-in tools for testing workflows and integrations

### 15.4 Application Separation
- **Library Focus**: Core workflow execution and integration management
- **Application Responsibility**: Persistence, external coordination, UI
- **Middleware Bridge**: Clean way for applications to handle lifecycle events

This simplified design maintains the core value proposition while removing complexity: a flexible, extensible workflow engine with strong typing that can be embedded in any Elixir application through a clean middleware interface.
