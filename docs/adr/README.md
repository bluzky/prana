# Architecture Decision Records (ADRs)

This directory contains Architecture Decision Records for the Prana workflow automation platform.

## ADR Format

We use the format proposed by Michael Nygard in his article ["Documenting Architecture Decisions"](http://thinkrelevance.com/blog/2011/11/15/documenting-architecture-decisions).

Each ADR includes:
- **Status**: Proposed, Accepted, Deprecated, Superseded
- **Context**: The issue motivating this decision
- **Decision**: The change we're proposing or have agreed to implement
- **Consequences**: What becomes easier or more difficult to do because of this change

## ADR List

| ADR | Title | Status | Date |
|-----|-------|--------|------|
| [001](./001-branch-following-execution.md) | Branch-Following Execution Strategy | Accepted | 2025-07-05 |
| [002](./002-enhanced-merge-node-multiple-inputs.md) | Enhanced Merge Node with Multiple Named Input Ports | Proposed | 2025-07-05 |
| [003](./003-unified-suspension-resume.md) | Unified Suspension/Resume Mechanism for Async Coordination | Proposed | 2025-07-05 |
| [004](./004-middleware-system.md) | Middleware System for Workflow Lifecycle Events | Accepted | 2025-07-05 |
| [006](./006-loop-integration-design.md) | Loop Integration Design | Proposed | 2025-07-05 |

## Creating New ADRs

1. Copy the template from an existing ADR
2. Increment the number (e.g., 002, 003, etc.)
3. Fill in the content following the established format
4. Update this README with the new ADR entry
5. Submit for review via pull request

## Related Documentation

- [Graph Executor Requirements](../graph_executor_requirement.md)
- [Graph Execution Patterns](../graph_execution%20pattern.md)
- [Execution Planning Updates](../execution_planning_update.md)