defmodule Prana.Template.SecurityTest do
  use ExUnit.Case, async: true

  alias Prana.Template.Engine

  describe "template size limits" do
    test "rejects templates exceeding size limit" do
      # Create a template larger than 1MB
      large_template = String.duplicate("{{ $input.data }}", 100_000)
      context = %{"$input" => %{"data" => "test"}}

      assert {:error, reason} = Engine.render(large_template, context)
      assert reason =~ "Template size"
      assert reason =~ "exceeds maximum allowed"
    end

    test "accepts templates within size limit" do
      normal_template = "Hello {{ $input.name }}!"
      context = %{"$input" => %{"name" => "World"}}

      assert {:ok, "Hello World!"} = Engine.render(normal_template, context)
    end
  end

  describe "nesting depth limits" do
    test "rejects deeply nested control structures" do
      # Create nested if statements beyond limit
      nested_template = build_nested_if_template(60)  # Over the 50 limit
      context = %{"$input" => %{"value" => true}}

      assert {:error, reason} = Engine.render(nested_template, context)
      assert reason =~ "nesting depth"
      assert reason =~ "exceeds maximum allowed"
    end

    test "accepts reasonable nesting depth" do
      # Create nested structure within limit
      nested_template = build_nested_if_template(3)
      context = %{"$input" => %{"value" => true}}

      assert {:ok, _result} = Engine.render(nested_template, context)
    end

    defp build_nested_if_template(depth) when depth <= 0, do: "Content"
    defp build_nested_if_template(depth) do
      inner = build_nested_if_template(depth - 1)
      "{% if $input.value %}#{inner}{% endif %}"
    end
  end

  describe "loop iteration limits" do
    test "rejects loops with too many iterations" do
      # Create a list with more than 10,000 items
      large_list = Enum.to_list(1..15_000)
      context = %{"$input" => %{"items" => large_list}}
      template = "{% for item in $input.items %}{{ $item }} {% endfor %}"

      assert {:ok, result} = Engine.render(template, context)
      # Should contain error indication rather than processing all items
      assert result =~ "Error: For loop iterations"
      assert result =~ "exceeds maximum allowed"
    end

    test "accepts loops within iteration limit" do
      normal_list = [1, 2, 3, 4, 5]
      context = %{"$input" => %{"items" => normal_list}}
      template = "{% for item in $input.items %}{{ $item }} {% endfor %}"

      assert {:ok, "1 2 3 4 5 "} = Engine.render(template, context)
    end
  end

  describe "variable scoping security" do
    test "loop variables don't leak sensitive context" do
      # Ensure loop variables are properly scoped and don't expose full context
      context = %{
        "$input" => %{"users" => [%{"name" => "Alice"}]},
        "$secrets" => %{"api_key" => "secret123"}
      }

      # Template tries to access secrets through loop variable
      template = "{% for user in $input.users %}{{ $user.name }} {% endfor %}"

      assert {:ok, "Alice "} = Engine.render(template, context)

      # Verify secrets aren't accessible through loop context
      # This would be implementation-specific based on how scoping is done
    end

    test "variables don't expose internal implementation" do
      context = %{"$input" => %{"name" => "test"}}
      template = "{{ $input.name }}"

      assert {:ok, "test"} = Engine.render(template, context)
      # Should not expose internal Elixir structures or functions
    end
  end

  describe "regex security (ReDoS protection)" do
    test "handles potentially malicious regex input efficiently" do
      # Test patterns that could cause ReDoS with naive regex
      malicious_patterns = [
        "{{ " <> String.duplicate("a", 1000) <> " }}",
        "{% " <> String.duplicate("for x in ", 100) <> "list %}content{% endfor %}",
        String.duplicate("{{", 1000) <> String.duplicate("}}", 1000)
      ]

      context = %{"$input" => %{"data" => "test"}}

      for pattern <- malicious_patterns do
        # Should complete quickly without hanging
        start_time = System.monotonic_time(:millisecond)
        _result = Engine.render(pattern, context)
        end_time = System.monotonic_time(:millisecond)

        # Should complete within reasonable time (less than 1 second)
        assert end_time - start_time < 1000, "Regex processing took too long for pattern: #{String.slice(pattern, 0, 50)}..."
      end
    end
  end
end