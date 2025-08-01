defmodule Prana.Template.V2.EngineTest do
  use ExUnit.Case, async: false

  alias Prana.Template.V2.Engine

  describe "V2 Engine compatibility with existing Engine tests" do
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

  describe "V2 Engine process_map functionality" do
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
        }
      }

      {:ok, context: context}
    end

    test "process_map works with simple expressions", %{context: context} do
      input_map = %{
        "greeting" => "{{ $input.user.name }}",
        "age" => "{{ $input.user.age }}",
        "static" => "Hello World"
      }

      assert {:ok, result} = Engine.process_map(input_map, context)
      assert result["greeting"] == "John"
      assert result["age"] == 25
      assert result["static"] == "Hello World"
    end

    test "process_map maintains original types for single expressions", %{context: context} do
      input_map = %{
        "name" => "{{ $input.user.name }}",  # String
        "age" => "{{ $input.user.age }}",    # Integer
        "missing" => "{{ $input.missing_field }}" # nil
      }

      assert {:ok, result} = Engine.process_map(input_map, context)
      assert result["name"] == "John"
      assert result["age"] == 25
      assert result["missing"] == nil
    end

    test "process_map handles nested structures", %{context: context} do
      input_map = %{
        "user_info" => %{
          "display_name" => "{{ $input.user.name }}",
          "years_old" => "{{ $input.user.age }}"
        },
        "metadata" => [
          "{{ $input.user.name }}",
          "{{ $input.user.age }}"
        ]
      }

      assert {:ok, result} = Engine.process_map(input_map, context)
      assert result["user_info"]["display_name"] == "John"
      assert result["user_info"]["years_old"] == 25
      assert result["metadata"] == ["John", 25]
    end
  end
end