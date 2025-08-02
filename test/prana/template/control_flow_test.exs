defmodule Prana.Template.ControlFlowTest do
  use ExUnit.Case, async: false

  alias Prana.Template

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
      template = "{% for user in $input.users %}User: {{ user.name }} {% endfor %}"

      assert {:ok, result} = Template.render(template, context)
      assert result == "User: Alice User: Bob User: Carol "
    end

    test "renders for loop with mixed content", %{context: context} do
      template = "Users: {% for user in $input.users %}{{ user.name }}({{ user.age }}) {% endfor %}Done!"

      assert {:ok, result} = Template.render(template, context)
      assert result == "Users: Alice(25) Bob(17) Carol(30) Done!"
    end

    test "renders for loop with empty collection", %{context: context} do
      template = "Items: {% for item in $input.empty_list %}{{ item }} {% endfor %}None found."

      assert {:ok, result} = Template.render(template, context)
      assert result == "Items: None found."
    end

    test "renders if condition with true condition", %{context: context} do
      template = "{% if $input.age >= 18 %}Welcome adult!{% endif %}"

      assert {:ok, result} = Template.render(template, context)
      assert result == "Welcome adult!"
    end

    test "renders if condition with false condition and no else", %{context: _context} do
      context = %{"$input" => %{"age" => 16}}
      template = "{% if $input.age >= 18 %}Welcome adult!{% endif %}"

      assert {:ok, result} = Template.render(template, context)
      assert result == ""
    end

    test "renders content before and after control blocks", %{context: context} do
      template = "Before {% for user in $input.users %}{{ user.name }} {% endfor %}After"

      assert {:ok, result} = Template.render(template, context)
      assert result == "Before Alice Bob Carol After"
    end

    test "handles multiple control blocks in sequence", %{context: context} do
      template = "{% if $input.age >= 18 %}Adult {% endif %}{% for user in $input.users %}{{ user.name }} {% endfor %}"

      assert {:ok, result} = Template.render(template, context)
      assert result == "Adult Alice Bob Carol "
    end

    test "handles control flow errors gracefully", %{context: _context} do
      context = %{"$input" => %{"not_a_list" => "string"}}
      template = "{% for item in $input.not_a_list %}{{ $item }}{% endfor %}"

      # Should return error indication instead of crashing
      assert {:ok, result} = Template.render(template, context)
      assert result =~ "Error: For loop iterable must be a list"
    end
  end
end