defmodule Prana.Integrations.LogicTest do
  use ExUnit.Case

  alias Prana.Integrations.Logic.SwitchAction

  describe "switch/1 - condition-based format" do
    test "matches first condition with exact value" do
      # Separate params and context for SwitchAction
      params = %{
        "cases" => [
          %{"condition" => "$input.tier", "value" => "premium", "port" => "premium_port"},
          %{"condition" => "$input.verified", "value" => true, "port" => "verified_port"}
        ],
        "default_port" => "default"
      }

      context = %{
        "$input" => %{
          "tier" => "premium",
          "verified" => true
        },
        "$nodes" => %{},
        "$variables" => %{}
      }

      assert {:ok, _data, "premium_port"} = SwitchAction.execute(params, context)
    end

    test "matches second condition when first doesn't match" do
      params = %{
        "cases" => [
          %{"condition" => "$input.tier", "value" => "premium", "port" => "premium_port"},
          %{"condition" => "$input.verified", "value" => true, "port" => "verified_port"}
        ],
        "default_port" => "default"
      }

      context = %{
        "$input" => %{
          "tier" => "standard",
          "verified" => true
        },
        "$nodes" => %{},
        "$variables" => %{}
      }

      assert {:ok, _data, "verified_port"} = SwitchAction.execute(params, context)
    end

    test "uses default when no conditions match" do
      params = %{
        "cases" => [
          %{"condition" => "$input.tier", "value" => "premium", "port" => "premium_port"},
          %{"condition" => "$input.verified", "value" => true, "port" => "verified_port"}
        ],
        "default_port" => "basic_port",
        "default_data" => %{"discount" => +0.0}
      }

      context = %{
        "$input" => %{
          "tier" => "basic",
          "verified" => false
        },
        "$nodes" => %{},
        "$variables" => %{}
      }

      assert {:ok, %{"discount" => +0.0}, "basic_port"} = SwitchAction.execute(params, context)
    end

    test "uses custom case data when provided" do
      params = %{
        "cases" => [
          %{
            "condition" => "$input.tier",
            "value" => "premium",
            "port" => "premium_port",
            "data" => %{"discount" => 0.3, "priority" => "high"}
          }
        ],
        "default_port" => "default"
      }

      context = %{
        "$input" => %{
          "tier" => "premium"
        },
        "$nodes" => %{},
        "$variables" => %{}
      }

      assert {:ok, %{"discount" => 0.3, "priority" => "high"}, "premium_port"} =
               SwitchAction.execute(params, context)
    end

    test "skips cases with invalid expressions and continues to valid ones" do
      params = %{
        "cases" => [
          %{"condition" => "$invalid.expression.that.does.not.exist", "value" => "premium", "port" => "invalid_port"},
          %{"condition" => "$input.tier", "value" => "premium", "port" => "valid_port"}
        ],
        "default_port" => "default"
      }

      context = %{
        "$input" => %{
          "tier" => "premium"
        },
        "$nodes" => %{},
        "$variables" => %{}
      }

      # Should match second case after first case fails expression evaluation
      assert {:ok, _data, "valid_port"} = SwitchAction.execute(params, context)
    end

    test "falls back to default when all expressions are invalid" do
      params = %{
        "cases" => [
          %{"condition" => "$invalid.expression.one", "value" => "premium", "port" => "invalid_port1"},
          %{"condition" => "$invalid.expression.two", "value" => "basic", "port" => "invalid_port2"}
        ],
        "default_port" => "fallback_port",
        "default_data" => %{"message" => "no valid cases"}
      }

      context = %{
        "$input" => %{
          "tier" => "premium"
        },
        "$nodes" => %{},
        "$variables" => %{}
      }

      # Should fall back to default when all cases fail expression evaluation
      assert {:ok, %{"message" => "no valid cases"}, "fallback_port"} =
               SwitchAction.execute(params, context)
    end
  end
end
