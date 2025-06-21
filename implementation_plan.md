# Prana Core Library - Updated Implementation Plan

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
- [x] `Prana.NodeExecution` - Individual node execution state (Updated: fixed fail/2)
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

### 3.2 Node Executor (✅ COMPLETED)
- [x] `Prana.NodeExecutor` - Individual node execution
  - [x] Action invocation via MFA
  - [x] Input preparation and expression evaluation
  - [x] Output port determination
  - [x] Error capture and routing
  - [x] Comprehensive exception handling (rescue, catch :exit, catch :throw)
  - [x] Structured error maps with JSON serialization
  - [x] Context management with custom_id storage
  - [x] Integration registry integration
  - [x] 100+ test scenarios covering all edge cases

### 3.3 Workflow Compiler (✅ COMPLETED)
- [x] `Prana.WorkflowCompiler` - Compile workflows into execution graphs
  - [x] Trigger node selection and validation
  - [x] Graph reachability analysis using BFS traversal
  - [x] Workflow pruning to remove unreachable nodes
  - [x] Dependency graph construction for execution ordering
  - [x] Performance optimization with O(1) lookup structures
  - [x] Clean public API (`compile/2`, `find_ready_nodes/4`)
  - [x] ExecutionGraph output with optimized data structures
  - [x] Renamed from ExecutionPlanner for accurate terminology

### 3.4 Graph Executor (🚧 IN PROGRESS)
- [ ] `Prana.GraphExecutor` - Core workflow execution engine
  - [x] Basic execution loop structure implemented
  - [x] WorkflowCompiler integration for ExecutionGraph consumption
  - [x] Event emission framework via Middleware
  - [x] Retry handling coordination
  - [x] Batch execution patterns for parallel nodes
  - [ ] **Completion detection logic needs refinement**
  - [ ] **Comprehensive end-to-end testing**
  - [ ] **Error handling edge cases**

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
  - [x] Comprehensive unit tests (100+ test scenarios)

### 5.2 Middleware Events
- [x] Lifecycle events defined in behavior documentation
- [x] Composable event handling
- [x] Application-controlled persistence and coordination

### 5.3 Testing Coverage
- [x] Core functionality tests (pipeline execution, configuration)
- [x] Event handling tests (event-specific middleware, pass-through)
- [x] Data transformation tests (single/multiple middleware chains)
- [x] Error handling tests (middleware failures, recovery, logging)
- [x] Pipeline control tests (short-circuiting, next function usage)
- [x] Integration scenarios (realistic workflow simulation)
- [x] Edge cases (complex data structures, long middleware chains)

## 6. Built-in Integrations (📋 TODO - Phase 4)

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

## 7. Main API (📋 TODO - Phase 5)

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

## 8. Development Tools (📋 TODO - Phase 6)

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

## 9. Application & Supervision (📋 TODO - Phase 6)

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

## 10. Error Handling & Resilience (📋 TODO - Phase 4)

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

## 11. Examples (📋 TODO - Phase 6)

### 11.1 Example Workflows
- [ ] `Prana.Examples` - Example workflow definitions
  - [ ] Basic HTTP workflow examples
  - [ ] Conditional routing examples
  - [ ] Data transformation examples
  - [ ] Error handling examples
  - [ ] Custom integration examples

## Updated Library Structure

```
prana/
├── lib/
│   ├── prana/
│   │   ├── core/              # ✅ Core data structures (all structs)
│   │   ├── behaviours/        # ✅ Simplified behavior definitions
│   │   ├── registry/          # ✅ Integration registry
│   │   ├── middleware.ex      # ✅ Middleware pipeline
│   │   ├── node_executor.ex   # ✅ Node executor (COMPLETED)
│   │   ├── expression_engine.ex # ✅ Built-in expression evaluator
│   │   ├── execution/         # 🎯 Graph executor (NEXT)
│   │   ├── integrations/      # 📋 Built-in integrations (TODO)
│   │   ├── dev/               # 📋 Development tools (TODO)
│   │   └── examples/          # 📋 Example workflows (TODO)
│   └── prana.ex               # 📋 Main API (TODO)
├── test/                      # ✅ Comprehensive test coverage
│   ├── prana/
│   │   ├── core/              # ✅ Data structure tests
│   │   ├── behaviours/        # ✅ Behavior tests
│   │   ├── registry/          # ✅ Integration registry tests
│   │   ├── middleware_test.exs # ✅ Middleware system tests (COMPLETED)
│   │   ├── node_executor_test.exs # ✅ Node executor tests (COMPLETED)
│   │   └── expression_engine_test.exs # ✅ Expression engine tests
│   └── prana_test.exs         # 📋 Basic module test
└── mix.exs                    # Project configuration
```

## Updated Implementation Priority

### Phase 1: Foundation (✅ COMPLETED)
1. [x] Data structures (Workflow, Node, Connection, etc.)
2. [x] Core behaviors (Integration, Middleware)
3. [x] Integration registry (simplified)
4. [x] Middleware system
5. [x] Expression engine (path-based expressions)

