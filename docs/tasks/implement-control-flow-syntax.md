# Task: Implement Control Flow Syntax (For Loops and If Conditions)

**Status:** Ready for Implementation  
**Priority:** High  
**Objective:** Extend the existing template engine to support for loops and if conditions while maintaining current functionality.

## Overview

Add control flow constructs to the template engine to enable:
- For loops for iterating over collections
- If/else/elsif conditions for conditional rendering
- Maintaining existing {{ }} expression syntax and process_map functionality

## Proposed Syntax

### For Loops
```
{% for user in $input.users %}
  Hello {{ user.name }}! Age: {{ user.age }}
{% endfor %}

{% for item in $nodes.api.response.items %}
  {{ item.title | upper_case }}
{% endfor %}
```

### If Conditions
```
{% if $input.age >= 18 %}
  Welcome adult user!
{% else %}
  Sorry, must be 18+
{% endif %}

{% if $input.status == "premium" %}
  Premium features enabled
{% elsif $input.status == "standard" %}
  Standard features enabled  
{% else %}
  Basic features only
{% endif %}
```

### Nested Control Flow
```
{% for user in $input.users %}
  {% if user.active %}
    Active user: {{ user.name }}
  {% else %}
    Inactive user: {{ user.name }}
  {% endif %}
{% endfor %}
```

## Implementation Plan

### Phase 1: Extractor Enhancement
**File:** `lib/prana/template/extractor.ex`

**Changes Required:**
1. **Add {% %} Block Support**
   - Extend `do_extract/1` to handle `{% %}` delimiters alongside `{{ }}`
   - Add validation for matched control flow blocks (for/endfor, if/endif)

2. **New Block Types**
   ```elixir
   # Current: {:literal, text} | {:expression, content}
   # Add: {:control, type, attributes, body}
   
   {:control, :for_loop, 
    %{variable: "user", iterable: "$input.users"}, 
    [body_blocks]}
   
   {:control, :if_condition,
    %{condition: "$input.age >= 18"},
    %{then_body: [blocks], else_body: [blocks], elsif_clauses: [...]}}
   ```

3. **Validation Functions**
   - `validate_control_blocks/1` - ensure proper nesting and matching tags
   - `parse_control_block_content/2` - extract attributes from control statements

### Phase 2: Expression Parser Extension  
**File:** `lib/prana/template/expression_parser.ex`

**Changes Required:**
1. **Control Flow AST Nodes**
   ```elixir
   # For loop AST
   %{
     type: :for_loop,
     variable: "user",
     iterable: %{type: :variable, path: "$input.users"},
     body: [parsed_body_blocks]
   }
   
   # If condition AST  
   %{
     type: :if_condition,
     condition: %{type: :binary_op, operator: ">=", left: ..., right: ...},
     then_body: [blocks],
     else_body: [blocks],
     elsif_clauses: [
       %{condition: ..., body: [blocks]}
     ]
   }
   ```

2. **New Parser Functions**
   - `parse_control_expression/2` - parse control flow statements
   - `parse_for_statement/1` - parse "user in $input.users"
   - `parse_condition_statement/1` - parse if/elsif conditions

### Phase 3: Evaluator Enhancement
**File:** `lib/prana/template/evaluator.ex`

**Changes Required:**
1. **Loop Evaluation with Scoping**
   ```elixir
   def evaluate(%{type: :for_loop} = ast, context) do
     with {:ok, collection} <- evaluate(ast.iterable, context) do
       results = Enum.map(collection, fn item ->
         # Create scoped context with loop variable
         scoped_context = Map.put(context, ast.variable, item)
         evaluate_body(ast.body, scoped_context)
       end)
       {:ok, results}
     end
   end
   ```

2. **Conditional Evaluation**
   ```elixir
   def evaluate(%{type: :if_condition} = ast, context) do
     with {:ok, condition_result} <- evaluate(ast.condition, context) do
       cond do
         condition_result -> evaluate_body(ast.then_body, context)
         ast.else_body -> evaluate_body(ast.else_body, context)
         true -> {:ok, ""}
       end
     end
   end
   ```

3. **Helper Functions**
   - `evaluate_body/2` - evaluate list of blocks with context
   - `create_scoped_context/3` - manage variable scoping

### Phase 4: Engine Integration
**File:** `lib/prana/template/engine.ex`

**Changes Required:**
1. **Handle Control Flow Blocks**
   ```elixir
   defp render_single_block({:control, type, attributes, body}, context) do
     # Convert control block to AST and evaluate
     ast = ExpressionParser.parse_control_expression(type, attributes, body)
     case Evaluator.evaluate(ast, context) do
       {:ok, results} -> {:ok, format_control_output(results)}
       {:error, reason} -> {:error, reason}
     end
   end
   ```

2. **Output Formatting**
   - `format_control_output/1` - handle array results from loops
   - Maintain string concatenation for template rendering
   - Preserve data types for pure expressions

3. **Preserve Existing Functionality**
   - Keep `process_map/2` unchanged
   - Maintain `{{ }}` expression processing
   - Ensure backward compatibility

### Phase 5: Comprehensive Testing
**Files:** `test/prana/template/*_test.exs`

**Test Categories:**
1. **Basic Control Flow**
   - Simple for loops with various data types
   - Basic if/else conditions
   - Empty collections and falsy conditions

2. **Complex Scenarios**
   - Nested loops and conditions
   - Filter chaining in control flow
   - Variable scoping edge cases

3. **Error Handling**
   - Malformed control blocks
   - Invalid variable references
   - Missing endfor/endif tags

4. **Integration Tests**
   - Control flow with `process_map/2`
   - Mixed `{{ }}` and `{% %}` syntax
   - Performance with large collections

### Phase 6: Documentation Updates
**Files:** Various documentation files

1. **Template Engine Documentation**
   - Update module docs with control flow examples
   - Add syntax reference guide

2. **Integration Guides**
   - Update workflow building examples
   - Add control flow patterns for common use cases

## Implementation Order

1. **Start with Extractor** - Foundation for parsing control blocks
2. **Expression Parser** - AST representation for control flow  
3. **Evaluator** - Core logic for loops and conditionals
4. **Engine Integration** - Tie everything together
5. **Testing** - Comprehensive test coverage
6. **Documentation** - Update examples and guides

## Compatibility Considerations

- **Backward Compatible** - All existing `{{ }}` syntax continues to work
- **process_map Preserved** - No changes to structural data processing
- **Filter System** - Existing filters work in control flow contexts
- **Error Handling** - Graceful fallback to original syntax on errors

## Success Criteria

- [ ] For loops iterate over arrays and render content for each item
- [ ] If conditions evaluate expressions and render appropriate branches
- [ ] Nested control flow works correctly with proper scoping
- [ ] Existing functionality remains unchanged
- [ ] Comprehensive test coverage (>95%)
- [ ] Performance impact < 10% for templates without control flow
- [ ] Clear error messages for malformed control blocks

## Future Enhancements (Not in Scope)

- While loops
- Switch/case statements  
- Template inheritance/includes
- Macro definitions
- Advanced loop variables (index, first, last)

---

**Estimated Effort:** 2-3 weeks  
**Risk Level:** Medium (complex parsing and evaluation logic)  
**Dependencies:** None (extends existing architecture)