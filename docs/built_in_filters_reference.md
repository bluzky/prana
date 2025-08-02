# Built-in Filters Reference

Complete reference for all built-in filters available in the Prana template engine.

## String Filters

### upper_case
Converts string to uppercase.
```
{{ "hello" | upper_case }}          # => "HELLO"
{{ $input.name | upper_case }}      # => "JOHN DOE"
```

### lower_case
Converts string to lowercase.
```
{{ "HELLO" | lower_case }}          # => "hello"
{{ $input.name | lower_case }}      # => "john doe"
```

### capitalize
Capitalizes the first letter of a string.
```
{{ "hello world" | capitalize }}    # => "Hello world"
{{ $input.name | capitalize }}      # => "John doe"
```

### truncate
Truncates string to specified length with optional suffix.
```
{{ $input.text | truncate(20) }}              # Truncate to 20 chars with "..."
{{ $input.text | truncate(15, "--") }}        # Truncate to 15 chars with "--"
```

### default
Provides a fallback value for nil or missing variables.
```
{{ $input.missing | default("Unknown") }}     # => "Unknown"
{{ $input.name | default("Anonymous") }}      # Uses name if present
```

## Number Filters

### round
Rounds number to specified decimal places.
```
{{ 3.14159 | round }}               # => 3 (integer)
{{ 3.14159 | round(2) }}            # => 3.14
{{ $input.price | round(2) }}       # Round to 2 decimal places
```

### format_currency
Formats number as currency with specified currency code.
```
{{ 42.5 | format_currency }}        # => "$42.50" (USD default)
{{ 42.5 | format_currency("EUR") }} # => "€42.50"
{{ 42.5 | format_currency("GBP") }} # => "£42.50"
```

## Collection Filters

All collection operations for lists, strings, and maps are consolidated in this section.

### Basic Collection Operations

#### length
Returns the size of a collection.
```
{{ $input.items | length }}         # Number of items in list
{{ $input.text | length }}          # Number of characters in string
{{ $input.data | length }}          # Number of keys in map
```

#### first
Returns the first element of a list or string.
```
{{ $input.items | first }}          # First item in list
{{ $input.text | first }}           # First character in string
```

#### last
Returns the last element of a list or string.
```
{{ $input.items | last }}           # Last item in list
{{ $input.text | last }}            # Last character in string
```

#### join
Joins list elements into a string with separator.
```
{{ $input.items | join }}           # Join with ", " (default)
{{ $input.items | join(" | ") }}    # Join with custom separator
```

### List Operations

#### sort
Sorts a list in ascending order.
```
{{ $input.numbers | sort }}         # Sort numbers: [1, 2, 3, 4, 5]
{{ $input.names | sort }}           # Sort strings: ["alice", "bob", "charlie"]
```

#### reverse
Reverses a list or string.
```
{{ $input.items | reverse }}        # Reverse list: [5, 4, 3, 2, 1]
{{ $input.text | reverse }}         # Reverse string: "olleh"
```

#### uniq
Removes duplicate elements from a list.
```
{{ [1, 2, 2, 3, 1] | uniq }}        # => [1, 2, 3]
{{ $input.tags | uniq }}            # Remove duplicate tags
```

#### slice
Extracts a portion of a list or string.
```
{{ $input.items | slice(1, 3) }}    # Elements 1-3: [2, 3, 4]
{{ $input.text | slice(0, 5) }}     # First 5 characters: "hello"
```

#### contains
Checks if a collection contains a value.
```
{{ $input.items | contains(3) }}    # => true/false
{{ $input.text | contains("world") }} # => true/false
```

#### compact
Removes nil values from a list.
```
{{ [1, nil, 2, nil, 3] | compact }} # => [1, 2, 3]
{{ $input.data | compact }}         # Remove nil entries
```

#### flatten
Flattens nested lists to a single level.
```
{{ [[1, 2], [3, 4]] | flatten }}    # => [1, 2, 3, 4]
{{ $input.nested | flatten }}       # Flatten all levels
```

#### sum
Calculates the sum of numeric values in a list.
```
{{ [1, 2, 3, 4] | sum }}            # => 10
{{ $input.scores | sum }}           # Total of all scores
```

### Map Operations

#### keys
Returns the keys of a map as a list.
```
{{ $input.user | keys }}            # => ["name", "age", "email"]
```

#### values
Returns the values of a map as a list.
```
{{ $input.user | values }}          # => ["John", 30, "john@example.com"]
```

### List of Maps Operations

#### group_by
Groups list elements by a specified key.
```
{{ $input.users | group_by("role") }}
# => %{"admin" => [...], "user" => [...]}
```

