# Prana Demo

A practical demonstration of Prana workflow automation platform showing real-world workflow patterns and execution modes.

## What This Demo Shows

- **5 Workflow Patterns:** Sequential, conditional branching, loops/retry, sub-workflows, and wait operations
- **Expression Engine:** Dynamic data transformation with `$input` and `$nodes` references
- **Suspension/Resume:** Long-running workflows with timers and sub-workflow coordination
- **Integration Types:** Manual, Logic, Data, Workflow, Wait integrations in action

## Quick Start

```bash
cd examples/prana_demo
mix deps.get
mix compile
iex -S mix
```

**Run all demos:**
```elixir
PranaDemo.run_all_demos()
```

**Individual patterns:**
```elixir
PranaDemo.run_simple_demo()        # Sequential workflow
PranaDemo.run_conditional_demo()   # If/else branching  
PranaDemo.run_loop_demo()          # Retry patterns
PranaDemo.run_sub_workflow_demo()  # Sub-workflow coordination
PranaDemo.run_wait_demo()          # Timer operations
```

## Demo Patterns

**Simple Sequential:** `trigger → transform_data → process → end`
- Basic workflow with data transformation using expressions

**Conditional Logic:** `trigger → data → age_check → (adult_path OR minor_path)`
- Branching based on runtime conditions (`age >= 18`)

**Loop/Retry:** `trigger → attempt → check_retry → (retry OR success)`
- Retry logic with attempt counting and max limits

**Sub-workflows:** `trigger → execute_sub_workflow → process_result`
- Three execution modes: sync, async, fire-and-forget

**Wait Operations:** `trigger → data → wait_2_seconds → continue`
- Timer-based workflow suspension and resume

## Architecture

- **WorkflowRunner:** Application-level execution engine with suspension handling
- **ETSStorage:** In-memory persistence for executions and workflows  
- **DemoWorkflow:** All workflow pattern implementations
- **Expression Engine:** `$input.field` and `$nodes.node_id.output` references

This demo uses simplified ETS storage - replace with database storage for production use.