#+title:      Prana Core Library - Revised Implementation Plan
#+date:       [2025-06-20 Fri 16:15]
#+filetags:   :prana:
#+identifier: 20250620T161500

# Prana Core Library - Revised Implementation Components

## 1. Data Structures & Types (✅ COMPLETED)

### 1.1 Core Data Types
- [x] `Prana.Workflow` - Workflow definition with nodes and connections
- [x] `Prana.Node` - Individual node with type, integration, action, config
- [x] `Prana.Connection` - Connection between nodes with ports and conditions
- [x] `Prana.Condition` - Connection routing conditions
- [x] `Prana.Integration` - Integration struct with actions
- [x] `Prana.Action` - Action struct with metadata

### 1.2 Execution Data Types
- [x] `Prana.Execution` - Workflow execution instance
- [x] `Prana.NodeExecution` - Individual node execution state
- [x] `Prana.ExecutionContext` - Shared execution context

### 1.3 Configuration Types
- [x] `Prana.ErrorHandling` - Error handling configuration
- [x] `Prana.RetryPolicy` - Retry policy configuration
- [x] `Prana.WorkflowSettings` - Workflow-level settings

## 2. Core Behaviors (✅ COMPLETED - Simplified)

### 2.1 Integration Behavior
- [x] `Prana.Behaviour.Integration` - Simplified integration contract
  - [x] Single required callback: `definition/0`
  - [x] Returns `Prana.Integration` struct
  - [x] No configuration or state management

### 2.2 Middleware Behavior
- [x] `Prana.Behaviour.Middleware` - Event handling contract
  - [x] Single callback: `call(event, data, next)`
  - [x] Composable pipeline design
  - [x] Error resilience

### 2.3 Removed Behaviors
- [x] ~~`Prana.Behaviour.StorageAdapter`~~ - Replaced with middleware
- [x] ~~`Prana.Behaviour.Hook`~~ - Replaced with middleware
- [x] ~~`Prana.Behaviour.ExpressionEngine`~~ - Built-in implementation
- [x] ~~`Prana.Behaviour.ActionExecutor`~~ - Unnecessary abstraction

## 3. Core Engine Components

### 3.1 Expression Evaluator (✅ COMPLETED)
- [x] `Prana.ExpressionEngine` - Built-in path expression engine
  - [x] Parse path expressions `$input.field`, `$nodes.api.response`
  - [x] Evaluate with flexible context (any map structure)
  - [x] Handle nested data access and array indexing
  - [x] Wildcard extraction (`$input.users.*.name`)
  - [x] Array filtering (`$input.users.{role: "admin"}.email`)
  - [x] Predictable output types (single values vs arrays)
  - [x] Comprehensive error handling and validation
  - [x] Clean public API (`extract/2`, `process_map/2`)

### 3.2 Graph Executor
- [ ] `Prana.GraphExecutor` - Core workflow execution engine
  - [ ] Graph traversal and execution planning
  - [ ] Parallel node execution with Tasks
  - [ ] Port-based data routing
  - [ ] Error handling and propagation
  - [ ] Context management
  - [ ] Middleware event emission

### 3.3 Node Executor
- [ ] `Prana.NodeExecutor` - Individual node execution
  - [ ] Action invocation via MFA
  - [ ] Input preparation and expression evaluation
  - [ ] Output port determination
  - [ ] Retry logic implementation
  - [ ] Error capture and routing

## 4. Registry System (✅ COMPLETED - Simplified)

### 4.1 Integration Registry
- [x] `Prana.IntegrationRegistry` - Simplified integration management
  - [x] Runtime integration registration (module-based only)
  - [x] Action lookup and retrieval
  - [x] Integration listing and discovery
  - [x] Basic health checking
  - [x] Statistics and monitoring

### 4.2 Removed Components
- [x] ~~Storage Manager~~ - No longer needed
- [x] ~~Complex validation~~ - Trust integration structs
- [x] ~~Map normalization~~ - Work with structs directly

## 5. Middleware System (✅ COMPLETED)

### 5.1 Middleware Pipeline
- [x] `Prana.Middleware` - Pipeline execution engine
  - [x] Sequential middleware execution
  - [x] Error handling with graceful fallback
  - [x] Runtime configuration
  - [x] Statistics and monitoring

### 5.2 Middleware Events
- [x] Lifecycle events defined in behavior documentation
- [x] Composable event handling
- [x] Application-controlled persistence and coordination

## 6. Built-in Integrations

### 6.1 HTTP Integration
- [ ] `Prana.Integrations.HTTP` - HTTP operations
  - [ ] HTTP request action (GET, POST, PUT, DELETE)
  - [ ] Webhook trigger action
  - [ ] Response handling and port routing
  - [ ] Error handling (timeout, connection errors)

### 6.2 Transform Integration
- [ ] `Prana.Integrations.Transform` - Data transformation
  - [ ] Extract fields action
  - [ ] Map fields action
  - [ ] Filter data action
  - [ ] Set variables action

### 6.3 Logic Integration
- [ ] `Prana.Integrations.Logic` - Conditional logic
  - [ ] IF condition action (true/false ports)
  - [ ] Switch action (multiple case ports)
  - [ ] Merge action (combine inputs)

