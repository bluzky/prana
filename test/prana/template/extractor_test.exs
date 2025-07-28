defmodule Prana.Template.ExtractorTest do
  use ExUnit.Case, async: true

  alias Prana.Template.Extractor

  describe "extract/1 with expressions" do
    test "extracts simple expression" do
      template = "Hello {{ $input.name }}!"

      assert {:ok, blocks} = Extractor.extract(template)

      assert blocks == [
               {:literal, "Hello "},
               {:expression, " $input.name "},
               {:literal, "!"}
             ]
    end

    test "extracts multiple expressions" do
      template = "{{ $input.greeting }} {{ $input.name }}!"

      assert {:ok, blocks} = Extractor.extract(template)

      assert blocks == [
               {:expression, " $input.greeting "},
               {:literal, " "},
               {:expression, " $input.name "},
               {:literal, "!"}
             ]
    end

    test "handles template with no expressions" do
      template = "No expressions here"

      assert {:ok, blocks} = Extractor.extract(template)
      assert blocks == [{:literal, "No expressions here"}]
    end

    test "handles empty template" do
      template = ""

      assert {:ok, blocks} = Extractor.extract(template)
      assert blocks == []
    end
  end

  describe "extract/1 with control flow" do
    test "extracts simple for loop" do
      template = "{% for user in $input.users %}{{ user.name }}{% endfor %}"

      assert {:ok, blocks} = Extractor.extract(template)
      assert [control_block] = blocks
      assert {:control, :for_loop, %{variable: "user", iterable: "$input.users"}, body} = control_block
      assert body == [{:expression, " user.name "}]
    end

    test "extracts for loop with literal text" do
      template = "{% for user in $input.users %}Hello {{ user.name }}!{% endfor %}"

      assert {:ok, blocks} = Extractor.extract(template)
      assert [control_block] = blocks
      assert {:control, :for_loop, %{variable: "user", iterable: "$input.users"}, body} = control_block

      assert body == [
               {:literal, "Hello "},
               {:expression, " user.name "},
               {:literal, "!"}
             ]
    end

    test "extracts simple if condition" do
      template = "{% if $input.age >= 18 %}Welcome adult!{% endif %}"

      assert {:ok, blocks} = Extractor.extract(template)
      assert [control_block] = blocks

      assert {:control, :if_condition, %{condition: "$input.age >= 18"}, %{then_body: body, else_body: []}} =
               control_block

      assert body == [{:literal, "Welcome adult!"}]
    end

    test "extracts content before and after control blocks" do
      template = "Before {% for user in $input.users %}{{ user.name }}{% endfor %} After"

      assert {:ok, blocks} = Extractor.extract(template)

      assert [
               {:literal, "Before "},
               {:control, :for_loop, %{variable: "user", iterable: "$input.users"}, [{:expression, " user.name "}]},
               {:literal, " After"}
             ] = blocks
    end
  end

  describe "has_expressions?/1" do
    test "detects expression blocks" do
      assert Extractor.has_expressions?("Hello {{ $input.name }}")
      refute Extractor.has_expressions?("No expressions")
    end

    test "detects control flow blocks" do
      assert Extractor.has_expressions?("{% for user in users %}...{% endfor %}")
      assert Extractor.has_expressions?("{% if condition %}...{% endif %}")
      refute Extractor.has_expressions?("No control flow")
    end

    test "detects mixed blocks" do
      assert Extractor.has_expressions?("{{ expr }} {% for x in y %}...{% endfor %}")
    end
  end

  describe "validation" do
    test "validates mismatched expression braces" do
      assert {:error, reason} = Extractor.extract("{{ missing close")
      assert reason =~ "Mismatched expression braces"
    end

    test "validates mismatched control flow braces" do
      assert {:error, reason} = Extractor.extract("{% missing close")
      assert reason =~ "Mismatched control flow braces"
    end

    test "validates invalid for loop syntax" do
      template = "{% for invalid syntax %}content{% endfor %}"
      assert {:error, reason} = Extractor.extract(template)
      assert reason =~ "Invalid or mismatched control flow blocks"
    end
  end
end