#### map
Extracts field values from a list of maps (similar to "pluck" in other systems).
```
{{ $input.users | map("name") }}     # => ["Alice", "Bob", "Charlie"]
{{ $input.products | map("price") }} # => [29.99, 49.99, 19.99]
{{ $input.items | map("category") }} # => ["electronics", "books", "clothing"]
```

#### filter
Filters a list of maps by field value (keeps matching items).
```
{{ $input.users | filter("role", "admin") }}      # Only admin users
{{ $input.products | filter("active", true) }}    # Only active products
{{ $input.orders | filter("status", "pending") }} # Only pending orders
```

#### reject
Rejects items from a list of maps by field value (removes matching items).
```
{{ $input.users | reject("role", "admin") }}      # All non-admin users
{{ $input.products | reject("active", false) }}   # Remove inactive products
{{ $input.orders | reject("status", "canceled") }} # Remove canceled orders
```

### Display Formatting

#### dump
Formats data structures for display in templates.
```
{{ $input.items | dump }}           # => "[1, 2, 3]"
{{ $input.user | dump }}            # => "%{name: \"John\", age: 30}"
{{ $input.text | dump }}            # => "hello" (strings pass through)
```

## Math Filters

### abs
Returns the absolute value of a number.
```
{{ -42 | abs }}                     # => 42
{{ $input.temperature | abs }}      # Absolute value
```

### ceil
Rounds number up to the nearest integer.
```
{{ 3.14 | ceil }}                   # => 4
{{ -2.5 | ceil }}                   # => -2
```

### floor
Rounds number down to the nearest integer.
```
{{ 3.99 | floor }}                  # => 3
{{ -2.5 | floor }}                  # => -3
```

### max
Returns the maximum of two values.
```
{{ 5 | max(10) }}                   # => 10
{{ $input.score | max(100) }}       # Cap at 100
```

### min
Returns the minimum of two values.
```
{{ 15 | min(10) }}                  # => 10
{{ $input.temperature | min(32) }}  # Floor at 32
```

### power
Raises number to the specified power.
```
{{ 2 | power(3) }}                  # => 8.0
{{ $input.base | power(2) }}        # Square the value
```

### sqrt
Returns the square root of a number.
```
{{ 16 | sqrt }}                     # => 4.0
{{ $input.area | sqrt }}            # Square root
```

### modulo
Returns the remainder of division.
```
{{ 17 | modulo(5) }}                # => 2
{{ $input.number | modulo(10) }}    # Remainder when divided by 10
```

### clamp
Constrains value between minimum and maximum.
```
{{ 5 | clamp(0, 10) }}              # => 5 (within range)
{{ -5 | clamp(0, 10) }}             # => 0 (below minimum)
{{ 15 | clamp(0, 10) }}             # => 10 (above maximum)
```


## Filter Chaining

All filters can be chained together using the pipe (`|`) operator:

### String Processing Chains
```
{{ $input.description | truncate(100) | capitalize | default("No description") }}
{{ $input.name | lower_case | capitalize }}
```

### Number Processing Chains
```
{{ $input.price | round(2) | format_currency("USD") }}
{{ $input.score | abs | max(100) | round(1) }}
```

### Data Processing Chains
```
{{ $input.numbers | sort | reverse | slice(0, 3) | sum }}
{{ $input.users | group_by("role") | keys | sort | join(", ") }}
{{ $input.users | map("name") | join(", ") | upper_case }}
{{ $input.users | filter("active", true) | map("email") | join("; ") }}
{{ $input.products | reject("discontinued", true) | map("price") | sum }}
{{ $input.data | compact | uniq | sort | dump }}
```

### Mixed Type Chains
```
{{ $input.items | length | format_currency }}  # Convert count to currency display
{{ $input.nested | flatten | uniq | size }}    # Process and count
{{ $input.data | sort | dump | truncate(50) }} # Process and format for display
```

## Type Behavior

### Pure Expressions
When a template contains only a single expression, the original data type is preserved:
```
{{ $input.count }}              # Returns: 42 (number)
{{ $input.active }}             # Returns: true (boolean)
{{ $input.items | sort }}       # Returns: [1, 2, 3] (list)
```

### Mixed Content
When a template mixes text with expressions, the result is always a string:
```
Count: {{ $input.count }}       # Returns: "Count: 42" (string)
Items: {{ $input.items | dump }} # Returns: "Items: [1, 2, 3]" (string)
```

## Error Handling

- **Unknown filters**: Return error messages
- **Invalid arguments**: Return error messages  
- **Type mismatches**: Return error messages
- **Missing variables**: Return empty strings (graceful mode) or errors (strict mode)

For comprehensive examples and usage patterns, see the [Template Syntax Guide](template_syntax_guide.md).