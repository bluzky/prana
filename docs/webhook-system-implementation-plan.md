# Webhook System Implementation Plan

**Version**: 1.2  
**Date**: 2025-01-02  
**Updated**: 2025-07-02  
**Related ADR**: ADR-005 Webhook System Architecture  
**Target Completion**: Phase 4.2

## Current Status: Ready for Implementation

**Prerequisites Met**:
- ✅ Core execution engine complete (Phases 3.1-3.3, 4.1)
- ✅ Sub-workflow orchestration complete with suspension/resume
- ✅ Middleware system with event handling
- ✅ Wait integration foundation implemented with unified wait action
- ✅ ADR-005 architectural decisions finalized
- ✅ Wait/Resume integration guide created with complete implementation examples

**Implementation Focus**: Distributed webhook system where Prana provides utilities and applications handle persistence/routing.

**Recent Progress**:
- ✅ **Task 7 Complete**: Webhook wait action implemented in Wait integration with unified 3-mode API
- ✅ **Task 12 Complete**: Comprehensive integration guide created with Phoenix examples and production patterns
- 🎯 **Next Priority**: Core webhook utilities (Tasks 1-6) for resume URL generation and expression support

## Overview

Implementation plan for the two-tier webhook system defined in ADR-005. This plan covers the core library enhancements needed to support webhook-based workflow triggers and execution resume patterns.

---

## Phase 1: Core Webhook Infrastructure (High Priority)

### Task 1: Webhook Utilities Module

**Objective**: Create webhook utility functions and data structures (no centralized registry)

#### Implementation Tasks
- [ ] **webhook-1**: Create `Prana.Webhook` utilities module (no centralized state)
- [ ] **webhook-2**: Implement webhook URL pattern parsing and building functions
- [ ] **webhook-3**: Add webhook validation and data creation helpers

#### Technical Details
- Pure functions for webhook ID generation and URL building
- URL patterns: `/webhook/workflow/trigger/:workflow_id` and `/webhook/workflow/resume/:resume_id`
- Utilities for webhook validation and data structure creation
- No centralized state - applications handle persistence

#### Acceptance Criteria
- [ ] **AC-WH-1.1**: Parse webhook URLs correctly for trigger (`/webhook/workflow/trigger/:workflow_id`) and resume (`/webhook/workflow/resume/:resume_id`) patterns
- [ ] **AC-WH-1.2**: Generate unique resume webhook IDs following pattern `webhook_{execution_id}_{node_id}_{random}`
- [ ] **AC-WH-1.3**: Route incoming webhooks to appropriate handlers with state validation
- [ ] **AC-WH-1.4**: Handle invalid webhook URLs and invalid states with clear error messages
- [ ] **AC-WH-1.5**: Support configurable base URL for full webhook URL generation
- [ ] **AC-WH-1.6**: Implement webhook lifecycle states (pending, active, consumed, expired)
- [ ] **AC-WH-1.7**: Generate resume URLs at execution start for expression availability

### Task 2: Webhook Data Structures and Context

**Objective**: Define core data structures and execution context enhancements

#### Implementation Tasks
- [ ] **webhook-4**: Create Prana.WebhookRegistration struct with all required fields
- [ ] **webhook-5**: Add resume_urls map to ExecutionContext for node-specific expression access
- [ ] **webhook-6**: Implement workflow scanning and resume URL generation at execution start

#### Technical Details
- WebhookRegistration with resume_id, execution_id, node_id, status, timestamps
- ExecutionContext enhanced with `resume_urls: %{"node_id" => "webhook_url"}` map
- Workflow scanning to identify wait nodes and pre-generate their resume URLs
- Expression support for `$execution.{node_id}.resume_url` syntax