### Phase 2: WorkflowCompiler + Node Execution (✅ COMPLETED)
1. [x] WorkflowCompiler (renamed from ExecutionPlanner for accuracy)
2. [x] Workflow compilation into ExecutionGraphs with optimization
3. [x] Node executor with expression engine integration
4. [x] Action invocation via MFA with comprehensive error handling
5. [x] Context management and result storage
6. [x] Comprehensive test coverage (100+ scenarios)
7. [x] Clean public APIs with accurate naming

### Phase 3: Graph Execution (🚧 CURRENT PRIORITY)
1. [✓] Graph executor basic structure (orchestrate workflow execution)
2. [✓] WorkflowCompiler integration for ExecutionGraph consumption
3. [✓] Parallel node execution coordination framework
4. [✓] Port-based data routing between nodes
5. [✓] Middleware event emission during execution
6. [ ] **Complete workflow completion detection**
7. [ ] **End-to-end workflow execution testing**

### Phase 4: Built-in Integrations
1. [ ] HTTP integration
2. [ ] Transform integration
3. [ ] Logic integration
4. [ ] Log integration
5. [ ] Error handling and resilience components

### Phase 5: Main API & Builder
1. [ ] Main API module (`Prana`)
2. [ ] Workflow builder with fluent interface
3. [ ] Integration registration helpers
4. [ ] Configuration management

### Phase 6: Development Tools & Polish
1. [ ] Validation tools
2. [ ] Testing helpers
3. [ ] Development utilities
4. [ ] Example workflows
5. [ ] Wait integration
6. [ ] Application supervision

## Recent Progress (June 21, 2025)

### ✅ Major Milestone: Node Executor Complete
- **Production Ready**: Node Executor with comprehensive test coverage
- **Expression Integration**: Full integration with ExpressionEngine for input preparation
- **Error Handling**: Structured error maps with JSON serialization
- **Context Management**: Results stored under node custom_id for flexible access
- **Action Support**: Multiple return formats (explicit/default ports)
- **Bug Fix**: NodeExecution.fail/2 now properly sets output_port = nil

### ✅ Major Milestone: Middleware System Complete
- **Comprehensive Test Coverage**: 100+ test scenarios covering all middleware functionality
- **Core Features Tested**: Pipeline execution, event handling, data transformation
- **Error Resilience Tested**: Middleware failures, recovery, graceful degradation
- **Integration Scenarios**: Realistic workflow simulation with multiple middleware
- **Edge Cases Covered**: Complex data structures, long middleware chains
- **Warning-Free Code**: Fixed all unused variable warnings

### 🎯 Immediate Next Steps
1. **Complete GraphExecutor** - Finish workflow completion detection logic
2. **End-to-end testing** - Create comprehensive workflow execution tests  
3. **Error handling refinement** - Handle edge cases in execution flow
4. **Performance optimization** - Optimize parallel execution coordination
5. **Integration validation** - Ensure WorkflowCompiler + GraphExecutor work seamlessly

### 📊 Progress Summary
- **Phase 1**: 100% Complete (Foundation)
- **Phase 2**: 100% Complete (WorkflowCompiler + Node Execution)
- **Phase 3**: ~85% Complete (GraphExecutor structure done, needs completion testing)
- **Testing**: Comprehensive coverage for completed phases
- **Overall**: ~70% Complete (2.85 of 4 core phases)

## Key Achievements

### ✅ Completed Simplifications
- **Removed Storage Adapters**: Replaced with middleware for application control
- **Removed Hook System**: Middleware provides better composability
- **Simplified Integration Registry**: No complex validation/normalization
- **Struct-Based Design**: Type safety with compile-time checking
- **Single Integration Registration**: Only module-based, no map definitions

### 🎯 Current Focus Areas
- **Graph Executor**: Workflow traversal and parallel execution coordination
- **Port-Based Routing**: Data flow between nodes based on output ports
- **Middleware Integration**: Emit lifecycle events during execution
- **End-to-End Testing**: Complete workflow execution scenarios

### 📋 Deferred to Applications
- **Persistence**: Applications handle via middleware
- **External Coordination**: Applications manage via middleware
- **Health Monitoring**: Basic registry health + application middleware
- **Configuration Management**: Simple config + application-specific logic

## Design Validation

The Node Executor completion validates key design decisions:
1. **Expression Engine Integration**: Seamless input preparation with dynamic data access
2. **MFA Action Pattern**: Clean action invocation with proper error handling
3. **Structured Error Handling**: JSON-serializable errors for application persistence
4. **Port-Based Design**: Explicit output ports for flexible routing
5. **Context Management**: Flexible storage under custom_id for graph coordination

The foundation is solid and ready for Graph Executor implementation, which will bring together all completed components into a working workflow execution engine.
