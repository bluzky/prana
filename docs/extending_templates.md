# Extending Prana Templates: Custom Filters

Simple guide for creating custom filters to extend template functionality.

## Overview

Extend templates by creating custom filters that transform data. Filters use the pipe (`|`) syntax: `{{ $input.data | my_filter }}`.

**Key Rules:**
- Return `{:ok, result}` or `{:error, message}`
- Validate all inputs
- Keep filters fast and simple

## Creating Custom Filters

### Simple Filter

```elixir
defmodule MyApp.CustomFilters do
  # Reverse a string
  def reverse(value, []) when is_binary(value) do
    {:ok, String.reverse(value)}
  end
  
  def reverse(value, []) do
    {:ok, value |> to_string() |> String.reverse()}
  end
  
  def reverse(_value, _args) do
    {:error, "reverse filter takes no arguments"}
  end
end
```

### Filter with Arguments

```elixir
# Pad string to specified length
def pad_right(value, [length]) when is_binary(value) and is_integer(length) do
  pad_right(value, [length, " "])
end

def pad_right(value, [length, char]) when is_binary(value) and is_integer(length) and is_binary(char) do
  current_length = String.length(value)
  
  if current_length >= length do
    {:ok, value}
  else
    padding_needed = length - current_length
    padding = String.duplicate(char, padding_needed)
    {:ok, value <> padding}
  end
end

def pad_right(_value, _args) do
  {:error, "pad_right filter requires length and optional padding character"}
end
```

## Filter Module

Organize related filters in modules with a `spec()` function:

```elixir
defmodule MyApp.DateFilters do
  def spec do
    %{
      name: "date_filters",
      description: "Date formatting filters",
      filters: [
        %{name: "format_date", function: {__MODULE__, :format_date}, description: "Format date"},
        %{name: "relative_time", function: {__MODULE__, :relative_time}, description: "Relative time"}
      ]
    }
  end

  # Format date: {{ $input.date | format_date("%Y-%m-%d") }}
  def format_date(%Date{} = date, [format]) when is_binary(format) do
    try do
      formatted = Calendar.strftime(date, format)
      {:ok, formatted}
    rescue
      _ -> {:error, "Invalid date format: #{format}"}
    end
  end
  
  def format_date(_value, _args) do
    {:error, "format_date requires a date and format string"}
  end

  # Relative time: {{ $input.created_at | relative_time }}
  def relative_time(%Date{} = date, []) do
    today = Date.utc_today()
    diff = Date.diff(today, date)
    
    cond do
      diff == 0 -> {:ok, "today"}
      diff == 1 -> {:ok, "yesterday"}
      diff > 1 -> {:ok, "#{diff} days ago"}
      true -> {:ok, "in #{abs(diff)} days"}
    end
  end
  
  def relative_time(_value, _args) do
    {:error, "relative_time requires a date"}
  end
end
```

## Registration

Register your filter modules in your application:

```elixir
# In your application.ex
defp register_custom_filters do
  Prana.Template.FilterRegistry.register_module(MyApp.DateFilters)
  Prana.Template.FilterRegistry.register_module(MyApp.CustomFilters)
end
```

## Testing

Simple test example:

```elixir
defmodule MyApp.DateFiltersTest do
  use ExUnit.Case, async: true

  test "format_date works correctly" do
    date = ~D[2024-01-15]
    assert {:ok, "2024-01-15"} = MyApp.DateFilters.format_date(date, ["%Y-%m-%d"])
  end

  test "relative_time works correctly" do
    today = Date.utc_today()
    assert {:ok, "today"} = MyApp.DateFilters.relative_time(today, [])
  end
end
```

## Best Practices

1. **Always validate inputs** - Check argument types and counts
2. **Return proper tuples** - `{:ok, result}` or `{:error, message}`
3. **Keep filters simple** - Avoid expensive operations like HTTP calls
4. **Handle multiple types** - Support strings, numbers, etc. when possible
5. **Write good error messages** - Be specific about what went wrong

## Template Usage

```elixir
# Use your custom filters in templates
template = """
Date: {{ $input.created_at | format_date("%B %d, %Y") }}
Time: {{ $input.created_at | relative_time }}
Name: {{ $input.name | reverse | pad_right(20, ".") }}
"""

context = %{
  "$input" => %{
    "created_at" => ~D[2024-01-15],
    "name" => "Alice"
  }
}

{:ok, result} = Engine.render(template, context)
# Result: "Date: January 15, 2024\nTime: today\nName: ecilA..............."
```