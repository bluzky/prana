defmodule Prana.Integrations.LogicTest do
  use ExUnit.Case, async: false

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

      # Check if_condition action
      assert Map.has_key?(definition.actions, "if_condition")
      if_action = definition.actions["if_condition"]
      assert if_action.name == "if_condition"
      assert if_action.display_name == "IF Condition"
      assert if_action.module == Prana.Integrations.Logic.IfConditionAction
      assert if_action.input_ports == ["main"]
      assert if_action.output_ports == ["true", "false"]

      # Check switch action
      assert Map.has_key?(definition.actions, "switch")
      switch_action = definition.actions["switch"]
      assert switch_action.name == "switch"
      assert switch_action.display_name == "Switch"
      assert switch_action.module == Prana.Integrations.Logic.SwitchAction
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
      params = %{"condition" => "true"}
      context = %{}

      assert {:ok, %{}, "true"} = IfConditionAction.execute(params, context)
    end

    test "execute/2 returns true port for non-empty string condition" do
      params = %{"condition" => "some value"}
      context = %{}

      assert {:ok, %{}, "true"} = IfConditionAction.execute(params, context)
    end

    test "execute/2 returns false port for falsy condition" do
      params = %{"condition" => false}
      context = %{}

      assert {:ok, %{}, "false"} = IfConditionAction.execute(params, context)
    end

    test "execute/2 returns false port for nil condition" do
      params = %{"condition" => nil}
      context = %{}

      assert {:ok, %{}, "false"} = IfConditionAction.execute(params, context)
    end

    test "execute/2 returns false port for empty string condition" do
      params = %{"condition" => ""}
      context = %{}

      assert {:ok, %{}, "false"} = IfConditionAction.execute(params, context)
    end

    test "execute/2 returns error when condition is missing" do
      params = %{}
      context = %{}

      assert {:error, "Missing required 'condition' field"} = IfConditionAction.execute(params, context)
    end

    test "resume/3 returns error as action does not support suspension" do
      params = %{}
      context = %{}
      resume_data = %{}

      assert {:error, "IF Condition action does not support suspension/resume"} =
               IfConditionAction.resume(params, context, resume_data)
    end
  end

  describe "SwitchAction" do
    test "execute/2 returns first matching case port" do
      params = %{
        "cases" => [
          %{"condition" => "match1", "port" => "port1"},
          %{"condition" => "match2", "port" => "port2"}
        ]
      }

      context = %{}

      assert {:ok, nil, "port1"} = SwitchAction.execute(params, context)
    end

    test "execute/2 returns second case when first condition is empty" do
      params = %{
        "cases" => [
          %{"condition" => "", "port" => "port1"},
          %{"condition" => "match2", "port" => "port2"}
        ]
      }

      context = %{}

      assert {:ok, nil, "port2"} = SwitchAction.execute(params, context)
    end

    test "execute/2 returns second case when first condition is nil" do
      params = %{
        "cases" => [
          %{"condition" => nil, "port" => "port1"},
          %{"condition" => "match2", "port" => "port2"}
        ]
      }

      context = %{}

      assert {:ok, nil, "port2"} = SwitchAction.execute(params, context)
    end

    test "execute/2 uses default port when none specified" do
      params = %{
        "cases" => [
          %{"condition" => "match1"}
        ]
      }

      context = %{}

      assert {:ok, nil, "default"} = SwitchAction.execute(params, context)
    end

    test "execute/2 returns error when no cases match" do
      params = %{
        "cases" => [
          %{"condition" => "", "port" => "port1"},
          %{"condition" => nil, "port" => "port2"}
        ]
      }

      context = %{}

      assert {:error, %Prana.Core.Error{code: "action_error", message: "No matching case found", details: %{"error_type" => "no_matching_case"}}} =
               SwitchAction.execute(params, context)
    end

    test "execute/2 returns error when cases is empty" do
      params = %{"cases" => []}
      context = %{}

      assert {:error, %Prana.Core.Error{code: "action_error", message: "No matching case found", details: %{"error_type" => "no_matching_case"}}} =
               SwitchAction.execute(params, context)
    end

    test "execute/2 handles missing cases parameter" do
      params = %{}
      context = %{}

      assert {:error, %Prana.Core.Error{code: "action_error", message: "No matching case found", details: %{"error_type" => "no_matching_case"}}} =
               SwitchAction.execute(params, context)
    end

    test "execute/2 processes cases in order" do
      params = %{
        "cases" => [
          %{"condition" => "", "port" => "port1"},
          %{"condition" => "first_match", "port" => "port2"},
          %{"condition" => "second_match", "port" => "port3"}
        ]
      }

      context = %{}

      # Should return port2 as it's the first matching case
      assert {:ok, nil, "port2"} = SwitchAction.execute(params, context)
    end

    test "execute/2 handles complex case structures" do
      params = %{
        "cases" => [
          %{"condition" => nil, "port" => "nil_port"},
          %{"condition" => "", "port" => "empty_port"},
          %{"condition" => "active", "port" => "active_port"},
          %{"condition" => "fallback", "port" => "default_port"}
        ]
      }

      context = %{}

      # Should return active_port as it's the first non-empty condition
      assert {:ok, nil, "active_port"} = SwitchAction.execute(params, context)
    end
  end
end
