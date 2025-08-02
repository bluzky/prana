defmodule Prana.Template.BasicRenderingTest do
  use ExUnit.Case, async: false

  alias Prana.Template

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
      assert {:ok, "Hello John!"} = Template.render("Hello {{ $input.user.name }}!", context)
    end

    test "renders mixed arithmetic expressions (returns strings)", %{context: context} do
      assert {:ok, "Age in 10 years: 45"} = Template.render("Age in 10 years: {{ $input.user.age + 10 }}", context)
    end

    test "renders mixed boolean expressions (returns strings)", %{context: context} do
      assert {:ok, "Eligible: true"} =
               Template.render("Eligible: {{ $input.user.age >= 18 && $input.verified }}", context)
    end

    test "renders mixed templates with filters (returns strings)", %{context: context} do
      assert {:ok, "Hello JOHN!"} = Template.render("Hello {{ $input.user.name | upper_case }}!", context)
    end

    test "handles missing variables by returning nil/empty string", %{context: context} do
      # Mixed template with missing field - nil becomes empty string
      assert {:ok, "Hello !"} = Template.render("Hello {{ $input.missing_field }}!", context)

      # Pure expression with missing field - returns nil
      assert {:ok, nil} = Template.render("{{ $input.missing_field }}", context)
    end

    test "renders literal text without expressions", %{context: _context} do
      assert {:ok, "No expressions here"} = Template.render("No expressions here", %{})
    end

    test "pure expressions return original data types", %{context: context} do
      # String value
      assert {:ok, "John"} = Template.render("{{ $input.user.name }}", context)

      # Integer value
      assert {:ok, 35} = Template.render("{{ $input.user.age }}", context)

      # Boolean value
      assert {:ok, true} = Template.render("{{ $input.verified }}", context)

      # Float value
      assert {:ok, 99.99} = Template.render("{{ $input.price }}", context)

      # Arithmetic result (number)
      assert {:ok, 45} = Template.render("{{ $input.user.age + 10 }}", context)

      # Boolean expression result
      assert {:ok, true} = Template.render("{{ $input.user.age >= 18 }}", context)

      # Filter result (string from filter)
      assert {:ok, "JOHN"} = Template.render("{{ $input.user.name | upper_case }}", context)
    end

    test "whitespace around expressions makes them mixed templates", %{context: context} do
      # Space before - mixed template, returns string
      assert {:ok, " John"} = Template.render(" {{ $input.user.name }}", context)

      # Space after - mixed template, returns string
      assert {:ok, "John "} = Template.render("{{ $input.user.name }} ", context)

      # Multiple expressions - mixed template, returns string
      assert {:ok, "John is 35"} = Template.render("{{ $input.user.name }} is {{ $input.user.age }}", context)
    end
  end
end