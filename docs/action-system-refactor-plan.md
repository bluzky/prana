# Prana Action System Refactor & Improvement Plan

## Overview
Complete architectural refactor to implement a clean action behavior system with structured suspension handling, eliminating MFA patterns and webhook-specific hardcoding.

## Phase 1: Core Architecture Foundation

### 1.1 Action Behavior System
**Priority: Critical**
- **Create `Prana.Behaviour.Action`** with clean contract:
  ```elixir
  @callback prepare(action_config :: map(), execution_context :: ExecutionContext.t()) :: 
    {:ok, preparation_data :: map()} | {:error, reason :: term()}
  
  @callback execute(input_data :: map()) :: 
    {:ok, output, output_port} | {:suspend, type, suspend_data} | {:error, reason, output_port}
  
  @callback resume(suspend_data :: term(), resume_input :: map()) :: 
    {:ok, output} | {:error, reason}
  ```
- **Default implementation module** for actions that only need execute/2
- **Preparation data storage** in ExecutionContext: `%{node_custom_id => preparation_map}`

### 1.2 Structured Suspension System
**Priority: Critical**
- **Refactor `Prana.Execution` struct** - Remove `resume_token`, add structured fields:
  ```elixir
  suspended_node_id: String.t() | nil,
  suspension_type: suspension_type() | nil,
  suspension_data: typed_suspension_data(),
  suspended_at: DateTime.t() | nil
  ```
- **Typed suspension data** for each suspension type:
  - `webhook_suspension_data`
  - `interval_suspension_data` 
  - `schedule_suspension_data`
  - `sub_workflow_suspension_data`
- **Clean suspension API** with direct field access

### 1.3 ExecutionContext Enhancement
**Priority: High**
- **Add `preparation_data` field**: `%{node_custom_id => map()}`
- **Update context creation** to handle preparation phase
- **Expression engine support** for `$preparation.node_id.field` syntax

## Phase 2: Core System Integration

### 2.1 NodeExecutor Refactor
**Priority: Critical**
- **Replace MFA handling** with module-based action execution
- **Add preparation phase** - call `prepare/2` during node setup
- **Update suspension handling** for new structured format
- **Maintain execute/resume pattern** with enhanced data flow

### 2.2 GraphExecutor Enhancement
**Priority: Critical**
- **Workflow preparation phase** - scan all nodes, call `prepare/2` on each action
- **Context enrichment** with preparation data before execution starts
- **Structured suspension handling** - populate new Execution fields
- **Clean execution flow** with typed suspension returns

### 2.3 Integration Registry Update
**Priority: High**
- **Replace MFA action definitions** with module references
- **Update Integration struct** - remove function/args fields, use module field
- **Action loading mechanism** for module-based actions
- **Health check updates** for new action pattern

## Phase 3: Integration Migration

### 3.1 Built-in Integration Conversion
**Priority: High**
- **Manual Integration** → Module-based with Action behavior
- **Logic Integration** → Module-based (no prepare/resume needed)
- **Data Integration** → Module-based (no prepare/resume needed)  
- **Workflow Integration** → Module-based (existing resume pattern)
- **Wait Integration** → Full prepare/execute/resume with webhook support

### 3.2 Wait Integration Enhancement
**Priority: High**
- **Webhook prepare/2** - Generate resume URLs using `Prana.Webhook.generate_resume_id/1`
- **Structured suspension data** - Include resume URLs, timeout info, webhook config
- **Resume handling** - Process webhook resume data
- **Mode-specific logic** - Interval, schedule, webhook modes with proper typing

## Phase 4: Expression & Testing

### 4.1 Expression Engine Enhancement
**Priority: Medium**
- **Preparation data access** - `$preparation.node_id.resume_url` syntax
- **Context enrichment** - Include preparation data in expression evaluation
- **Backward compatibility** - Maintain existing expression patterns

### 4.2 Comprehensive Testing
**Priority: Medium**
- **Action behavior lifecycle** - prepare → execute → resume patterns
- **Structured suspension** - All suspension types with proper data
- **Integration conversion** - All built-in integrations with new pattern
- **Expression engine** - Preparation data access and resolution
- **End-to-end workflows** - Complete webhook and suspension scenarios

## Phase 5: Documentation & Examples

### 5.1 Updated Documentation
**Priority: Low**
- **Action behavior guide** - How to implement prepare/execute/resume
- **Suspension system** - New structured approach and typed data
- **Webhook integration** - Complete application integration examples
- **Migration guide** - From MFA to module-based actions

### 5.2 Application Examples
**Priority: Low**
- **Phoenix controller patterns** for webhook handling
- **Database persistence** examples for suspension data
- **Resume workflow** integration patterns
- **Error handling** best practices

## Key Architectural Improvements

### 1. **Elimination of Hardcoding**
- No webhook-specific logic in core GraphExecutor
- Generic preparation/suspension pattern for all action types
- Clean separation between library utilities and application logic

