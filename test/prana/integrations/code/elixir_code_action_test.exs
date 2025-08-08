defmodule Prana.Integrations.Code.ElixirCodeActionTest do
  use ExUnit.Case, async: true

  alias Prana.Integrations.Code.ElixirCodeAction
  alias Prana.Integrations.Code.Sandbox

  describe "execute/2" do
    test "executes simple arithmetic in compiled mode" do
      params = %{"code" => "def run(_input, _context), do: 1 + 2"}

      context = %{
        "$input" => %{},
        "$nodes" => %{},
        "$vars" => %{},
        "$env" => %{},
        "$workflow" => %{"id" => "test_workflow"},
        "$execution" => %{
          "current_node_key" => "test_node1"
        }
      }

      assert {:ok, 3} = ElixirCodeAction.execute(params, context)
    end

    test "executes string operations in compiled mode" do
      params = %{"code" => "def run(_input, _context), do: String.upcase(\"hello\")"}

      context = %{
        "$input" => %{},
        "$nodes" => %{},
        "$vars" => %{},
        "$env" => %{},
        "$workflow" => %{"id" => "test_workflow"},
        "$execution" => %{
          "current_node_key" => "test_node2"
        }
      }

      assert {:ok, "HELLO"} = ElixirCodeAction.execute(params, context)
    end

    test "uses input parameter in compiled mode" do
      params = %{"code" => "def run(input, _context), do: input[\"name\"]"}

      context = %{
        "$input" => %{"name" => "John"},
        "$nodes" => %{},
        "$vars" => %{},
        "$env" => %{},
        "$workflow" => %{"id" => "test_workflow"},
        "$execution" => %{
          "current_node_key" => "test_node3"
        }
      }

      assert {:ok, "John"} = ElixirCodeAction.execute(params, context)
    end

    test "executes complex expressions" do
      params = %{"code" => "def run(_input, _context), do: Enum.map([1, 2, 3], fn x -> x * 2 end)"}

      context = %{
        "$input" => %{},
        "$nodes" => %{},
        "$vars" => %{},
        "$env" => %{},
        "$workflow" => %{"id" => "test_workflow"},
        "$execution" => %{
          "current_node_key" => "test_node4"
        }
      }

      assert {:ok, [2, 4, 6]} = ElixirCodeAction.execute(params, context)
    end

    test "rejects dangerous code" do
      params = %{"code" => "def run(_input, _context), do: File.read!(\"/etc/passwd\")"}

      context = %{
        "$input" => %{},
        "$nodes" => %{},
        "$vars" => %{},
        "$env" => %{},
        "$workflow" => %{"id" => "test_workflow"},
        "$execution" => %{
          "current_node_key" => "test_node5"
        }
      }

      assert {:error, error_msg} = ElixirCodeAction.execute(params, context)
      assert String.contains?(error_msg, "not allowed")
    end

    test "uses context vars from workflow" do
      params = %{"code" => ~s{def run(input, context), do: input["name"] <> " in " <> context.env["environment"]}}

      context = %{
        "$input" => %{"name" => "Alice"},
        "$nodes" => %{"api" => %{"response" => %{"status" => "ok"}}},
        "$vars" => %{},
        "$env" => %{"environment" => "production"},
        "$workflow" => %{"id" => "test_workflow"},
        "$execution" => %{
          "current_node_key" => "test_node_ctx"
        }
      }

      assert {:ok, "Alice in production"} = ElixirCodeAction.execute(params, context)
    end

    test "rejects non-run function definitions" do
      params = %{"code" => "def hello, do: :world"}

      context = %{
        "$input" => %{},
        "$nodes" => %{},
        "$vars" => %{},
        "$env" => %{},
        "$workflow" => %{"id" => "test_workflow"},
        "$execution" => %{
          "current_node_key" => "test_node6"
        }
      }

      assert {:error, error_msg} = ElixirCodeAction.execute(params, context)
      assert String.contains?(error_msg, "Expecting only `def run` at the top level")
    end

    test "provides clear error messages for runtime errors" do
      params = %{"code" => "def run(input, _context), do: input.nonexistent_key"}

      context = %{
        "$input" => %{"name" => "Test"},
        "$nodes" => %{},
        "$vars" => %{},
        "$env" => %{},
        "$workflow" => %{"id" => "test_workflow"},
        "$execution" => %{
          "current_node_key" => "test_node_error"
        }
      }

      assert {:error, error_msg} = ElixirCodeAction.execute(params, context)
      assert String.contains?(error_msg, "Key error") or String.contains?(error_msg, "key :nonexistent_key")
    end

    test "validates required code parameter" do
      params = %{}
      context = %{}

      assert {:error, "Code parameter is required"} = ElixirCodeAction.execute(params, context)
    end

    test "handles fresh context on each execution (no stale data)" do
      params = %{"code" => "def run(input, _context), do: input[\"value\"]"}

      # First execution with value "first"
      context1 = %{
        "$input" => %{"value" => "first"},
        "$workflow" => %{"id" => "test_workflow"},
        "$execution" => %{"current_node_key" => "test_context_node"}
      }

      assert {:ok, "first"} = ElixirCodeAction.execute(params, context1)

      # Second execution with same node but different input value
      context2 = %{
        "$input" => %{"value" => "second"},
        "$workflow" => %{"id" => "test_workflow"},
        "$execution" => %{"current_node_key" => "test_context_node"}
      }

      # Should return "second", not "first" (proving no context baking)
      assert {:ok, "second"} = ElixirCodeAction.execute(params, context2)
    end

    test "interpreted and compiled modes handle context identically" do
      # Test that both modes produce the same result with the same context
      code = ~s|def run(input, context), do: {input["name"], context.env["mode"]}|

      context = %{
        "$input" => %{"name" => "Alice"},
        "$nodes" => %{},
        "$vars" => %{},
        "$env" => %{"mode" => "test"},
        "$workflow" => %{"id" => "test_workflow"},
        "$execution" => %{"current_node_key" => "test_mode_consistency"}
      }

      # Test interpreted mode
      {:ok, interpreted_result} = Sandbox.run_interpreted(code, context)

      # Test compiled mode  
      {:ok, compiled_result} = Sandbox.run_compiled(code, "test_consistency", context)

      # Both should return the same result
      assert interpreted_result == compiled_result
      assert interpreted_result == {"Alice", "test"}
    end
  end

  describe "params_schema/0" do
    test "returns correct parameter schema" do
      schema = ElixirCodeAction.params_schema()

      assert schema["code"]["type"] == "string"
      assert schema["code"]["required"] == true
    end
  end

  describe "validate_params/1" do
    test "validates correct parameters" do
      params = %{"code" => "1 + 2"}
      assert {:ok, ^params} = ElixirCodeAction.validate_params(params)
    end

    test "rejects missing code" do
      params = %{}
      assert {:error, errors} = ElixirCodeAction.validate_params(params)
      assert "Code parameter is required" in errors
    end

    test "rejects non-string code" do
      params = %{"code" => 123}
      assert {:error, errors} = ElixirCodeAction.validate_params(params)
      assert "Code must be a string" in errors
    end
  end
end
