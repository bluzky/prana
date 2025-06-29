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
  end
  
end