### 2. **Type Safety & Structure**
- Typed suspension data structures
- Direct field access instead of nested maps
- Compile-time behavior contracts

### 3. **Extensibility**
- Any integration can implement prepare/execute/resume
- Custom suspension types supported
- Applications control persistence and routing

### 4. **Clean APIs**
```elixir
# Before: Nested, complex
execution.resume_token.suspension_metadata.type
execution.resume_token.suspension_metadata.data.resume_url

# After: Direct, typed
execution.suspension_type # :webhook  
execution.suspension_data.resume_url # String.t()
```

## Implementation Dependencies

1. **Behavior Definition** → Core foundation for everything
2. **Execution Struct Refactor** → Required for structured suspension
3. **Context Enhancement** → Needed for preparation data
4. **GraphExecutor Changes** → Core orchestration updates  
5. **Integration Conversion** → Uses all above components
6. **Testing & Documentation** → Validates entire system

## Success Metrics

- **Zero webhook hardcoding** in core execution system
- **100% type safety** for suspension data structures  
- **Clean API** with direct field access
- **Extensible pattern** for future integrations
- **Comprehensive test coverage** for all scenarios
- **Complete webhook integration** without special-case logic

## Current Implementation Status

### ✅ Phase 1 Complete (January 2, 2025)
- **✅ Phase 1.1**: Action behavior definition and default implementation complete
  - Created `Prana.Behaviour.Action` with prepare/execute/resume contract
  - Built `Prana.Actions.SimpleAction` default implementation for simple actions
- **✅ Phase 1.2**: Execution struct refactored with structured suspension
  - Refactored `Prana.Execution` with structured suspension fields
  - Added typed suspension data structures in `Prana.Core.SuspensionData`
  - Implemented hybrid approach: structured fields + root-level resume_token for optimal querying
- **✅ Phase 1.3**: ExecutionContext cleaned up based on user feedback
  - Removed preparation_data field (handled at graph execution level)
  - Cleaned up expression context for memory optimization
  - All existing tests passing (256/256) with 100% compatibility

### ✅ Phase 2.1 Complete (January 3, 2025)
- **✅ NodeExecutor Action Behavior Integration**: Complete conversion from MFA to Action behavior pattern
  - Updated `NodeExecutor.invoke_action/2` to call `module.execute/1` instead of MFA pattern
  - Simplified Action behavior to `execute/1` signature (removed preparation_data parameter)
  - Added comprehensive error handling for action execution
- **✅ All Built-in Integrations Converted**: Complete migration to Action behavior modules
  - **Manual Integration**: Created `TriggerAction`, `ProcessAdultAction`, `ProcessMinorAction` modules
  - **Logic Integration**: Created `IfConditionAction` and `SwitchAction` modules with expression evaluation
  - **Workflow Integration**: Created `ExecuteWorkflowAction` module with suspension support
  - All integrations use proper 3-tuple return format: `{:ok, data, output_port}` or `{:error, data, "error"}`
- **✅ Expression Engine Enhancement**: Preserved `$` prefix in context structure
  - Expression engine maintains `$` prefix for context keys (`$input`, `$nodes`, `$variables`)
  - Updated NodeExecutor to build proper context structure with `$`-prefixed keys
  - All tests updated to use correct context structure
- **✅ Comprehensive Testing**: All 255 tests passing with new Action behavior pattern
  - Updated expression engine tests with `$`-prefixed context data
  - Fixed conditional branching tests to use proper context structure
  - Fixed workflow tests with correct module namespace and return formats
  - All integration tests working with new Action behavior modules

### ✅ Foundation Already Complete
- **Prana.Webhook utilities module** - Pure utility functions for webhook operations
- **Comprehensive webhook tests** - 38 passing tests covering all webhook functionality
- **Wait integration foundation** - Basic wait action with interval, schedule, webhook modes

### 🎯 Next Priority Implementation Order

1. **✅ Phase 1**: Core Architecture Foundation - **COMPLETE**
2. **✅ Phase 2.1**: NodeExecutor & Integration Conversion - **COMPLETE**
3. **Phase 2.2**: Enhance GraphExecutor with preparation phase and structured suspension
4. **Phase 2.3**: Update Integration Registry for module-based actions
5. **Phase 3.2**: Wait Integration Enhancement with webhook prepare/resume
6. **Phase 4**: Expression engine enhancement and comprehensive testing

## Migration Strategy

This refactor transforms Prana from an MFA-based system with hardcoded webhook logic into a clean, extensible, behavior-driven architecture with proper type safety and separation of concerns.

### Key Design Principles
- **Generic patterns over specific implementations**
- **Type safety and compile-time contracts**
- **Clean separation of concerns**
- **Extensibility for future integrations**
- **Backward compatibility eliminated for cleaner design**

The end result will be a robust, maintainable workflow execution system that can handle complex suspension/resume patterns without hardcoded logic for specific integration types.