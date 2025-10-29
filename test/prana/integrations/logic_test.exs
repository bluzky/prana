defmodule Prana.Integrations.LogicTest do
  use ExUnit.Case, async: false

  alias Prana.Core.Error
  alias Prana.Integrations.Logic
  alias Prana.Integrations.Logic.IfConditionAction
  alias Prana.Integrations.Logic.SwitchAction

  describe "Logic Integration definition" do
    test "returns correct integration definition" do
      definition = Logic.definition()

      assert definition.name == "logic"
      assert definition.display_name == "Logic"
      assert definition.description == "Core logic operations for conditional branching and data merging"
      assert definition.version == "1.0.0"
      assert definition.category == "core"

      # Check we have the right number of actions
      assert length(definition.actions) == 2

      # Check if_condition action
      if_action_module = Enum.find(definition.actions, &(&1 == IfConditionAction))
      assert if_action_module != nil
      if_action = if_action_module.definition()
      assert if_action.name == "logic.if_condition"
      assert if_action.display_name == "IF Condition"
      assert if_action.input_ports == ["main"]
      assert if_action.output_ports == ["true", "false"]

      # Check switch action
      switch_action_module = Enum.find(definition.actions, &(&1 == SwitchAction))
      assert switch_action_module != nil
      switch_action = switch_action_module.definition()
      assert switch_action.name == "logic.switch"
      assert switch_action.display_name == "Switch"
      assert switch_action.input_ports == ["main"]
      assert switch_action.output_ports == ["*"]
    end
  end

  describe "IfConditionAction" do
    test "prepare/1 returns empty map" do
      node = %{}
      assert {:ok, %{}} = IfConditionAction.prepare(node)
    end

    test "execute/2 returns true port for truthy condition" do
      params = %{condition: "true"}
      context = %{}

      assert {:ok, %{}, "true"} = IfConditionAction.execute(params, context)
    end

    test "execute/2 returns true port for non-empty string condition" do
      params = %{condition: "some value"}
      context = %{}

      assert {:ok, %{}, "true"} = IfConditionAction.execute(params, context)
    end

    test "execute/2 returns false port for falsy condition" do
      params = %{condition: false}
      context = %{}

      assert {:ok, %{}, "false"} = IfConditionAction.execute(params, context)
    end

    test "resume/3 returns error as action does not support suspension" do
      params = %{}
      context = %{}
      resume_data = %{}

      assert {:error, %Error{code: "action_error", message: "IF Condition action does not support suspension/resume", details: nil}} =
               IfConditionAction.resume(params, context, resume_data)
    end
  end

  describe "SwitchAction" do
    test "execute/2 returns first matching case port" do
      params = %{
        :cases => [
          %{condition: true, port: "port1"},
          %{condition: true, port: "port2"}
        ]
      }

      context = %{}

      assert {:ok, nil, "port1"} = SwitchAction.execute(params, context)
    end

    test "execute/2 returns second case when first condition is false" do
      params = %{
        :cases => [
          %{condition: false, port: "port1"},
          %{condition: true, port: "port2"}
        ]
      }

      context = %{}

      assert {:ok, nil, "port2"} = SwitchAction.execute(params, context)
    end

    test "execute/2 returns second case when first condition is nil" do
      params = %{
        :cases => [
          %{condition: nil, port: "port1"},
          %{condition: true, port: "port2"}
        ]
      }

      context = %{}

      assert {:ok, nil, "port2"} = SwitchAction.execute(params, context)
    end

    
    test "execute/2 returns error when no cases match" do
      params = %{
        :cases => [
          %{condition: false, port: "port1"},
          %{condition: nil, port: "port2"}
        ]
      }

      context = %{}

      assert {:error,
              %Error{
                code: "no_matching_case",
                message: "No matching case found",
                details: nil
              }} =
               SwitchAction.execute(params, context)
    end

    test "execute/2 returns error when cases is empty" do
      params = %{:cases => []}
      context = %{}

      assert {:error,
              %Error{
                code: "no_matching_case",
                message: "No matching case found",
                details: nil
              }} =
               SwitchAction.execute(params, context)
    end

    test "execute/2 handles missing cases parameter" do
      params = %{}
      context = %{}

      assert {:error,
              %Error{
                code: "missing_cases",
                message: "Cases parameter is required",
                details: nil
              }} =
               SwitchAction.execute(params, context)
    end

    test "execute/2 processes cases in order" do
      params = %{
        :cases => [
          %{condition: false, port: "port1"},
          %{condition: true, port: "port2"},
          %{condition: true, port: "port3"}
        ]
      }

      context = %{}

      # Should return port2 as it's the first matching case
      assert {:ok, nil, "port2"} = SwitchAction.execute(params, context)
    end

    test "execute/2 handles complex case structures" do
      params = %{
        :cases => [
          %{condition: nil, port: "nil_port"},
          %{condition: false, port: "false_port"},
          %{condition: true, port: "active_port"},
          %{condition: true, port: "default_port"}
        ]
      }

      context = %{}

      # Should return active_port as it's the first true condition
      assert {:ok, nil, "active_port"} = SwitchAction.execute(params, context)
    end
  end
end
