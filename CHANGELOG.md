# Changelog


## [0.2.0] - 2025-06-21

### Added
- **Node Executor (Production Ready)**: Complete individual node execution engine
  - Expression-based input preparation using ExpressionEngine
  - MFA action invocation with comprehensive error handling
  - Multiple return format support (explicit/default ports)
  - Context management storing results under node `custom_id`
  - Structured error maps with JSON serialization
  - Comprehensive exception handling (rescue, catch :exit, catch :throw)
  - 100+ test scenarios covering all edge cases
- **Node Executor Functions**:
  - `execute_node/3` - Main node execution orchestration
  - `prepare_input/2` - Expression evaluation using ExpressionEngine
  - `get_action/1` - Action lookup from IntegrationRegistry
  - `invoke_action/2` - MFA-based action invocation
  - `process_action_result/2` - Output port determination and validation
  - `update_context/3` - Context state management
- **Action Return Format Support**:
  - Explicit port format: `{:ok, data, "success"}`, `{:error, error, "custom_error"}`
  - Default port format: `{:ok, data}`, `{:error, error}`
- **Comprehensive Test Coverage**: Node Executor test suite with scenarios for:
  - Successful node execution
  - Expression evaluation (simple, complex, wildcards, filtering)
  - Error handling (action errors, exceptions, invalid ports)
  - Context management and updates
  - Integration registry integration
  - Edge cases and error conditions

### Fixed
- **NodeExecution.fail/2**: Fixed to properly set `output_port = nil` for failed executions
  - **Issue**: Test expected `output_port = nil` but function was setting default error port
  - **Root Cause**: Function had optional `error_port` parameter that was setting `output_port`
  - **Solution**: Removed optional parameter, always set `output_port = nil` for failures
  - **Rationale**: Failed nodes don't produce valid output; error routing handled at graph level

### Changed
- **Project Status**: Phase 2 (Node Execution) marked as complete
- **Implementation Priority**: Graph Executor is now immediate next priority
- **Documentation**: Updated implementation summary and plan to reflect Node Executor completion

## [0.1.0] - 2025-06-20

### Added
- **Expression Engine (Complete)**: Path-based expression evaluation system
  - `extract/2` - Main expression extraction function
  - `process_map/2` - Process maps with expressions recursively
  - Support for simple field access: `$input.email`, `$nodes.api.response`
  - Array access: `$input.users[0].name`
  - Wildcard extraction: `$input.users.*.name` (returns arrays)
  - Array filtering: `$input.users.{role: "admin"}.email` (returns arrays)
  - Flexible context structure (any map)
  - Comprehensive error handling and validation
  - Extensive test coverage (100+ test cases)

- **Core Data Structures**: Complete struct-based design
  - `Prana.Workflow` - Workflow definition with nodes and connections
  - `Prana.Node` - Individual node with type, integration, action, config
  - `Prana.Connection` - Connection between nodes with ports and conditions
  - `Prana.Condition` - Connection routing conditions
  - `Prana.Integration` - Integration struct with actions
  - `Prana.Action` - Action struct with metadata
  - `Prana.Execution` - Workflow execution instance
  - `Prana.NodeExecution` - Individual node execution state
  - `Prana.ExecutionContext` - Shared execution context
  - `Prana.ErrorHandling` - Error handling configuration
  - `Prana.RetryPolicy` - Retry policy configuration

- **Behavior Definitions**: Clean contracts for extensibility
  - `Prana.Behaviour.Integration` - Integration contract with `definition/0` callback
  - `Prana.Behaviour.Middleware` - Event handling contract with `call/3` callback
  - Support for composable middleware pipeline
  - Lifecycle events: execution_started, execution_completed, node_failed, etc.

- **Integration Registry**: Runtime integration management
  - `Prana.IntegrationRegistry` - GenServer for managing integrations
  - Runtime integration registration (module-based only)
  - Action lookup and retrieval
  - Integration listing and discovery
  - Basic health checking and statistics

- **Middleware System**: Event-driven lifecycle handling
  - `Prana.Middleware` - Pipeline execution engine
  - Sequential middleware execution with error handling
  - Runtime configuration support
  - Statistics and monitoring

- **Core Functions**:
  - Workflow management: `new/2`, `from_map/1`, `get_entry_nodes/1`
  - Node operations: `get_node_by_key/2`, `add_node/2`, connection helpers
  - Validation: `valid?/1` for workflows and nodes
  - Registry operations: `register_integration/1`, `get_action/2`
  - Middleware: `call/2`, runtime management functions

---

*This changelog tracks all notable changes to the Prana Core Library.*
