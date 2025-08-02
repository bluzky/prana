# Prana Template Syntax Guide

Complete reference for the Prana template engine syntax, features, and usage patterns.

## Table of Contents

1. [Basic Syntax](#basic-syntax)
2. [Variable Access](#variable-access)
3. [Expressions](#expressions)
4. [Control Structures](#control-structures)
5. [Filters](#filters)
6. [Functions](#functions)
7. [Operators](#operators)
8. [Security and Limits](#security-and-limits)
9. [Advanced Features](#advanced-features)
10. [Best Practices](#best-practices)
11. [Error Handling](#error-handling)

## Basic Syntax

### Template Delimiters

Prana templates use double curly braces for expressions and control structures:

```
{{ expression }}          # Variable expressions
{% control_structure %}   # Control flow (if, for)
```

### Simple Variable Substitution

```
Hello {{ $input.name }}!
# Result: "Hello John!"
```

### Mixed Content vs Pure Expressions

**Mixed Content** (returns string):
```
Name: {{ $input.name }}, Age: {{ $input.age }}
# Result: "Name: John, Age: 25"
```

**Pure Expression** (preserves original type):
```
{{ $input.age }}
# Result: 25 (number, not "25")
```

## Variable Access

### Context Variables

Access variables from the context using the `$` prefix:

```
{{ $input.name }}           # Simple field access
{{ $input.user.email }}     # Nested field access
{{ $variables.app_name }}   # Variables section
```

### Local Variables

Access loop variables and local scope without the `$` prefix:

```
{% for user in $input.users %}
  {{ user.name }}           # Local variable access
  {{ user.profile.email }}  # Nested local variable
{% endfor %}
```

### Nested Field Access

```
{{ $input.user.profile.settings.theme }}
{{ $input.data.nested.deeply.nested.value }}
```

### Array Access

```
{{ $input.users[0].name }}        # Index access
{{ $input.items[2].description }} # Array element access
```

## Expressions

### Arithmetic Expressions

```
{{ $input.price + $input.tax }}           # Addition
{{ $input.total - $input.discount }}      # Subtraction
{{ $input.quantity * $input.unit_price }} # Multiplication
{{ $input.total / $input.count }}         # Division
```

### Complex Arithmetic with Parentheses

```
{{ ($input.base_price + $input.tax) * $input.quantity }}
{{ (($input.a + $input.b) * $input.c) / $input.d }}
```

### Operator Precedence

Mathematical precedence is respected:

```
{{ $input.a + $input.b * $input.c }}
# Equivalent to: $input.a + ($input.b * $input.c)

{{ ($input.a + $input.b) * $input.c }}
# Forces addition first
```

### Boolean Expressions

```
{{ $input.age >= 18 }}                    # Comparison
{{ $input.active && $input.verified }}    # Logical AND
{{ $input.premium || $input.trial }}      # Logical OR
{{ $input.status != "pending" }}          # Not equal
```

### Complex Boolean Logic

```
{{ ($input.age >= 18 && $input.verified) || $input.admin }}
{{ ($input.score > 80) && ($input.active != false) }}
```

### String Comparisons

```
{{ $input.role == "admin" }}
{{ $input.status != "pending" }}
{{ $input.name == "John Doe" }}
```

## Control Structures

### If Conditions

**Basic If Statement:**
```
{% if $input.active %}
  User is active
{% endif %}
```

**If with Complex Conditions:**
```
{% if $input.age >= 18 && $input.verified %}
  Welcome, verified adult user!
{% endif %}
```

**If with Nested Expressions:**
```
{% if ($input.score + $input.bonus) > 100 %}
  Congratulations! You achieved over 100 points!
{% endif %}
```

### For Loops

**Basic For Loop:**
```
{% for user in $input.users %}
  Name: {{ user.name }}, Email: {{ user.email }}
{% endfor %}
```

**For Loop with Complex Content:**
```
{% for product in $input.products %}
  Product: {{ product.name }}
  Price: {{ product.price | format_currency }}
  {% if product.on_sale %}
    Sale Price: {{ product.sale_price | format_currency }}
  {% endif %}
{% endfor %}
```

**For Loop with Nested Data:**
```
{% for category in $input.categories %}
  Category: {{ category.name }}
  {% for item in category.items %}
    - {{ item.name }}: {{ item.price | format_currency }}
  {% endfor %}
{% endfor %}
```

### Loop Variables

Loops automatically provide access to:
- `loop_index`: Current iteration index (0-based)

```
{% for item in $input.items %}
  Item {{ loop_index }}: {{ item.name }}
{% endfor %}
```

## Filters

Filters transform values using the pipe (`|`) operator.

### String Filters

**Case Conversion:**
```
{{ $input.name | upper_case }}      # JOHN DOE
{{ $input.name | lower_case }}      # john doe
{{ $input.name | capitalize }}      # John doe
```

**String Manipulation:**
```
{{ $input.text | truncate(20) }}              # Truncate to 20 chars with "..."
{{ $input.text | truncate(15, "--") }}        # Truncate to 15 chars with "--"
{{ $input.value | default("No value") }}      # Default value for nil
```

### Number Filters

**Rounding:**
```
{{ $input.price | round }}          # Round to integer
{{ $input.price | round(2) }}       # Round to 2 decimal places
```

**Currency Formatting:**
```
{{ $input.price | format_currency }}         # Format as $42.50 (USD default)
{{ $input.price | format_currency("EUR") }}  # Format as €42.50
{{ $input.price | format_currency("GBP") }}  # Format as £42.50
```

### Basic Filter Examples

**String Filters:**
```
{{ $input.name | upper_case }}      # Case conversion
{{ $input.text | truncate(20) }}    # String manipulation
{{ $input.value | default("N/A") }} # Default values
```

**Number Filters:**
```
{{ $input.price | round(2) }}       # Rounding
{{ $input.amount | format_currency("USD") }} # Currency formatting
```

**Collection Filters:**
```
{{ $input.items | length }}         # Get collection size
{{ $input.items | first }}          # Get first item
{{ $input.items | join(", ") }}     # Join with separator
```

### Filter Chaining

Combine multiple filters using the pipe operator:

```
{{ $input.description | truncate(50) | capitalize }}
{{ $input.price | round(2) | format_currency("USD") }}
{{ $input.tags | join(", ") | upper_case | truncate(30) }}
```

### Complex Filter Chains

```
{{ $input.user.bio | truncate(100) | capitalize | default("No bio available") }}
{{ $input.description | truncate(50) | capitalize }}
{{ $input.tags | join(", ") | upper_case | truncate(30) }}
```

## Functions

Functions provide reusable operations within expressions.

### Function Calls

**Basic Function Calls:**
```
{{ $input.text | upper_case() }}          # Function with no arguments
{{ $input.price | round(2) }}             # Function with one argument
{{ $input.text | truncate(20, "...") }}   # Function with multiple arguments
```

**Functions in Expressions:**
```
{{ ($input.items | length()) + $input.count }}
{{ ($input.users | length()) > 10 }}
```

### Function Arguments

**Literal Arguments:**
```
{{ $input.text | truncate(50, "...") }}
{{ $input.price | format_currency("EUR") }}
```

**Variable Arguments:**
```
{{ $input.price | round(precision) }}
{{ $input.text | truncate(max_length, suffix) }}
```

**Mixed Arguments:**
```
{{ $input.price | format_currency(currency_code) }}
{{ $input.description | truncate(limit, "...") }}
```

## Operators

### Arithmetic Operators

| Operator | Description | Example | Precedence |
|----------|-------------|---------|------------|
| `+` | Addition | `{{ a + b }}` | Low |
| `-` | Subtraction | `{{ a - b }}` | Low |
| `*` | Multiplication | `{{ a * b }}` | High |
| `/` | Division | `{{ a / b }}` | High |

### Comparison Operators

| Operator | Description | Example |
|----------|-------------|---------|
| `==` | Equal | `{{ status == "active" }}` |
| `!=` | Not equal | `{{ status != "pending" }}` |
| `>` | Greater than | `{{ age > 18 }}` |
| `<` | Less than | `{{ score < 100 }}` |
| `>=` | Greater than or equal | `{{ age >= 21 }}` |
| `<=` | Less than or equal | `{{ score <= 100 }}` |

### Logical Operators

| Operator | Description | Example | Precedence |
|----------|-------------|---------|------------|
| `&&` | Logical AND | `{{ active && verified }}` | Medium |
| `\|\|` | Logical OR | `{{ premium \|\| trial }}` | Low |

### Operator Precedence (High to Low)

1. **Parentheses**: `( )`
2. **Multiplication/Division**: `*`, `/`
3. **Addition/Subtraction**: `+`, `-`
4. **Comparison**: `==`, `!=`, `>`, `<`, `>=`, `<=`
5. **Logical AND**: `&&`
6. **Logical OR**: `||`

## Security and Limits

### Built-in Security Limits

The template engine enforces several security limits:

**Template Size:**
- Maximum template size: 100,000 bytes
- Prevents memory exhaustion attacks

**Loop Iterations:**
- Maximum loop iterations: 10,000
- Enforced per-iteration with early termination
- Prevents infinite loop attacks

**Nesting Depth:**
- Maximum control structure nesting: 50 levels
- Prevents stack overflow from deeply nested structures

**Recursion Depth:**
- Maximum expression recursion: 100 levels
- Prevents infinite recursion in complex expressions

### Security Features

**Safe Variable Access:**
- Missing variables return empty strings (graceful handling)
- No code injection possible through variable names

**Filter Security:**
- Unknown filters return errors (strict handling)
- Filter arguments are validated for type safety

**Expression Safety:**
- All expressions are parsed and validated before execution
- No arbitrary code execution possible

## Advanced Features

### Nested Parentheses

Complex nested expressions are fully supported:

```
{{ (($input.base * $input.rate) + $input.fee) / $input.divisor }}
{{ ($input.score > 80) && (($input.bonus + $input.extra) > 50) }}
```

### Mixed Arithmetic and Boolean Logic

```
{{ ($input.total + $input.tax) > ($input.budget * 0.8) }}
{{ (($input.price * $input.quantity) + $input.shipping) <= $input.limit }}
```

### Function Results in Expressions

```
{{ ($input.items | length()) + ($input.users | length()) }}
{{ ($input.text | length()) > 100 && $input.truncate_long }}
```

### Complex Control Flow

```
{% for user in $input.users %}
  {% if ($input.min_age <= user.age) && (user.age <= $input.max_age) %}
    {{ user.name }} ({{ user.age }} years old)
    Balance: {{ user.balance | format_currency }}
  {% endif %}
{% endfor %}
```

### Type Preservation

The template engine preserves types in pure expressions:

```
{{ $input.count }}              # Returns: 42 (number)
{{ $input.active }}             # Returns: true (boolean)
{{ $input.items | length }}     # Returns: 5 (number)

Count: {{ $input.count }}       # Returns: "Count: 42" (string)
```

## Best Practices

### Expression Complexity

**Use parentheses for clarity:**
```
# Good
{{ ($input.base_price + $input.tax) * $input.quantity }}

# Less clear
{{ $input.base_price + $input.tax * $input.quantity }}
```

### Control Structure Organization

**Keep control blocks focused:**
```
# Good
{% for product in $input.products %}
  {{ product.name }}: {{ product.price | format_currency }}
{% endfor %}

# Avoid deeply nested structures when possible
```

### Performance Considerations

**Minimize complex expressions in loops:**
```
# Good - calculate once outside loop
{{ $input.tax_rate }}
{% for item in $input.items %}
  {{ item.price * tax_rate | format_currency }}
{% endfor %}

# Less efficient - calculate in every iteration
{% for item in $input.items %}
  {{ item.price * ($input.tax_percent / 100) | format_currency }}
{% endfor %}
```

## Error Handling

### Error Modes

The template engine supports two error handling modes:

**Graceful Mode (default):**
- Missing variables return empty strings
- Unknown filters return errors
- Parse errors return original template

**Strict Mode:**
- All errors return error messages
- No fallback behavior
- Recommended for development and debugging

### Common Error Scenarios

**Missing Variables:**
```
# Graceful mode
{{ $input.missing_field }}     # Returns: ""

# Strict mode
{{ $input.missing_field }}     # Returns: Error message
```

**Unknown Filters:**
```
# Both modes
{{ $input.text | unknown_filter }}  # Returns: Error message
```

**Parse Errors:**
```
# Graceful mode
{{ $input.value + }}               # Returns: "{{ $input.value + }}"

# Strict mode
{{ $input.value + }}               # Returns: Error message
```