### 6.4 Log Integration
- [ ] `Prana.Integrations.Log` - Logging operations
  - [ ] Info log action
  - [ ] Debug log action
  - [ ] Error log action

### 6.5 Wait Integration
- [ ] `Prana.Integrations.Wait` - Delay operations
  - [ ] Simple delay action
  - [ ] Wait for execution action

## 7. Main API

### 7.1 Core API Module
- [ ] `Prana` - Main public API
  - [ ] Workflow creation and management
  - [ ] Node and connection helpers
  - [ ] Workflow execution
  - [ ] Integration registration helpers
  - [ ] Configuration management

### 7.2 Builder Helpers
- [ ] `Prana.WorkflowBuilder` - Fluent workflow building
  - [ ] Method chaining for workflow construction
  - [ ] Node ID management
  - [ ] Connection helpers
  - [ ] Validation helpers

## 8. Development Tools

### 8.1 Validation Tools
- [ ] `Prana.Validator` - Workflow validation
  - [ ] Graph structure validation
  - [ ] Node configuration validation
  - [ ] Connection validation
  - [ ] Circular dependency detection

### 8.2 Testing Tools
- [ ] `Prana.TestHelpers` - Testing utilities
  - [ ] Middleware testing helpers
  - [ ] Test execution helpers
  - [ ] Assertion helpers
  - [ ] Workflow fixtures

### 8.3 Development Helpers
- [ ] `Prana.Dev` - Development utilities
  - [ ] Integration scaffolding
  - [ ] Workflow debugging
  - [ ] Performance profiling
  - [ ] Configuration validation

## 9. Application & Supervision

### 9.1 Application Module
- [ ] `Prana.Application` - OTP application
  - [ ] Supervision tree setup
  - [ ] Built-in integration registration
  - [ ] Default middleware configuration
  - [ ] Graceful startup and shutdown

### 9.2 Configuration
- [ ] Application configuration schema
- [ ] Environment-specific configuration
- [ ] Runtime configuration validation

## 10. Error Handling & Resilience

### 10.1 Error Types
- [ ] `Prana.Errors` - Error type definitions
  - [ ] Workflow errors
  - [ ] Node execution errors
  - [ ] Configuration errors
  - [ ] Integration errors

### 10.2 Resilience Components
- [ ] Retry logic implementation
- [ ] Circuit breaker patterns
- [ ] Timeout handling
- [ ] Graceful degradation

## 11. Examples

### 11.1 Example Workflows
- [ ] `Prana.Examples` - Example workflow definitions
  - [ ] Basic HTTP workflow examples
  - [ ] Conditional routing examples
  - [ ] Data transformation examples
  - [ ] Error handling examples
  - [ ] Custom integration examples

## Revised Library Structure

```
prana/
├── lib/
│   ├── prana/
│   │   ├── core/              # Core data structures (all structs)
│   │   ├── behaviours/        # Simplified behavior definitions
│   │   ├── integrations/      # Built-in integrations
│   │   ├── execution/         # Execution engine components
│   │   ├── registry/          # Integration registry
│   │   ├── middleware.ex      # Middleware pipeline
│   │   ├── expression_engine.ex # Built-in expression evaluator
│   │   ├── dev/               # Development tools
│   │   └── examples/          # Example workflows
│   └── prana.ex               # Main API
├── examples/                  # Usage examples
├── test/                      # Test suite
└── mix.exs                    # Project configuration
```

## Implementation Priority

### Phase 1: Foundation (✅ COMPLETED)
1. [x] Data structures (Workflow, Node, Connection, etc.)
2. [x] Core behaviors (Integration, Middleware)
3. [x] Integration registry (simplified)
4. [x] Middleware system
5. [x] Expression engine (path-based expressions)

### Phase 2: Execution Engine (🚧 IN PROGRESS)
1. [ ] Node executor (use expression engine for input preparation)
2. [ ] Graph executor (orchestrate workflow execution)
3. [ ] Basic error handling and retry logic

### Phase 3: Built-in Integrations
1. HTTP integration
2. Transform integration
3. Logic integration
4. Log integration

### Phase 4: API & Tools
1. Main API module
2. Workflow builder
3. Validation tools
4. Basic testing helpers

### Phase 5: Polish & Examples
1. Development tools
2. Example workflows
3. Wait integration
4. Documentation

## Key Changes from Original Plan

### ✅ Completed Simplifications
- **Removed Storage Adapters**: Replaced with middleware for application control
- **Removed Hook System**: Middleware provides better composability
- **Simplified Integration Registry**: No complex validation/normalization
- **Struct-Based Design**: Type safety with compile-time checking
- **Single Integration Registration**: Only module-based, no map definitions

### 🎯 Focus Areas for Phase 2
- **Node Executor**: Action invocation with expression-based input preparation
- **Graph Executor**: Workflow traversal and parallel execution coordination
- **Middleware Integration**: Emit lifecycle events during execution
- **Error Handling**: Robust error management and recovery

### 📋 Deferred to Applications
- **Persistence**: Applications handle via middleware
- **External Coordination**: Applications manage via middleware
- **Health Monitoring**: Basic registry health + application middleware
- **Configuration Management**: Simple config + application-specific logic

This revised plan reflects the cleaner, more focused design we've developed, with clear separation between library responsibilities (execution) and application responsibilities (persistence, coordination).
