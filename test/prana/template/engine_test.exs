defmodule Prana.TemplateTest do
  use ExUnit.Case, async: false

  alias Prana.Template

  describe "template engine integration" do
    test "basic template rendering works" do
      context = %{"$input" => %{"name" => "World"}}
      assert {:ok, "Hello World!"} = Template.render("Hello {{ $input.name }}!", context)
    end

    test "handles empty context" do
      assert {:ok, "Hello !"} = Template.render("Hello {{ $input.name }}!", %{})
    end

    test "handles malformed expressions gracefully" do
      context = %{"$input" => %{"name" => "World"}}
      
      # Unclosed expression becomes literal text
      assert {:ok, "Hello {{ $input.name"} = Template.render("Hello {{ $input.name", context)
      
      # Invalid syntax becomes literal text (graceful degradation)
      assert {:ok, "Hello {{ $input. }}"} = Template.render("Hello {{ $input. }}", context)
    end

    test "template engine performance with complex expressions" do
      context = %{
        "$input" => %{
          "users" => Enum.map(1..100, fn i -> %{"id" => i, "name" => "User#{i}"} end)
        }
      }
      
      template = "{% for user in $input.users %}{{ user.name }} {% endfor %}"
      
      {time, {:ok, result}} = :timer.tc(fn -> Template.render(template, context) end)
      
      # Should complete within reasonable time (1 second = 1,000,000 microseconds)
      assert time < 1_000_000
      assert String.contains?(result, "User1")
      assert String.contains?(result, "User100")
    end
  end
end