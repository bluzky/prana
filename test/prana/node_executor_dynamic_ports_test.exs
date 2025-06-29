defmodule Prana.NodeExecutorDynamicPortsTest do
  use ExUnit.Case

  alias Prana.NodeExecutor
  alias Prana.Action

  describe "dynamic output ports with ['*']" do
    test "allows any port name when output_ports is ['*']" do
      # Create action with dynamic ports
      dynamic_action = %Action{
        name: "test_action",
        output_ports: ["*"],
        default_success_port: "default",
        default_error_port: "error"
      }

      # Test custom port names are allowed
      assert {:ok, %{result: "success"}, "custom_port_name"} = 
        NodeExecutor.process_action_result(
          {:ok, %{result: "success"}, "custom_port_name"}, 
          dynamic_action
        )

      assert {:ok, %{result: "data"}, "very_specific_port"} = 
        NodeExecutor.process_action_result(
          {:ok, %{result: "data"}, "very_specific_port"}, 
          dynamic_action
        )

      # Test error cases with custom ports
      assert {:error, %{"type" => "action_error", "port" => "error_port"}} = 
        NodeExecutor.process_action_result(
          {:error, "something failed", "error_port"}, 
          dynamic_action
        )
    end

    test "still validates ports for non-dynamic actions" do
      # Create action with fixed ports
      fixed_action = %Action{
        name: "test_action",
        output_ports: ["success", "error"],
        default_success_port: "success",
        default_error_port: "error"
      }

      # Valid port should work
      assert {:ok, %{result: "data"}, "success"} = 
        NodeExecutor.process_action_result(
          {:ok, %{result: "data"}, "success"}, 
          fixed_action
        )

      # Invalid port should be rejected
      assert {:error, %{"type" => "invalid_output_port", "port" => "invalid_port"}} = 
        NodeExecutor.process_action_result(
          {:ok, %{result: "data"}, "invalid_port"}, 
          fixed_action
        )
    end

    test "logic switch action uses dynamic ports" do
      # Test that our Logic integration actually uses dynamic ports
      logic_action = Prana.Integrations.Logic.definition().actions["switch"]
      
      assert logic_action.output_ports == ["*"]
      
      # Test with NodeExecutor that custom ports work
      assert {:ok, %{data: "test"}, "premium_port"} = 
        NodeExecutor.process_action_result(
          {:ok, %{data: "test"}, "premium_port"}, 
          logic_action
        )
        
      assert {:ok, %{data: "test"}, "completely_custom_name"} = 
        NodeExecutor.process_action_result(
          {:ok, %{data: "test"}, "completely_custom_name"}, 
          logic_action
        )
    end
  end
end