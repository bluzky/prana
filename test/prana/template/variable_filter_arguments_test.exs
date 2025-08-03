defmodule Prana.Template.VariableFilterArgumentsTest do
  use ExUnit.Case, async: false

  alias Prana.Template

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
               Template.render("Hello {{ $input.user.name | default($input.fallback_name) }}!", context)

      # Variable fallback when field is missing
      assert {:ok, "Hello Default User!"} =
               Template.render("Hello {{ $input.missing_field | default($input.fallback_name) }}!", context)
    end

    test "renders templates with nested variable paths in filters", %{context: context} do
      assert {:ok, "Name: API Default"} =
               Template.render("Name: {{ $input.missing_field | default($nodes.api.default_name) }}", context)
    end

    test "renders templates with unquoted variable arguments", %{context: context} do
      # Simple variable name
      assert {:ok, "Name: Simple Fallback"} =
               Template.render("Name: {{ $input.missing_field | default(fallback_name) }}", context)

      # Dotted variable path
      assert {:ok, "Currency: EUR"} =
               Template.render("Currency: {{ $input.missing_field | default(config.currency) }}", context)
    end

    test "handles mixed literal and variable arguments", %{context: context} do
      # Mix of literal string and variable
      template = "User: {{ $input.missing_field | default($input.fallback_name) | default(\"Unknown\") }}"
      assert {:ok, "User: Default User"} = Template.render(template, context)

      # When both variables are missing, should use literal
      context_minimal = %{"$input" => %{}}
      assert {:ok, "User: Unknown"} = Template.render(template, context_minimal)
    end

    test "maintains backward compatibility with literal arguments", %{context: context} do
      # Should work exactly as before
      assert {:ok, "Hello Unknown!"} =
               Template.render("Hello {{ $input.missing_field | default(\"Unknown\") }}!", context)

      assert {:ok, "Age: 18"} =
               Template.render("Age: {{ $input.missing_age | default(18) }}", context)
    end

    test "handles chained filters with variable arguments", %{context: context} do
      template = "{{ $input.missing_field | default($input.fallback_name) | upper_case }}"
      assert {:ok, "DEFAULT USER"} = Template.render(template, context)
    end

    test "pure expressions return correct types with variable filter arguments", %{context: context} do
      # Should return the actual fallback value type, not string
      assert {:ok, 18} =
               Template.render("{{ $input.missing_age | default($variables.default_age) }}", context)

      assert {:ok, "Default User"} =
               Template.render("{{ $input.missing_field | default($input.fallback_name) }}", context)
    end

    test "handles missing variable paths in filter arguments gracefully", %{context: context} do
      # Missing variable path should resolve to nil
      # Since $input.user.name exists, it should return "John" (not the nil fallback)
      assert {:ok, "John"} =
               Template.render("{{ $input.user.name | default($missing.path) }}", context)

      # When main field is missing, should use the nil fallback from missing path
      assert {:ok, nil} =
               Template.render("{{ $input.missing_field | default($missing.path) }}", context)
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
              """} = Template.render(template, context)

      # Same template but with missing user data
      context_empty = Map.put(context, "$input", %{})

      assert {:ok,
              """
              Name: API Default
              Age: 18
              """} = Template.render(template, context_empty)
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
      assert {:ok, "Enter name"} = Template.render(template, context_nested)
    end
  end
end