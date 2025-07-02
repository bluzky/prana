# Webhook System Implementation Plan

**Version**: 1.1  
**Date**: 2025-01-02  
**Updated**: 2025-07-02  
**Related ADR**: ADR-005 Webhook System Architecture  
**Target Completion**: Phase 4.2

## Current Status: Ready for Implementation

**Prerequisites Met**:
- ✅ Core execution engine complete (Phases 3.1-3.3, 4.1)
- ✅ Sub-workflow orchestration complete with suspension/resume
- ✅ Middleware system with event handling
- ✅ Wait integration foundation implemented
- ✅ ADR-005 architectural decisions finalized

**Implementation Focus**: Two-tier webhook system with trigger URLs (workflow-scoped) and resume URLs (execution-scoped) following n8n patterns.

## Overview

Implementation plan for the two-tier webhook system defined in ADR-005. This plan covers the core library enhancements needed to support webhook-based workflow triggers and execution resume patterns.

---

## Phase 1: Core Webhook Infrastructure (High Priority)

### Task 1: WebhookRegistry GenServer Module

**Objective**: Create central webhook routing and state management system

#### Implementation Tasks
- [ ] **webhook-1**: Create `Prana.WebhookRegistry` GenServer module with state management
- [ ] **webhook-2**: Implement webhook URL pattern parsing for trigger and resume patterns
- [ ] **webhook-3**: Add webhook lifecycle state management (pending → active → consumed/expired)

#### Technical Details
- GenServer with ETS tables for fast webhook lookups
- URL patterns: `/webhook/workflow/trigger/:workflow_id` and `/webhook/workflow/resume/:resume_id`
- State transitions with proper validation and error handling

#### Acceptance Criteria
- [ ] **AC-WH-1.1**: Parse webhook URLs correctly for trigger (`/webhook/workflow/trigger/:workflow_id`) and resume (`/webhook/workflow/resume/:resume_id`) patterns
- [ ] **AC-WH-1.2**: Generate unique resume webhook IDs following pattern `webhook_{execution_id}_{node_id}_{random}`
- [ ] **AC-WH-1.3**: Route incoming webhooks to appropriate handlers with state validation
- [ ] **AC-WH-1.4**: Handle invalid webhook URLs and invalid states with clear error messages
- [ ] **AC-WH-1.5**: Support configurable base URL for full webhook URL generation
- [ ] **AC-WH-1.6**: Implement webhook lifecycle states (pending, active, consumed, expired)
- [ ] **AC-WH-1.7**: Generate resume URLs at execution start for expression availability

### Task 2: Webhook Data Structures

**Objective**: Define core data structures following ADR-005 specifications

#### Implementation Tasks
- [ ] **webhook-4**: Create Prana.WebhookRegistration struct with all required fields
- [ ] **webhook-5**: Add resume_url field to ExecutionContext for expression access
- [ ] **webhook-6**: Implement resume URL generation at execution start

#### Technical Details
- WebhookRegistration with resume_id, execution_id, node_id, status, timestamps
- ExecutionContext enhanced with resume_url for `$execution.resume_url` expressions
- Resume URL generation using pattern `webhook_{execution_id}_{node_id}_{random}`

#### Acceptance Criteria
- [ ] **AC-WH-1.8**: WebhookRegistration contains all required fields (resume_id, execution_id, node_id, status, created_at, expires_at, webhook_config)
- [ ] **AC-WH-1.9**: WebhookConfig supports HTTP method, timeout, response validation, and custom headers
- [ ] **AC-WH-1.10**: Suspension data includes complete webhook registration data for application persistence
- [ ] **AC-WH-1.11**: ExecutionContext.resume_url available for expression evaluation throughout workflow
- [ ] **AC-WH-1.12**: All webhook structs have proper type specifications and validation

---

## Phase 2: Integration (Medium Priority)

### Task 7: Webhook Wait Action

**Objective**: Add webhook waiting capability to Wait integration

#### Implementation Tasks
- [ ] **webhook-7**: Add webhook wait action to Prana.Integrations.Wait

#### Technical Details
- Implement `wait_webhook/1` function with webhook activation logic
- Transition webhooks from pending to active state with timeout handling
- Integration with WebhookRegistry for state management
- Proper suspension data generation for GraphExecutor

