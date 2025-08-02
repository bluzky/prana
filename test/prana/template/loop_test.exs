defmodule Prana.Template.LoopTest do
  use ExUnit.Case, async: true

  alias Prana.Template

  describe "for loop rendering" do
    setup do
      context = %{
        "$input" => %{
          "users" => [
            %{"name" => "Alice", "age" => 25},
            %{"name" => "Bob", "age" => 17},
            %{"name" => "Carol", "age" => 30}
          ],
          "empty_list" => [],
          "numbers" => [1, 2, 3, 4, 5],
          "strings" => ["hello", "world", "test"]
        }
      }

      {:ok, context: context}
    end

    test "renders simple for loop", %{context: context} do
      template = "{% for user in $input.users %}{{ user.name }} {% endfor %}"

      assert {:ok, result} = Template.render(template, context)
      assert result == "Alice Bob Carol "
    end

    test "renders for loop with loop_index", %{context: context} do
      template = "{% for user in $input.users %}{{ loop_index }}: {{ user.name }} {% endfor %}"

      assert {:ok, result} = Template.render(template, context)
      assert result == "0: Alice 1: Bob 2: Carol "
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

    test "renders for loop with numbers", %{context: context} do
      template = "{% for num in $input.numbers %}{{ num }}. {% endfor %}"

      assert {:ok, result} = Template.render(template, context)
      assert result == "1. 2. 3. 4. 5. "
    end

    test "renders nested content with loop_index", %{context: context} do
      template = """
      {% for user in $input.users %}
      User {{ loop_index }}: {{ user.name }} is {{ user.age }} years old
      {% endfor %}
      """

      assert {:ok, result} = Template.render(template, context)
      assert String.contains?(result, "User 0: Alice is 25 years old")
      assert String.contains?(result, "User 1: Bob is 17 years old")
      assert String.contains?(result, "User 2: Carol is 30 years old")
    end

    test "handles loop variable scoping correctly", %{context: context} do
      template = "{% for item in $input.strings %}{{ item }}: {{ loop_index }} {% endfor %}"

      assert {:ok, result} = Template.render(template, context)
      assert result == "hello: 0 world: 1 test: 2 "
    end

    test "handles for loop with non-list gracefully" do
      context = %{"$input" => %{"not_a_list" => "string"}}
      template = "{% for item in $input.not_a_list %}{{ item }}{% endfor %}"

      assert {:ok, result} = Template.render(template, context)
      assert result =~ "Error: For loop iterable must be a list"
    end

    test "handles missing collection gracefully" do
      context = %{"$input" => %{}}
      template = "{% for item in $input.missing %}{{ item }}{% endfor %}"

      assert {:ok, result} = Template.render(template, context)
      assert result =~ "Error: For loop iterable must be a list"
    end

    test "loop_index starts at 0 and increments correctly" do
      context = %{"$input" => %{"items" => ["a", "b", "c"]}}
      template = "{% for item in $input.items %}[{{ loop_index }}:{{ item }}] {% endfor %}"

      assert {:ok, result} = Template.render(template, context)
      assert result == "[0:a] [1:b] [2:c] "
    end
  end
end
