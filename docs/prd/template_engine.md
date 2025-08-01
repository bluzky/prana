# Prana Template Engine - Development Requirements

## Project Overview
Add template engine functionality to existing Prana project that supports Liquid-style template syntax with filters, building on Prana's existing variable extraction capabilities.

## Technical Requirements

### 1. Project Structure
```
lib/prana/template/
├── engine.ex                 # Main API module
├── extractor.ex             # Template block extraction
├── expression_parser.ex     # NimbleParsec expression parser
├── evaluator.ex             # Expression evaluation
├── filter_registry.ex       # Filter management
└── filters/
    ├── string_filters.ex    # String manipulation filters
    ├── number_filters.ex    # Number formatting filters
    └── collection_filters.ex # Array/collection filters
```

### 2. Dependencies
Add to `mix.exs`:
```elixir
{:nimble_parsec, "~> 1.4"}
```

### 3. Core API
```elixir
# Main public interface
Prana.Template.render(template_string, context_map, opts \\ [])
```

### 4. Supported Template Syntax

#### 4.1 Basic Variable Interpolation
```elixir
"Hello {{ $input.user.name }}"
"User email: {{ $input[:email] }}"  # Atom key access
"First item: {{ $input.items[0] }}"   # Array index access
"String key: {{ $input[\"data\"] }}" # String key access
```

#### 4.2 Mixed Key Access (NEW)
```elixir
"{{ $input.user[:name] }}"          # Dot notation + atom key
"{{ $input.user[\"email\"] }}"     # Dot notation + string key
"{{ $input.data[0].title }}"        # Array index + field access
"{{ $input[\"config\"][:timeout] }}" # Mixed string and atom keys
```

#### 4.3 Arithmetic Expressions
```elixir
"{{ $input.age + 10 }}"
"{{ ($input.price - 5) * 2 }}"
```

#### 4.4 Boolean Expressions
```elixir
"{{ $input.age > 30 }}"
"{{ $input.age > 18 && $input.verified == true }}"
```

#### 4.5 Filter Syntax
```elixir
"{{ $input.name | upper_case }}"
"{{ $input.price | format_currency('USD') }}"
"{{ $input.description | truncate(50) | upper_case }}"
```

### 5. Operator Support

#### 5.1 Arithmetic Operators
- `+` (addition)
- `-` (subtraction)
- `*` (multiplication)
- `/` (division)
- `()` (parentheses for grouping)

#### 5.2 Comparison Operators
- `>` (greater than)
- `<` (less than)
- `>=` (greater than or equal)
- `<=` (less than or equal)
- `==` (equality)
- `!=` (not equal)

#### 5.3 Logical Operators
- `&&` (logical AND)
- `||` (logical OR)

#### 5.4 Filter Operator
- `|` (pipe to filter function)

### 6. Built-in Filters

#### 6.1 String Filters
```elixir
upper_case()          # Convert to uppercase
lower_case()          # Convert to lowercase
capitalize()          # Capitalize first letter
truncate(length)      # Truncate to specified length
```

#### 6.2 Number Filters
```elixir
round(decimals)       # Round to decimal places
format_currency(code) # Format as currency (e.g., "USD")
```

#### 6.3 Collection Filters
```elixir
length()              # Get length/count
first()               # Get first item
last()                # Get last item
join(separator)       # Join array elements
```

#### 6.4 Utility Filters
```elixir
default(value)        # Use default if nil/empty
to_string()           # Convert to string
```

### 7. Implementation Architecture

#### 7.1 Two-Phase Parsing Strategy
1. **Template Extraction**: Use regex to extract `{{ }}` blocks vs literal text
2. **Expression Parsing**: Use NimbleParsec to parse expression content

#### 7.2 Variable Integration
- Use existing `Prana.ExpressionEngine.extract("$input.user.name", context)` for variable path extraction
- Support mixed key types: string keys, atom keys, integer keys
- Handle nested map access gracefully (return `nil` for missing keys)
- Support bracket notation: `$input["key"]`, `$input[:atom]`, `$input[0]`

#### 7.3 Operator Precedence (highest to lowest)
1. Parentheses `()`
2. Multiplication/Division `*`, `/`
3. Addition/Subtraction `+`, `-`
4. Comparison `>`, `<`, `>=`, `<=`
5. Equality `==`, `!=`
6. Logical AND `&&`
7. Logical OR `||`
8. Pipe operator `|`

### 8. Error Handling Requirements

#### 8.1 Parse Errors
- Invalid template syntax (unclosed `{{`)
- Invalid expression syntax
- Provide line/column information where possible

#### 8.2 Runtime Errors
- Undefined filters
- Type mismatches in operations
- Missing variables (should return `nil`, not error)

#### 8.3 Error Response Format
```elixir
{:ok, rendered_string} | {:error, error_type, message}
```

### 9. Context Format
```elixir
context = %{
  "$input" => %{
    "user" => %{"name" => "John", "age" => 35},
    "items" => ["a", "b", "c"],
    "price" => 99.99,
    "verified" => true
  }
}
```

### 10. Example Usage
```elixir
# Basic interpolation
Prana.Template.render("Hello {{ $input.user.name }}!", context)
# => "Hello John!"

# Arithmetic with filters
Prana.Template.render("Price: {{ ($input.price + 5) | format_currency('USD') }}", context)
# => "Price: $104.99"

# Boolean expression
Prana.Template.render("Eligible: {{ $input.user.age >= 18 && $input.verified }}", context)
# => "Eligible: true"

# Filter chaining
Prana.Template.render("{{ $input.user.name | upper_case | truncate(3) }}", context)
# => "JOH"
```

### 11. Performance Requirements
- Support templates up to 10KB in size
- Handle contexts with nested maps up to 5 levels deep
- Process simple templates (< 10 expressions) in under 1ms

### 12. Testing Requirements
- Unit tests for each module
- Integration tests for complete template rendering
- Error handling test cases
- Performance benchmarks
- Property-based testing for expression evaluation

### 13. Documentation Requirements
- Module documentation with examples
- Filter reference documentation
- Usage guide with complex examples
- Performance characteristics documentation

## Implementation Notes

1. **Start with template extraction** - Get basic `{{ }}` parsing working first
2. **Build expression parser incrementally** - Start with variables, add operators gradually
3. **Implement filters last** - Core expression evaluation is the critical path
4. **Leverage existing Prana** - Use `Prana.ExpressionEngine.extract/2` for variable path extraction with mixed key support
5. **Error handling throughout** - Don't defer error handling to the end
6. **Mixed key support** - Ensure parser handles string, atom, and integer keys in bracket notation

## Success Criteria
- All example usage cases work correctly
- Comprehensive test suite passes
- Performance requirements met
- Clean, maintainable code structure
- Full documentation coverage
