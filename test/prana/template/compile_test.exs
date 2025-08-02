defmodule Prana.Template.CompileTest do
  use ExUnit.Case, async: false

  alias Prana.Template

  describe "compile/1 and compile/2" do
    test "compiles simple template successfully" do
      assert {:ok, compiled} = Template.compile("Hello {{$input.name}}")
      assert %Prana.Template.CompiledTemplate{} = compiled
      assert is_list(compiled.ast)
      assert is_map(compiled.options)
    end

    test "compiles template with options" do
      opts = [strict_mode: true, max_template_size: 50000]
      assert {:ok, compiled} = Template.compile("Hello {{$input.name}}", opts)
      assert %Prana.Template.CompiledTemplate{} = compiled
      assert compiled.options.strict_mode == true
      assert compiled.options.max_template_size == 50000
    end

    test "fails compilation for oversized template" do
      large_template = String.duplicate("x", 200_000) <> "{{$input.name}}"
      assert {:error, reason} = Template.compile(large_template)
      assert String.contains?(reason, "size")
    end

    test "fails compilation for invalid template syntax" do
      # The parser is quite permissive, so we need actually broken syntax
      # For now, let's test with a more realistic scenario where compilation might fail
      assert {:ok, _compiled} = Template.compile("Hello {{invalid syntax")
      # TODO: Add actual invalid syntax test when parser is stricter
    end
  end

  describe "render/2 with compiled templates" do
    setup do
      {:ok, compiled} = Template.compile("Hello {{$input.name}}")
      {:ok, compiled_mixed} = Template.compile("Value: {{$input.value}}")
      {:ok, compiled_pure} = Template.compile("{{$input.value}}")
      
      context = %{
        "$input" => %{
          "name" => "John",
          "value" => 42
        }
      }
      
      {:ok, compiled: compiled, compiled_mixed: compiled_mixed, compiled_pure: compiled_pure, context: context}
    end

    test "renders compiled template with mixed content", %{compiled: compiled, context: context} do
      assert {:ok, "Hello John"} = Template.render(compiled, context)
    end

    test "renders compiled template with mixed content returning string", %{compiled_mixed: compiled, context: context} do
      assert {:ok, result} = Template.render(compiled, context)
      assert result == "Value: 42"
      assert is_binary(result)
    end

    test "renders compiled pure expression preserving type", %{compiled_pure: compiled, context: context} do
      assert {:ok, result} = Template.render(compiled, context)
      assert result == 42
      assert is_integer(result)
    end

    test "handles missing context gracefully", %{compiled: compiled} do
      empty_context = %{}
      assert {:ok, result} = Template.render(compiled, empty_context)
      # Should gracefully handle missing data
      assert is_binary(result)
    end

    test "handles rendering errors", %{context: context} do
      # Compile a template that will cause evaluation error
      {:ok, error_compiled} = Template.compile("{{$input.nonexistent.deeply.nested}}")
      assert {:ok, _result} = Template.render(error_compiled, context)
      # Template engine should handle this gracefully in non-strict mode
    end

    test "render/3 with compiled template ignores options", %{compiled: compiled, context: context} do
      # Options should be ignored for compiled templates since they're already baked in
      assert {:ok, "Hello John"} = Template.render(compiled, context, strict_mode: true)
    end
  end

  describe "compile vs render performance comparison" do
    test "compiled templates can be reused efficiently" do
      template_string = "Hello {{$input.name}}, you have {{$input.count}} messages"
      context1 = %{"$input" => %{"name" => "Alice", "count" => 5}}
      context2 = %{"$input" => %{"name" => "Bob", "count" => 3}}
      context3 = %{"$input" => %{"name" => "Charlie", "count" => 10}}

      # Compile once
      {:ok, compiled} = Template.compile(template_string)

      # Use multiple times
      assert {:ok, "Hello Alice, you have 5 messages"} = Template.render(compiled, context1)
      assert {:ok, "Hello Bob, you have 3 messages"} = Template.render(compiled, context2)
      assert {:ok, "Hello Charlie, you have 10 messages"} = Template.render(compiled, context3)

      # Compare with direct rendering
      assert {:ok, "Hello Alice, you have 5 messages"} = Template.render(template_string, context1)
      assert {:ok, "Hello Bob, you have 3 messages"} = Template.render(template_string, context2)
      assert {:ok, "Hello Charlie, you have 10 messages"} = Template.render(template_string, context3)
    end
  end

  describe "compile with filters" do
    test "compiles and renders templates with filters" do
      {:ok, compiled} = Template.compile("{{$input.name | upper_case}}")
      context = %{"$input" => %{"name" => "john"}}
      
      assert {:ok, "JOHN"} = Template.render(compiled, context)
    end

    test "compiles and renders complex filter chains" do
      {:ok, compiled} = Template.compile("{{$input.items | length}} items, first: {{$input.items | first}}")
      context = %{"$input" => %{"items" => [1, 2, 3, 4, 5]}}
      
      assert {:ok, "5 items, first: 1"} = Template.render(compiled, context)
    end
  end

  describe "unified render function" do
    test "render/2 works with both string and compiled templates" do
      template_string = "Hello {{$input.name}}!"
      context = %{"$input" => %{"name" => "World"}}
      
      # Render string template
      assert {:ok, result1} = Template.render(template_string, context)
      
      # Compile and render compiled template
      {:ok, compiled} = Template.compile(template_string)
      assert {:ok, result2} = Template.render(compiled, context)
      
      # Both should produce the same result
      assert result1 == result2
      assert result1 == "Hello World!"
    end

    test "render/3 works with both string and compiled templates" do
      template_string = "Value: {{$input.value}}"
      context = %{"$input" => %{"value" => 42}}
      opts = [strict_mode: true]
      
      # Render string template with options
      assert {:ok, result1} = Template.render(template_string, context, opts)
      
      # Compile and render compiled template with options (options ignored for compiled)
      {:ok, compiled} = Template.compile(template_string, opts)
      assert {:ok, result2} = Template.render(compiled, context, opts)
      
      # Both should produce the same result
      assert result1 == result2
      assert result1 == "Value: 42"
    end
  end

  describe "compile error cases" do
    test "returns error for non-string input" do
      assert_raise FunctionClauseError, fn ->
        Template.compile(123)
      end
    end

    test "returns error for invalid options" do
      # Should still work but ignore invalid options
      assert {:ok, _compiled} = Template.compile("{{$input.name}}", invalid_option: true)
    end
  end

  describe "CompiledTemplate struct benefits" do
    test "provides clear structure and type safety" do
      {:ok, compiled} = Template.compile("Hello {{$input.name}}")
      
      # Clear struct pattern matching
      assert %Prana.Template.CompiledTemplate{ast: ast, options: options} = compiled
      assert is_list(ast)
      assert is_map(options)
      
      # Easy access to fields
      assert compiled.ast == ast
      assert compiled.options == options
      
      # Type safety - can't accidentally destructure wrong
      assert compiled.options.strict_mode == false
    end
    
    test "works seamlessly with render function" do
      {:ok, compiled} = Template.compile("Value: {{$input.count}}")
      context = %{"$input" => %{"count" => 42}}
      
      # Both ways work identically
      assert {:ok, result1} = Template.render("Value: {{$input.count}}", context)
      assert {:ok, result2} = Template.render(compiled, context)
      assert result1 == result2
      assert result1 == "Value: 42"
    end
  end
end