#### Acceptance Criteria
- [ ] **AC-WH-2.1**: `wait_webhook/1` activates pre-existing webhook registration and returns suspension data
- [ ] **AC-WH-2.2**: Activated webhooks transition from pending to active state with proper expiry
- [ ] **AC-WH-2.3**: Support configurable webhook timeout with default of 24 hours
- [ ] **AC-WH-2.4**: Return suspension data with complete webhook registration for application persistence
- [ ] **AC-WH-2.5**: Validate execution context contains resume_url and current node_id
- [ ] **AC-WH-2.6**: Handle webhook activation failures gracefully with clear error messages

### Task 8: GraphExecutor Webhook Integration

**Objective**: Integrate webhook suspensions with GraphExecutor

#### Implementation Tasks
- [ ] **webhook-8**: Integrate webhook suspensions with GraphExecutor
- [ ] **webhook-9**: Add webhook data to middleware events for application persistence
- [ ] **webhook-10**: Implement webhook cleanup on execution completion

#### Technical Details
- Handle `{:suspend, :webhook, registration_data}` returns in GraphExecutor
- Emit `:node_suspended` middleware events with complete webhook data
- Integrate with existing `resume_workflow/4` API for webhook resume
- Automatic webhook cleanup on execution completion/failure

#### Acceptance Criteria
- [ ] **AC-WH-3.1**: GraphExecutor handles `{:suspend, :webhook, registration_data}` with proper state management
- [ ] **AC-WH-3.2**: Emit `:node_suspended` middleware event with complete webhook registration data
- [ ] **AC-WH-3.3**: Webhook resume integrates seamlessly with existing `resume_workflow/4` API
- [ ] **AC-WH-3.4**: WebhookRegistry.handle_resume_webhook/2 validates state and returns resume data
- [ ] **AC-WH-3.5**: Webhook state transitions (active → consumed/expired) handled correctly
- [ ] **AC-WH-3.6**: Webhook cleanup on execution completion prevents memory leaks

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
- [ ] **webhook-12**: Create webhook system documentation and integration examples

#### Technical Details
- Webhook system usage guide covering two-tier architecture
- Complete workflow examples (email approval, user registration)
- Phoenix application integration patterns with controller examples
- Webhook troubleshooting guide and API reference
- n8n compatibility patterns and expression usage examples

#### Acceptance Criteria
- [ ] **AC-WH-5.1**: 100% test coverage for WebhookRegistry module with all state transitions
- [ ] **AC-WH-5.2**: All webhook wait action scenarios tested including timeouts and failures
- [ ] **AC-WH-5.3**: GraphExecutor webhook suspension/resume integration thoroughly tested
- [ ] **AC-WH-5.4**: Webhook URL generation, parsing, and validation edge cases covered
- [ ] **AC-WH-5.5**: End-to-end webhook workflows execute successfully with proper cleanup
- [ ] **AC-WH-5.6**: Complete documentation with usage examples and Phoenix integration patterns

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
- [ ] Existing Wait integration functionality preserved
- [ ] No breaking changes to public APIs
- [ ] Backward compatibility for existing suspension patterns
- [ ] Integration registry compatibility maintained

---

## Dependencies and Prerequisites

### Required
- [ ] ADR-005 Webhook System Architecture approved
- [ ] Current Wait integration implementation (Phase 4.1 complete)
- [ ] GraphExecutor suspension/resume mechanism (ADR-003)
- [ ] Integration registry system

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
7. **webhook-7**: Add webhook wait action to Wait integration
8. **webhook-8**: Integrate webhook suspensions with GraphExecutor
9. **webhook-9**: Add webhook data to middleware events
10. **webhook-10**: Implement webhook cleanup

### Medium-Low Priority Tasks (Phase 3)
11. **webhook-11**: Add comprehensive unit tests
12. **webhook-12**: Create documentation and examples

## Success Metrics

### Functional
- [ ] All 12 implementation tasks completed
- [ ] 100% test coverage for webhook functionality
- [ ] Zero breaking changes to existing APIs
- [ ] Complete documentation with Phoenix integration examples

### Performance
- [ ] < 1ms webhook URL generation and routing
- [ ] < 5ms webhook suspension overhead
- [ ] Memory-efficient webhook registry with proper cleanup

---

**Next Review**: Weekly during implementation  
**Escalation**: Report blockers immediately to architecture team  
**Completion Target**: End of Phase 4.2