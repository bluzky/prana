defmodule Prana.Integrations.LogicTest do
  use ExUnit.Case
  
  alias Prana.Integrations.Logic

  describe "switch/1 - condition-based format" do
    test "matches first condition with exact value" do
      input_map = %{
        "tier" => "premium",
        "verified" => true,
        "cases" => [
          %{"condition" => "$input.tier", "value" => "premium", "port" => "premium_port"},
          %{"condition" => "$input.verified", "value" => true, "port" => "verified_port"}
        ],
        "default_port" => "default"
      }
      
      context = %{"input" => input_map}
      
      assert {:ok, data, "premium_port"} = Logic.switch(Map.merge(input_map, context))
    end
    
    test "matches second condition when first doesn't match" do
      input_map = %{
        "tier" => "standard", 
        "verified" => true,
        "cases" => [
          %{"condition" => "$input.tier", "value" => "premium", "port" => "premium_port"},
          %{"condition" => "$input.verified", "value" => true, "port" => "verified_port"}
        ],
        "default_port" => "default"
      }
      
      context = %{"input" => input_map}
      
      assert {:ok, data, "verified_port"} = Logic.switch(Map.merge(input_map, context))
    end
    
    test "uses default when no conditions match" do
      input_map = %{
        "tier" => "basic",
        "verified" => false,  
        "cases" => [
          %{"condition" => "$input.tier", "value" => "premium", "port" => "premium_port"},
          %{"condition" => "$input.verified", "value" => true, "port" => "verified_port"}
        ],
        "default_port" => "basic_port",
        "default_data" => %{"discount" => 0.0}
      }
      
      context = %{"input" => input_map}
      
      assert {:ok, %{"discount" => 0.0}, "basic_port"} = Logic.switch(Map.merge(input_map, context))
    end
    
    test "uses custom case data when provided" do
      input_map = %{
        "tier" => "premium",
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
      
      context = %{"input" => input_map}
      
      assert {:ok, %{"discount" => 0.3, "priority" => "high"}, "premium_port"} = 
        Logic.switch(Map.merge(input_map, context))
    end

    test "skips cases with invalid expressions and continues to valid ones" do
      input_map = %{
        "tier" => "premium",
        "cases" => [
          %{"condition" => "$invalid.expression.that.does.not.exist", "value" => "premium", "port" => "invalid_port"},
          %{"condition" => "$input.tier", "value" => "premium", "port" => "valid_port"}
        ],
        "default_port" => "default"
      }
      
      context = %{"input" => input_map}
      
      # Should match second case after first case fails expression evaluation
      assert {:ok, _data, "valid_port"} = Logic.switch(Map.merge(input_map, context))
    end

    test "falls back to default when all expressions are invalid" do
      input_map = %{
        "tier" => "premium",
        "cases" => [
          %{"condition" => "$invalid.expression.one", "value" => "premium", "port" => "invalid_port1"},
          %{"condition" => "$invalid.expression.two", "value" => "basic", "port" => "invalid_port2"}
        ],
        "default_port" => "fallback_port",
        "default_data" => %{"message" => "no valid cases"}
      }
      
      context = %{"input" => input_map}
      
      # Should fall back to default when all cases fail expression evaluation
      assert {:ok, %{"message" => "no valid cases"}, "fallback_port"} = 
        Logic.switch(Map.merge(input_map, context))
    end
  end
  
end