#### Acceptance Criteria
- [ ] **AC-WH-1.8**: WebhookRegistration contains all required fields (resume_id, execution_id, node_id, status, created_at, expires_at, webhook_config)
- [ ] **AC-WH-1.9**: ExecutionContext.resume_urls contains map of node_id → webhook_url for all wait nodes
- [ ] **AC-WH-1.10**: Workflow scanning correctly identifies all wait nodes at execution start
- [ ] **AC-WH-1.11**: Expression engine supports `$execution.{node_id}.resume_url` syntax
- [ ] **AC-WH-1.12**: Resume URLs generated with pattern `webhook_{execution_id}_{node_id}_{random}`
- [ ] **AC-WH-1.13**: All webhook structs have proper type specifications and validation

---

## Phase 2: Integration (Medium Priority)

### Task 7: Webhook Wait Action

**Objective**: Add webhook waiting capability to Wait integration

#### Implementation Tasks
- [x] **webhook-7**: Add webhook wait action to Prana.Integrations.Wait

#### Technical Details
- ✅ **COMPLETED**: Implemented `wait_webhook/1` function with webhook activation logic
- ✅ **COMPLETED**: Webhook timeout handling with configurable `timeout_hours` parameter
- ✅ **COMPLETED**: Proper suspension data generation for GraphExecutor
- ✅ **COMPLETED**: Unified wait action with three modes: interval, schedule, webhook
- ✅ **COMPLETED**: Comprehensive test coverage with 25 test scenarios

#### Acceptance Criteria
- [x] **AC-WH-2.1**: `wait_webhook/1` activates pre-existing webhook registration and returns suspension data
- [x] **AC-WH-2.2**: Activated webhooks transition from pending to active state with proper expiry
- [x] **AC-WH-2.3**: Support configurable webhook timeout with default of 24 hours
- [x] **AC-WH-2.4**: Return suspension data with complete webhook registration for application persistence
- [x] **AC-WH-2.5**: Validate execution context contains resume_url and current node_id
- [x] **AC-WH-2.6**: Handle webhook activation failures gracefully with clear error messages

### Task 8: GraphExecutor Webhook Integration

**Objective**: Integrate webhook suspensions with GraphExecutor execution results

#### Implementation Tasks
- [ ] **webhook-8**: Return webhook data in GraphExecutor execution results (not middleware)
- [ ] **webhook-9**: Handle webhook suspension return tuples in GraphExecutor
- [ ] **webhook-10**: Integrate webhook resume with existing `resume_workflow/4` API

#### Technical Details
- Handle `{:suspend, :webhook, registration_data}` returns in GraphExecutor
- Return webhook data directly in execution results for application storage
- Integrate with existing `resume_workflow/4` API for webhook resume
- No middleware events - webhook data flows through normal execution results

#### Acceptance Criteria
- [ ] **AC-WH-3.1**: GraphExecutor returns webhook data in execution results when suspended
- [ ] **AC-WH-3.2**: Webhook suspension tuples handled correctly in execution flow
- [ ] **AC-WH-3.3**: Webhook resume integrates seamlessly with existing `resume_workflow/4` API
- [ ] **AC-WH-3.4**: Applications receive complete webhook data for persistence and routing
- [ ] **AC-WH-3.5**: No centralized state in Prana - all persistence handled by applications

---

## Phase 3: Testing & Documentation (Medium-Low Priority)

### Task 11: Comprehensive Testing

**Objective**: Add comprehensive unit test coverage for webhook functionality

#### Implementation Tasks
- [ ] **webhook-11**: Add comprehensive unit tests for webhook functionality

#### Technical Details
- Test WebhookRegistry state management and lifecycle transitions
- Test Wait integration webhook actions and suspension handling
- Test GraphExecutor webhook integration and middleware events
- Test webhook URL generation, parsing, and validation
- End-to-end webhook workflow testing

### Task 12: Documentation and Examples

**Objective**: Create comprehensive documentation and integration examples

#### Implementation Tasks
- [x] **webhook-12**: Create webhook system documentation and integration examples

