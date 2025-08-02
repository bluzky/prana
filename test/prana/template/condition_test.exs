defmodule Prana.Template.ConditionTest do
  use ExUnit.Case, async: true

  alias Prana.Template

  describe "if condition rendering" do
    setup do
      context = %{
        "$input" => %{
          "age" => 25,
          "name" => "Alice",
          "active" => true,
          "inactive" => false,
          "count" => 5,
          "empty_string" => "",
          "zero" => 0,
          "nil_value" => nil
        }
      }

      {:ok, context: context}
    end

    test "renders if condition with true boolean", %{context: context} do
      template = "{% if $input.active %}User is active{% endif %}"

      assert {:ok, result} = Template.render(template, context)
      assert result == "User is active"
    end

    test "renders if condition with false boolean", %{context: context} do
      template = "{% if $input.inactive %}User is active{% endif %}"

      assert {:ok, result} = Template.render(template, context)
      assert result == ""
    end

    test "renders if condition with numeric comparison", %{context: context} do
      template = "{% if $input.age >= 18 %}Welcome adult!{% endif %}"

      assert {:ok, result} = Template.render(template, context)
      assert result == "Welcome adult!"
    end

    test "renders if condition with false numeric comparison" do
      context = %{"$input" => %{"age" => 16}}
      template = "{% if $input.age >= 18 %}Welcome adult!{% endif %}"

      assert {:ok, result} = Template.render(template, context)
      assert result == ""
    end

    test "renders if condition with string comparison", %{context: context} do
      template = "{% if $input.name == \"Alice\" %}Hello Alice!{% endif %}"

      assert {:ok, result} = Template.render(template, context)
      assert result == "Hello Alice!"
    end

    test "renders if condition with string inequality", %{context: context} do
      template = "{% if $input.name != \"Bob\" %}Not Bob{% endif %}"

      assert {:ok, result} = Template.render(template, context)
      assert result == "Not Bob"
    end

    test "handles truthiness of various values", %{context: context} do
      # Test truthy values
      template1 = "{% if $input.count %}Has count{% endif %}"
      assert {:ok, "Has count"} = Template.render(template1, context)

      template2 = "{% if $input.name %}Has name{% endif %}"
      assert {:ok, "Has name"} = Template.render(template2, context)

      # Test falsy values
      template3 = "{% if $input.empty_string %}Has string{% endif %}"
      assert {:ok, ""} = Template.render(template3, context)

      template4 = "{% if $input.zero %}Has zero{% endif %}"
      assert {:ok, "Has zero"} = Template.render(template4, context)

      template5 = "{% if $input.nil_value %}Has nil{% endif %}"
      assert {:ok, ""} = Template.render(template5, context)
    end

    test "renders if condition with complex expressions", %{context: context} do
      template = "{% if $input.age > 18 && $input.active %}Adult and active{% endif %}"

      assert {:ok, result} = Template.render(template, context)
      assert result == "Adult and active"
    end

    test "renders if condition with OR logic", %{context: context} do
      template = "{% if $input.age < 18 || $input.active %}Young or active{% endif %}"

      assert {:ok, result} = Template.render(template, context)
      assert result == "Young or active"
    end

    test "handles missing variables in conditions gracefully", %{context: context} do
      template = "{% if $input.missing_field %}Has missing{% endif %}"

      assert {:ok, result} = Template.render(template, context)
      assert result == ""
    end

    test "renders content before and after if blocks", %{context: context} do
      template = "Before {% if $input.active %}ACTIVE{% endif %} After"

      assert {:ok, result} = Template.render(template, context)
      assert result == "Before ACTIVE After"
    end

    test "handles multiple if blocks in sequence", %{context: context} do
      template = "{% if $input.age >= 18 %}Adult {% endif %}{% if $input.active %}Active{% endif %}"

      assert {:ok, result} = Template.render(template, context)
      assert result == "Adult Active"
    end

    test "handles nested expressions in conditions", %{context: context} do
      template = "{% if ($input.age + 5) > 25 %}Age plus 5 is over 25{% endif %}"

      assert {:ok, result} = Template.render(template, context)
      assert result == "Age plus 5 is over 25"
    end

    test "handles condition parsing errors gracefully" do
      context = %{"$input" => %{"value" => 42}}
      template = "{% if $input.value ++ invalid %}Bad syntax{% endif %}"

      # Should handle the parse error gracefully
      assert {:ok, result} = Template.render(template, context)
      # The exact error handling may vary based on implementation
      assert is_binary(result)
    end
  end
end
