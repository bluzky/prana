defmodule Prana.Template.ProcessMapTest do
  use ExUnit.Case, async: false

  alias Prana.Template

  describe "process_map functionality" do
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

      assert {:ok, result} = Template.process_map(input_map, context)
      assert result["greeting"] == "John"
      assert result["age"] == 25
      assert result["static"] == "Hello World"
    end

    test "process_map maintains original types for single expressions", %{context: context} do
      input_map = %{
        # String
        "name" => "{{ $input.user.name }}",
        # Integer
        "age" => "{{ $input.user.age }}",
        # nil
        "missing" => "{{ $input.missing_field }}"
      }

      assert {:ok, result} = Template.process_map(input_map, context)
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

      assert {:ok, result} = Template.process_map(input_map, context)
      assert result["user_info"]["display_name"] == "John"
      assert result["user_info"]["years_old"] == 25
      assert result["metadata"] == ["John", 25]
    end

    test "process_map works with mixed content templates" do
      input_map = %{
        "greeting" => "Hello {{ $input.name }}!",
        "message" => "Welcome {{ $input.name | upper_case }}"
      }

      context = %{"$input" => %{"name" => "alice"}}

      expected = %{
        "greeting" => "Hello alice!",
        "message" => "Welcome ALICE"
      }

      assert {:ok, ^expected} = Template.process_map(input_map, context)
    end
  end
end