defmodule Prana.Template.EngineTest do
  use ExUnit.Case, async: false

  alias Prana.Template.V2.Engine

  describe "basic template rendering with correct context format" do
    setup do
      context = %{
        "$input" => %{
          "user" => %{"name" => "John", "age" => 35},
          "items" => ["a", "b", "c"],
          "price" => 99.99,
          "verified" => true
        }
      }

      {:ok, context: context}
    end

    test "renders mixed template expressions (returns strings)", %{context: context} do
      assert {:ok, "Hello John!"} = Engine.render("Hello {{ $input.user.name }}!", context)
    end

    test "renders mixed arithmetic expressions (returns strings)", %{context: context} do
      assert {:ok, "Age in 10 years: 45"} = Engine.render("Age in 10 years: {{ $input.user.age + 10 }}", context)
    end

    test "renders mixed boolean expressions (returns strings)", %{context: context} do
      assert {:ok, "Eligible: true"} = Engine.render("Eligible: {{ $input.user.age >= 18 && $input.verified }}", context)
    end

    test "renders mixed templates with filters (returns strings)", %{context: context} do
      assert {:ok, "Hello JOHN!"} = Engine.render("Hello {{ $input.user.name | upper_case }}!", context)
    end

    test "handles missing variables by returning nil/empty string", %{context: context} do
      # Mixed template with missing field - nil becomes empty string
      assert {:ok, "Hello !"} = Engine.render("Hello {{ $input.missing_field }}!", context)

      # Pure expression with missing field - returns nil
      assert {:ok, nil} = Engine.render("{{ $input.missing_field }}", context)
    end

    test "renders literal text without expressions", %{context: _context} do
      assert {:ok, "No expressions here"} = Engine.render("No expressions here", %{})
    end

    test "pure expressions return original data types", %{context: context} do
      # String value
      assert {:ok, "John"} = Engine.render("{{ $input.user.name }}", context)

      # Integer value
      assert {:ok, 35} = Engine.render("{{ $input.user.age }}", context)

      # Boolean value
      assert {:ok, true} = Engine.render("{{ $input.verified }}", context)

      # Float value
      assert {:ok, 99.99} = Engine.render("{{ $input.price }}", context)

      # Arithmetic result (number)
      assert {:ok, 45} = Engine.render("{{ $input.user.age + 10 }}", context)

      # Boolean expression result
      assert {:ok, true} = Engine.render("{{ $input.user.age >= 18 }}", context)

      # Filter result (string from filter)
      assert {:ok, "JOHN"} = Engine.render("{{ $input.user.name | upper_case }}", context)
    end

    test "whitespace around expressions makes them mixed templates", %{context: context} do
      # Space before - mixed template, returns string
      assert {:ok, " John"} = Engine.render(" {{ $input.user.name }}", context)

      # Space after - mixed template, returns string
      assert {:ok, "John "} = Engine.render("{{ $input.user.name }} ", context)

      # Multiple expressions - mixed template, returns string
      assert {:ok, "John is 35"} = Engine.render("{{ $input.user.name }} is {{ $input.user.age }}", context)
    end
  end

  describe "variable filter arguments integration" do
    setup do
      context = %{
        "$input" => %{
          "user" => %{"name" => "John", "age" => 25},
          "fallback_name" => "Default User",
          "missing_field" => nil
        },
        "$variables" => %{
          "default_age" => 18,
          "currency" => "USD"
        },
        "$nodes" => %{
          "api" => %{
            "default_name" => "API Default",
            "response" => %{"bonus" => 5}
          }
        },
        # Simple variables for unquoted syntax
        "fallback_name" => "Simple Fallback",
        "config" => %{
          "currency" => "EUR",
          "theme" => "dark"
        }
      }

      {:ok, context: context}
    end

    test "renders templates with variable filter arguments", %{context: context} do
      # Variable fallback when field exists
      assert {:ok, "Hello John!"} =
               Engine.render("Hello {{ $input.user.name | default($input.fallback_name) }}!", context)

      # Variable fallback when field is missing
      assert {:ok, "Hello Default User!"} =
               Engine.render("Hello {{ $input.missing_field | default($input.fallback_name) }}!", context)
    end

    test "renders templates with nested variable paths in filters", %{context: context} do
      assert {:ok, "Name: API Default"} =
               Engine.render("Name: {{ $input.missing_field | default($nodes.api.default_name) }}", context)
    end

    test "renders templates with unquoted variable arguments", %{context: context} do
      # Simple variable name
      assert {:ok, "Name: Simple Fallback"} =
               Engine.render("Name: {{ $input.missing_field | default(fallback_name) }}", context)

      # Dotted variable path
      assert {:ok, "Currency: EUR"} =
               Engine.render("Currency: {{ $input.missing_field | default(config.currency) }}", context)
    end

    test "handles mixed literal and variable arguments", %{context: context} do
      # Mix of literal string and variable
      template = "User: {{ $input.missing_field | default($input.fallback_name) | default(\"Unknown\") }}"
      assert {:ok, "User: Default User"} = Engine.render(template, context)

      # When both variables are missing, should use literal
      context_minimal = %{"$input" => %{}}
      assert {:ok, "User: Unknown"} = Engine.render(template, context_minimal)
    end

    test "maintains backward compatibility with literal arguments", %{context: context} do
      # Should work exactly as before
      assert {:ok, "Hello Unknown!"} =
               Engine.render("Hello {{ $input.missing_field | default(\"Unknown\") }}!", context)

      assert {:ok, "Age: 18"} =
               Engine.render("Age: {{ $input.missing_age | default(18) }}", context)
    end

    test "handles chained filters with variable arguments", %{context: context} do
      template = "{{ $input.missing_field | default($input.fallback_name) | upper_case }}"
      assert {:ok, "DEFAULT USER"} = Engine.render(template, context)
    end

    test "pure expressions return correct types with variable filter arguments", %{context: context} do
      # Should return the actual fallback value type, not string
      assert {:ok, 18} =
               Engine.render("{{ $input.missing_age | default($variables.default_age) }}", context)

      assert {:ok, "Default User"} =
               Engine.render("{{ $input.missing_field | default($input.fallback_name) }}", context)
    end

    test "handles missing variable paths in filter arguments gracefully", %{context: context} do
      # Missing variable path should resolve to nil
      # Since $input.user.name exists, it should return "John" (not the nil fallback)
      assert {:ok, "John"} =
               Engine.render("{{ $input.user.name | default($missing.path) }}", context)

      # When main field is missing, should use the nil fallback from missing path
      assert {:ok, nil} =
               Engine.render("{{ $input.missing_field | default($missing.path) }}", context)
    end

    test "complex real-world scenarios", %{context: context} do
      # Scenario: User profile with multiple fallbacks
      template = """
      Name: {{ $input.user.display_name | default($input.user.name) | default($nodes.api.default_name) }}
      Age: {{ $input.user.age | default($variables.default_age) }}
      """

      assert {:ok,
              """
              Name: John
              Age: 25
              """} = Engine.render(template, context)

      # Same template but with missing user data
      context_empty = Map.put(context, "$input", %{})

      assert {:ok,
              """
              Name: API Default
              Age: 18
              """} = Engine.render(template, context_empty)
    end

    test "deeply nested variable paths in filter arguments", %{context: _context} do
      context_nested = %{
        "$config" => %{
          "ui" => %{
            "defaults" => %{
              "user" => %{
                "placeholder" => "Enter name"
              }
            }
          }
        },
        "$input" => %{"name" => nil}
      }

      template = "{{ $input.name | default($config.ui.defaults.user.placeholder) }}"
      assert {:ok, "Enter name"} = Engine.render(template, context_nested)
    end
  end

  describe "control flow rendering" do
    setup do
      context = %{
        "$input" => %{
          "users" => [
            %{"name" => "Alice", "age" => 25, "active" => true},
            %{"name" => "Bob", "age" => 17, "active" => false},
            %{"name" => "Carol", "age" => 30, "active" => true}
          ],
          "age" => 25,
          "status" => "premium",
          "empty_list" => []
        }
      }

      {:ok, context: context}
    end

    test "renders for loop with simple iteration", %{context: context} do
      template = "{% for user in $input.users %}User: {{ $user.name }} {% endfor %}"

      assert {:ok, result} = Engine.render(template, context)
      assert result == "User: Alice User: Bob User: Carol "
    end

    test "renders for loop with mixed content", %{context: context} do
      template = "Users: {% for user in $input.users %}{{ $user.name }}({{ $user.age }}) {% endfor %}Done!"

      assert {:ok, result} = Engine.render(template, context)
      assert result == "Users: Alice(25) Bob(17) Carol(30) Done!"
    end

    test "renders for loop with empty collection", %{context: context} do
      template = "Items: {% for item in $input.empty_list %}{{ $item }} {% endfor %}None found."

      assert {:ok, result} = Engine.render(template, context)
      assert result == "Items: None found."
    end

    test "renders if condition with true condition", %{context: context} do
      template = "{% if $input.age >= 18 %}Welcome adult!{% endif %}"

      assert {:ok, result} = Engine.render(template, context)
      assert result == "Welcome adult!"
    end

    test "renders if condition with false condition and no else", %{context: _context} do
      context = %{"$input" => %{"age" => 16}}
      template = "{% if $input.age >= 18 %}Welcome adult!{% endif %}"

      assert {:ok, result} = Engine.render(template, context)
      assert result == ""
    end

    test "renders content before and after control blocks", %{context: context} do
      template = "Before {% for user in $input.users %}{{ $user.name }} {% endfor %}After"

      assert {:ok, result} = Engine.render(template, context)
      assert result == "Before Alice Bob Carol After"
    end

    test "handles multiple control blocks in sequence", %{context: context} do
      template = "{% if $input.age >= 18 %}Adult {% endif %}{% for user in $input.users %}{{ $user.name }} {% endfor %}"

      assert {:ok, result} = Engine.render(template, context)
      assert result == "Adult Alice Bob Carol "
    end

    test "handles control flow errors gracefully", %{context: _context} do
      context = %{"$input" => %{"not_a_list" => "string"}}
      template = "{% for item in $input.not_a_list %}{{ $item }}{% endfor %}"

      # Should return error indication instead of crashing
      assert {:ok, result} = Engine.render(template, context)
      assert result =~ "Error: For loop iterable must be a list"
    end
  end
end
