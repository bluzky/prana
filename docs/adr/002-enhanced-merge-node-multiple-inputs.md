# ADR-002: Enhanced Merge Node with Multiple Named Input Ports

## Status
Proposed

## Context
The current merge action in Prana's Logic integration (`lib/prana/integrations/logic.ex`) will be moved to a new dedicated Data integration (`lib/prana/integrations/data.ex`) for data manipulation operations. The current implementation has limitations that prevent effective diamond pattern coordination in workflows:

- **Single input port**: Only accepts a list of data through one `input` port
- **No input differentiation**: Cannot distinguish which data came from which workflow branch
- **Basic strategies**: Limited to `combine_objects`, `combine_arrays`, and `last_wins`
- **Manual data collection**: Requires external coordination to gather data from multiple predecessor nodes

This limits Prana's ability to implement fork-join patterns where data from multiple parallel branches needs to be combined intelligently.

## Decision
We will create a new Data integration and move the merge action from Logic integration to this new dedicated module. The enhanced merge node will support multiple named input ports with three fundamental merge strategies:

### 1. Multiple Named Input Ports
- Replace single `input` port with user-configurable named ports
- Users define input port names: `["user_data", "payment_info", "preferences"]`
- Each port receives data from different workflow execution paths

### 2. Enhanced Input Structure
**Current Format:**
```elixir
%{
  "strategy" => "combine_objects",
  "inputs" => [data1, data2, data3]
}
```

**Enhanced Format:**
```elixir
%{
  "strategy" => "append" | "merge" | "concat",
  # Named input data comes automatically from ports:
  # "user_data" => %{name: "John", age: 30},
  # "payment_info" => %{card: "****1234"},
  # "preferences" => %{theme: "dark"}
}
```

### 3. Three Core Merge Strategies

#### Append Mode
- **Purpose**: Collect all inputs as separate array elements
- **Behavior**: Preserves input structure and data types
- **Output**: `[input_a, input_b, input_c]`
- **Use case**: General purpose data collection from parallel branches

#### Merge Mode
- **Purpose**: Combine object inputs by merging properties
- **Behavior**: Uses `Map.merge/2` across all named inputs, ignores non-maps
- **Output**: Single merged object with all properties
- **Use case**: Combining related data from different sources

#### Concat Mode
- **Purpose**: Flatten and concatenate array inputs
- **Behavior**: Uses `List.flatten/1` on array inputs, ignores non-arrays
- **Output**: Single flattened array
- **Use case**: Combining lists from parallel data processing branches

## Consequences

### Positive
- **Clear data lineage**: Developers know which data came from which workflow branch
- **Flexible combination**: Handles objects, arrays, or mixed data types appropriately
- **Diamond pattern support**: Enables proper fork-join workflow coordination
- **Simple API**: Three intuitive strategies cover most common merge scenarios
- **Extensible foundation**: Can add advanced strategies (field-based joins) later
- **Backward compatibility**: Can maintain existing single-input behavior during migration

### Negative
- **Breaking change**: Existing workflows using merge action will need updates
- **Increased complexity**: Node configuration becomes more involved
- **Implementation effort**: Requires changes to action definition, execution logic, and tests

### Neutral
- **Strategy migration**: Current strategies map reasonably to new ones:
  - `combine_objects` → `merge`
  - `combine_arrays` → `concat` 
  - `last_wins` → can be handled by `append` with custom logic

## Implementation Notes
- Create new `Prana.Integrations.Data` module for data manipulation operations
- Move merge action from `Prana.Integrations.Logic` to the new Data integration
- Remove merge action from Logic integration (keep if_condition and switch only)
- Modify input ports from `["input"]` to user-configurable list in Data integration
- Enhance merge function to handle named input map structure
- Add comprehensive tests for all three strategies with multiple inputs
- Update documentation and examples for diamond pattern workflows
- Register new Data integration in IntegrationRegistry

## Alternatives Considered
1. **Keep current single input**: Rejected - doesn't solve coordination problem
2. **Add field-based joins immediately**: Rejected - too complex for initial implementation
3. **Keep merge in Logic integration**: Rejected - Logic should focus on conditional branching, Data integration better suited for data manipulation
4. **Separate coordination from merging**: Considered but merge node enhancement provides better developer experience

## Related
- Supports Phase 3.3 goal of diamond pattern coordination
- Complements planned Wait integration for async synchronization
- Aligns with n8n-style multiple input handling patterns