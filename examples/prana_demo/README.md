# Prana Demo

Demonstrates Prana workflow patterns with ETS storage - sequential, conditional, loops, sub-workflows, and wait operations.

## What

**5 Workflow Patterns:**
- **Sequential** - `trigger → set_data → process`
- **Conditional** - `trigger → data → age_check → (adult OR minor)`  
- **Loop** - `trigger → attempt → retry_check → (retry OR success)`
- **Sub-workflow** - `trigger → execute_sub_workflow → process_result` (sync/async/fire-and-forget)
- **Wait** - `trigger → data → wait_2_seconds → continue`

**Components:**
- `WorkflowRunner` - Execution engine with suspension handling
- `ETSStorage` - In-memory persistence 
- `DemoWorkflow` - All pattern implementations
- Expression engine - `$input.field` and `$nodes.node_id.output`

## How

```bash
cd examples/prana_demo
mix deps.get && mix compile
iex -S mix
```

**Run all:**
```elixir
PranaDemo.run_all_demos()
```

**Individual patterns:**
```elixir
PranaDemo.run_simple_demo()        # Sequential
PranaDemo.run_conditional_demo()   # If/else branching  
PranaDemo.run_loop_demo()          # Retry patterns
PranaDemo.run_sub_workflow_demo()  # Sub-workflow coordination
PranaDemo.run_wait_demo()          # Timer operations
```

**Sub-workflow modes:**
```elixir
PranaDemo.run_all_sub_workflow_demos()  # sync, async, fire-and-forget
```

**Key Point:** GraphExecutor always returns `:suspend` for sub-workflows - applications handle execution mode in suspension handler.

Uses ETS for demo - replace with database for production.