#### Technical Details
- ✅ **COMPLETED**: Wait/Resume integration guide with comprehensive implementation examples
- ✅ **COMPLETED**: Complete workflow examples (approval, payment confirmation, scheduling)
- ✅ **COMPLETED**: Phoenix application integration patterns with controller examples
- ✅ **COMPLETED**: Webhook storage implementation patterns (ETS and database)
- ✅ **COMPLETED**: Error handling patterns and production considerations
- ✅ **COMPLETED**: Advanced patterns for multiple wait nodes and complex workflows

#### Acceptance Criteria
- [ ] **AC-WH-5.1**: 100% test coverage for WebhookRegistry module with all state transitions
- [x] **AC-WH-5.2**: All webhook wait action scenarios tested including timeouts and failures
- [ ] **AC-WH-5.3**: GraphExecutor webhook suspension/resume integration thoroughly tested
- [ ] **AC-WH-5.4**: Webhook URL generation, parsing, and validation edge cases covered
- [ ] **AC-WH-5.5**: End-to-end webhook workflows execute successfully with proper cleanup
- [x] **AC-WH-5.6**: Complete documentation with usage examples and Phoenix integration patterns

---

## Quality Gates

### Code Quality
- [ ] All new code passes `mix credo` analysis
- [ ] All new code formatted with `mix format`
- [ ] Type specifications added to all public functions
- [ ] Documentation added to all public modules and functions

### Performance
- [ ] Webhook URL generation < 1ms
- [ ] Webhook routing lookup < 1ms
- [ ] No memory leaks in webhook registry
- [ ] Webhook suspension adds < 5ms to execution time

### Compatibility
- [x] Existing Wait integration functionality preserved
- [x] No breaking changes to public APIs
- [x] Backward compatibility for existing suspension patterns
- [x] Integration registry compatibility maintained

---

## Dependencies and Prerequisites

### Required
- [x] ADR-005 Webhook System Architecture approved
- [x] Current Wait integration implementation (Phase 4.1 complete)
- [x] GraphExecutor suspension/resume mechanism (ADR-003)
- [x] Integration registry system

### Optional
- [ ] Application webhook persistence layer (for full functionality)
- [ ] HTTP server for webhook endpoint handling (application responsibility)
- [ ] Database schema for webhook storage (application responsibility)

---

## Risk Management

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Complex webhook URL collision | High | Low | Use UUIDs in resume_id generation |
| Performance impact on GraphExecutor | Medium | Medium | Lazy webhook registration, optimize lookups |
| Breaking changes to existing APIs | High | Low | Maintain backward compatibility, thorough testing |
| Application integration complexity | Medium | Medium | Clear documentation, examples, helper functions |

---

## Task Summary

### High Priority Tasks (Phase 1)
1. **webhook-1**: Create Prana.WebhookRegistry GenServer module
2. **webhook-2**: Implement webhook URL pattern parsing
3. **webhook-3**: Add webhook lifecycle state management
4. **webhook-4**: Create Prana.WebhookRegistration struct
5. **webhook-5**: Add resume_url to ExecutionContext
6. **webhook-6**: Implement resume URL generation

### Medium Priority Tasks (Phase 2)
7. **webhook-7**: ✅ **COMPLETED** - Add webhook wait action to Wait integration
8. **webhook-8**: Integrate webhook suspensions with GraphExecutor
9. **webhook-9**: Add webhook data to middleware events
10. **webhook-10**: Implement webhook cleanup

### Medium-Low Priority Tasks (Phase 3)
11. **webhook-11**: Add comprehensive unit tests
12. **webhook-12**: ✅ **COMPLETED** - Create documentation and examples

## Success Metrics

### Functional
- [ ] All 12 implementation tasks completed (2 of 12 complete)
- [x] 100% test coverage for webhook wait action functionality  
- [x] Zero breaking changes to existing APIs
- [x] Complete documentation with Phoenix integration examples

### Performance
- [ ] < 1ms webhook URL generation and routing
- [ ] < 5ms webhook suspension overhead
- [ ] Memory-efficient webhook registry with proper cleanup

---

**Next Review**: Weekly during implementation  
**Escalation**: Report blockers immediately to architecture team  
**Completion Target**: End of Phase 4.2