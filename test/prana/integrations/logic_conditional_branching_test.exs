defmodule Prana.Integrations.LogicConditionalBranchingTest do
  @moduledoc """
  Tests for Logic integration conditional branching patterns in GraphExecutor.

  This test suite verifies that IF/ELSE and Switch patterns work correctly
  with the GraphExecutor's conditional branching logic.
  """

  use ExUnit.Case, async: false

  alias Prana.Connection
  alias Prana.GraphExecutor
  alias Prana.IntegrationRegistry
  alias Prana.Integrations.Logic
  alias Prana.Integrations.Logic.IfConditionAction
  alias Prana.Integrations.Logic.SwitchAction
  alias Prana.Node
  alias Prana.TestSupport.TestIntegration
  alias Prana.Workflow
  alias Prana.WorkflowCompiler
  alias Prana.WorkflowSettings

  # Helper functions for handling map-based node_executions
  defp get_all_node_executions(execution) do
    case execution.node_executions do
      node_executions_map when is_map(node_executions_map) ->
        node_executions_map
        |> Enum.flat_map(fn {_node_id, executions} -> executions end)
        |> Enum.sort_by(& &1.execution_index)

      node_executions_list when is_list(node_executions_list) ->
        node_executions_list
    end
  end

  defp count_node_executions(execution) do
    execution |> get_all_node_executions() |> length()
  end

  defp get_node_execution(execution, node_key) do
    case execution.node_executions do
      node_executions_map when is_map(node_executions_map) ->
        node_executions_map
        |> Map.get(node_key, [])
        |> List.last()

      node_executions_list when is_list(node_executions_list) ->
        Enum.find(node_executions_list, fn ne -> ne.node_key == node_key end)
    end
  end

  setup do
    # Start the IntegrationRegistry GenServer for testing
    {:ok, registry_pid} = Prana.IntegrationRegistry.start_link()

    # Register integrations - ensure modules are loaded first
    Code.ensure_loaded(TestIntegration)
    Code.ensure_loaded(Logic)
    Code.ensure_loaded(IfConditionAction)
    Code.ensure_loaded(SwitchAction)

    :ok = IntegrationRegistry.register_integration(TestIntegration)
    :ok = IntegrationRegistry.register_integration(Logic)

    on_exit(fn ->
      if Process.alive?(registry_pid) do
        GenServer.stop(registry_pid)
      end
    end)

    :ok
  end

  describe "IF/ELSE conditional branching" do
    test "IF condition routes to true branch when condition is truthy" do
      # Create workflow: trigger → if_condition → true_branch
      trigger_node = %Node{
        key: "trigger",
        name: "Trigger",
        integration_name: "test",
        action_name: "trigger_action",
        params: %{}
      }

      if_node = %Node{
        key: "if_condition",
        name: "IF Condition",
        integration_name: "logic",
        action_name: "if_condition",
        params: %{"condition" => "true"}
      }

      true_branch = %Node{
        key: "true_branch",
        name: "True Branch",
        integration_name: "test",
        action_name: "simple_action",
        params: %{}
      }

      false_branch = %Node{
        key: "false_branch",
        name: "False Branch",
        integration_name: "test",
        action_name: "simple_action",
        params: %{}
      }

      workflow = %Workflow{
        id: "test_workflow",
        name: "Test IF/ELSE Workflow",
        nodes: [trigger_node, if_node, true_branch, false_branch],
        connections: [
          %Connection{from: "trigger", from_port: "success", to: "if_condition", to_port: "input"},
          %Connection{from: "if_condition", from_port: "true", to: "true_branch", to_port: "input"},
          %Connection{from: "if_condition", from_port: "false", to: "false_branch", to_port: "input"}
        ],
        settings: %WorkflowSettings{}
      }

      # Compile and execute workflow
      {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "trigger")

      context = %{
        workflow_loader: fn _id -> {:error, "not implemented"} end,
        variables: %{},
        metadata: %{}
      }

      {:ok, result} = GraphExecutor.execute_graph(execution_graph, context)

      # Verify execution results
      assert result.status == :completed
      # trigger, if_condition, true_branch
      assert count_node_executions(result) == 3

      # Verify only true branch was executed
      assert get_node_execution(result, "trigger").status == :completed
      assert get_node_execution(result, "if_condition").status == :completed
      assert get_node_execution(result, "if_condition").output_port == "true"
      assert get_node_execution(result, "true_branch").status == :completed
      assert get_node_execution(result, "false_branch") == nil
    end

    test "IF condition routes to false branch when condition is falsy" do
      # Create workflow: trigger → if_condition → false_branch
      trigger_node = %Node{
        key: "trigger",
        name: "Trigger",
        integration_name: "test",
        action_name: "trigger_action",
        params: %{}
      }

      if_node = %Node{
        key: "if_condition",
        name: "IF Condition",
        integration_name: "logic",
        action_name: "if_condition",
        params: %{"condition" => ""}
      }

      true_branch = %Node{
        key: "true_branch",
        name: "True Branch",
        integration_name: "test",
        action_name: "simple_action",
        params: %{}
      }

      false_branch = %Node{
        key: "false_branch",
        name: "False Branch",
        integration_name: "test",
        action_name: "simple_action",
        params: %{}
      }

      workflow = %Workflow{
        id: "test_workflow",
        name: "Test IF/ELSE Workflow",
        nodes: [trigger_node, if_node, true_branch, false_branch],
        connections: [
          %Connection{from: "trigger", from_port: "success", to: "if_condition", to_port: "input"},
          %Connection{from: "if_condition", from_port: "true", to: "true_branch", to_port: "input"},
          %Connection{from: "if_condition", from_port: "false", to: "false_branch", to_port: "input"}
        ],
        settings: %WorkflowSettings{}
      }

      # Compile and execute workflow
      {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "trigger")

      context = %{
        workflow_loader: fn _id -> {:error, "not implemented"} end,
        variables: %{},
        metadata: %{}
      }

      {:ok, result} = GraphExecutor.execute_graph(execution_graph, context)

      # Verify execution results
      assert result.status == :completed
      # trigger, if_condition, false_branch
      assert count_node_executions(result) == 3

      # Verify only false branch was executed
      assert get_node_execution(result, "trigger").status == :completed
      assert get_node_execution(result, "if_condition").status == :completed
      assert get_node_execution(result, "if_condition").output_port == "false"
      assert get_node_execution(result, "false_branch").status == :completed
      assert get_node_execution(result, "true_branch") == nil
    end

    test "IF condition with diamond pattern converges correctly" do
      # Create workflow: trigger → if_condition → (true_branch OR false_branch) → merge
      trigger_node = %Node{
        key: "trigger",
        name: "Trigger",
        integration_name: "test",
        action_name: "trigger_action",
        params: %{}
      }

      if_node = %Node{
        key: "if_condition",
        name: "IF Condition",
        integration_name: "logic",
        action_name: "if_condition",
        params: %{"condition" => "true"}
      }

      true_branch = %Node{
        key: "true_branch",
        name: "True Branch",
        integration_name: "test",
        action_name: "simple_action",
        params: %{}
      }

      false_branch = %Node{
        key: "false_branch",
        name: "False Branch",
        integration_name: "test",
        action_name: "simple_action",
        params: %{}
      }

      merge_node = %Node{
        key: "merge",
        name: "Merge",
        integration_name: "test",
        action_name: "simple_action",
        params: %{}
      }

      workflow = %Workflow{
        id: "test_workflow",
        name: "Test IF/ELSE Diamond Workflow",
        nodes: [trigger_node, if_node, true_branch, false_branch, merge_node],
        connections: [
          %Connection{from: "trigger", from_port: "success", to: "if_condition", to_port: "input"},
          %Connection{from: "if_condition", from_port: "true", to: "true_branch", to_port: "input"},
          %Connection{from: "if_condition", from_port: "false", to: "false_branch", to_port: "input"},
          %Connection{from: "true_branch", from_port: "success", to: "merge", to_port: "input"},
          %Connection{from: "false_branch", from_port: "success", to: "merge", to_port: "input"}
        ],
        settings: %WorkflowSettings{}
      }

      # Compile and execute workflow
      {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "trigger")

      context = %{
        workflow_loader: fn _id -> {:error, "not implemented"} end,
        variables: %{},
        metadata: %{}
      }

      {:ok, result} = GraphExecutor.execute_graph(execution_graph, context)

      # Verify execution results
      assert result.status == :completed
      # trigger, if_condition, true_branch, merge
      assert count_node_executions(result) == 4

      # Verify execution path
      assert get_node_execution(result, "trigger").status == :completed
      assert get_node_execution(result, "if_condition").status == :completed
      assert get_node_execution(result, "if_condition").output_port == "true"
      assert get_node_execution(result, "true_branch").status == :completed
      assert get_node_execution(result, "merge").status == :completed
      assert get_node_execution(result, "false_branch") == nil
    end
  end

  describe "Switch conditional branching" do
    test "Switch routes to first matching case" do
      # Create workflow: trigger → switch → case1_branch
      trigger_node = %Node{
        key: "trigger",
        name: "Trigger",
        integration_name: "test",
        action_name: "trigger_action",
        params: %{}
      }

      switch_node = %Node{
        key: "switch",
        name: "Switch",
        integration_name: "logic",
        action_name: "switch",
        params: %{
          "cases" => [
            %{"condition" => "match1", "port" => "case1"},
            %{"condition" => "match2", "port" => "case2"}
          ]
        }
      }

      case1_branch = %Node{
        key: "case1_branch",
        name: "Case 1 Branch",
        integration_name: "test",
        action_name: "simple_action",
        params: %{}
      }

      case2_branch = %Node{
        key: "case2_branch",
        name: "Case 2 Branch",
        integration_name: "test",
        action_name: "simple_action",
        params: %{}
      }

      workflow = %Workflow{
        id: "test_workflow",
        name: "Test Switch Workflow",
        nodes: [trigger_node, switch_node, case1_branch, case2_branch],
        connections: [
          %Connection{from: "trigger", from_port: "success", to: "switch", to_port: "input"},
          %Connection{from: "switch", from_port: "case1", to: "case1_branch", to_port: "input"},
          %Connection{from: "switch", from_port: "case2", to: "case2_branch", to_port: "input"}
        ],
        settings: %WorkflowSettings{}
      }

      # Compile and execute workflow
      {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "trigger")

      context = %{
        workflow_loader: fn _id -> {:error, "not implemented"} end,
        variables: %{},
        metadata: %{}
      }

      {:ok, result} = GraphExecutor.execute_graph(execution_graph, context)

      # Verify execution results
      assert result.status == :completed
      # trigger, switch, case1_branch
      assert count_node_executions(result) == 3

      # Verify only case1 branch was executed
      assert get_node_execution(result, "trigger").status == :completed
      assert get_node_execution(result, "switch").status == :completed
      assert get_node_execution(result, "switch").output_port == "case1"
      assert get_node_execution(result, "case1_branch").status == :completed
      assert get_node_execution(result, "case2_branch") == nil
    end

    test "Switch routes to second case when first condition is empty" do
      # Create workflow: trigger → switch → case2_branch
      trigger_node = %Node{
        key: "trigger",
        name: "Trigger",
        integration_name: "test",
        action_name: "trigger_action",
        params: %{}
      }

      switch_node = %Node{
        key: "switch",
        name: "Switch",
        integration_name: "logic",
        action_name: "switch",
        params: %{
          "cases" => [
            %{"condition" => "", "port" => "case1"},
            %{"condition" => "match2", "port" => "case2"}
          ]
        }
      }

      case1_branch = %Node{
        key: "case1_branch",
        name: "Case 1 Branch",
        integration_name: "test",
        action_name: "simple_action",
        params: %{}
      }

      case2_branch = %Node{
        key: "case2_branch",
        name: "Case 2 Branch",
        integration_name: "test",
        action_name: "simple_action",
        params: %{}
      }

      workflow = %Workflow{
        id: "test_workflow",
        name: "Test Switch Workflow",
        nodes: [trigger_node, switch_node, case1_branch, case2_branch],
        connections: [
          %Connection{from: "trigger", from_port: "success", to: "switch", to_port: "input"},
          %Connection{from: "switch", from_port: "case1", to: "case1_branch", to_port: "input"},
          %Connection{from: "switch", from_port: "case2", to: "case2_branch", to_port: "input"}
        ],
        settings: %WorkflowSettings{}
      }

      # Compile and execute workflow
      {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "trigger")

      context = %{
        workflow_loader: fn _id -> {:error, "not implemented"} end,
        variables: %{},
        metadata: %{}
      }

      {:ok, result} = GraphExecutor.execute_graph(execution_graph, context)

      # Verify execution results
      assert result.status == :completed
      # trigger, switch, case2_branch
      assert count_node_executions(result) == 3

      # Verify only case2 branch was executed
      assert get_node_execution(result, "trigger").status == :completed
      assert get_node_execution(result, "switch").status == :completed
      assert get_node_execution(result, "switch").output_port == "case2"
      assert get_node_execution(result, "case2_branch").status == :completed
      assert get_node_execution(result, "case1_branch") == nil
    end

    test "Switch with multiple cases and diamond convergence" do
      # Create workflow: trigger → switch → (case1 OR case2 OR case3) → merge
      trigger_node = %Node{
        key: "trigger",
        name: "Trigger",
        integration_name: "test",
        action_name: "trigger_action",
        params: %{}
      }

      switch_node = %Node{
        key: "switch",
        name: "Switch",
        integration_name: "logic",
        action_name: "switch",
        params: %{
          "cases" => [
            %{"condition" => "", "port" => "case1"},
            %{"condition" => "", "port" => "case2"},
            %{"condition" => "match3", "port" => "case3"}
          ]
        }
      }

      case1_branch = %Node{
        key: "case1_branch",
        name: "Case 1 Branch",
        integration_name: "test",
        action_name: "simple_action",
        params: %{}
      }

      case2_branch = %Node{
        key: "case2_branch",
        name: "Case 2 Branch",
        integration_name: "test",
        action_name: "simple_action",
        params: %{}
      }

      case3_branch = %Node{
        key: "case3_branch",
        name: "Case 3 Branch",
        integration_name: "test",
        action_name: "simple_action",
        params: %{}
      }

      merge_node = %Node{
        key: "merge",
        name: "Merge",
        integration_name: "test",
        action_name: "simple_action",
        params: %{}
      }

      workflow = %Workflow{
        id: "test_workflow",
        name: "Test Switch Diamond Workflow",
        nodes: [trigger_node, switch_node, case1_branch, case2_branch, case3_branch, merge_node],
        connections: [
          %Connection{from: "trigger", from_port: "success", to: "switch", to_port: "input"},
          %Connection{from: "switch", from_port: "case1", to: "case1_branch", to_port: "input"},
          %Connection{from: "switch", from_port: "case2", to: "case2_branch", to_port: "input"},
          %Connection{from: "switch", from_port: "case3", to: "case3_branch", to_port: "input"},
          %Connection{from: "case1_branch", from_port: "success", to: "merge", to_port: "input"},
          %Connection{from: "case2_branch", from_port: "success", to: "merge", to_port: "input"},
          %Connection{from: "case3_branch", from_port: "success", to: "merge", to_port: "input"}
        ],
        settings: %WorkflowSettings{}
      }

      # Compile and execute workflow
      {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "trigger")

      context = %{
        workflow_loader: fn _id -> {:error, "not implemented"} end,
        variables: %{},
        metadata: %{}
      }

      {:ok, result} = GraphExecutor.execute_graph(execution_graph, context)

      # Verify execution results
      assert result.status == :completed
      # trigger, switch, case3_branch, merge
      assert count_node_executions(result) == 4

      # Verify only case3 branch was executed (first non-empty condition)
      assert get_node_execution(result, "trigger").status == :completed
      assert get_node_execution(result, "switch").status == :completed
      assert get_node_execution(result, "switch").output_port == "case3"
      assert get_node_execution(result, "case3_branch").status == :completed
      assert get_node_execution(result, "merge").status == :completed
      assert get_node_execution(result, "case1_branch") == nil
      assert get_node_execution(result, "case2_branch") == nil
    end

    test "Switch fails when no cases match" do
      # Create workflow: trigger → switch (no matching cases)
      trigger_node = %Node{
        key: "trigger",
        name: "Trigger",
        integration_name: "test",
        action_name: "trigger_action",
        params: %{}
      }

      switch_node = %Node{
        key: "switch",
        name: "Switch",
        integration_name: "logic",
        action_name: "switch",
        params: %{
          "cases" => [
            %{"condition" => "", "port" => "case1"},
            %{"condition" => nil, "port" => "case2"}
          ]
        }
      }

      workflow = %Workflow{
        id: "test_workflow",
        name: "Test Switch Failure Workflow",
        nodes: [trigger_node, switch_node],
        connections: [
          %Connection{from: "trigger", from_port: "success", to: "switch", to_port: "input"}
        ],
        settings: %WorkflowSettings{}
      }

      # Compile and execute workflow
      {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "trigger")

      context = %{
        workflow_loader: fn _id -> {:error, "not implemented"} end,
        variables: %{},
        metadata: %{}
      }

      {:error, result} = GraphExecutor.execute_graph(execution_graph, context)

      # Verify execution results
      assert result.status == :failed
      # trigger, switch
      assert count_node_executions(result) == 2

      # Verify switch failed
      assert get_node_execution(result, "trigger").status == :completed
      assert get_node_execution(result, "switch").status == :failed

      # Check error structure - the error_data should contain the error returned by the action
      switch_execution = get_node_execution(result, "switch")
      error_data = switch_execution.error_data

      # The structure shows: %{"error" => %{message: "...", type: "..."}, "port" => "error", "type" => "action_error"}
      assert error_data["error"][:type] == "no_matching_case"
    end
  end

  describe "Nested conditional branching" do
    test "IF condition nested within switch case" do
      # Create workflow: trigger → switch → case1_branch (IF condition) → (true_branch OR false_branch)
      trigger_node = %Node{
        key: "trigger",
        name: "Trigger",
        integration_name: "test",
        action_name: "trigger_action",
        params: %{}
      }

      switch_node = %Node{
        key: "switch",
        name: "Switch",
        integration_name: "logic",
        action_name: "switch",
        params: %{
          "cases" => [
            %{"condition" => "match1", "port" => "case1"}
          ]
        }
      }

      if_node = %Node{
        key: "if_condition",
        name: "IF Condition",
        integration_name: "logic",
        action_name: "if_condition",
        params: %{"condition" => ""}
      }

      true_branch = %Node{
        key: "true_branch",
        name: "True Branch",
        integration_name: "test",
        action_name: "simple_action",
        params: %{}
      }

      false_branch = %Node{
        key: "false_branch",
        name: "False Branch",
        integration_name: "test",
        action_name: "simple_action",
        params: %{}
      }

      workflow = %Workflow{
        id: "test_workflow",
        name: "Test Nested Conditional Workflow",
        nodes: [trigger_node, switch_node, if_node, true_branch, false_branch],
        connections: [
          %Connection{from: "trigger", from_port: "success", to: "switch", to_port: "input"},
          %Connection{from: "switch", from_port: "case1", to: "if_condition", to_port: "input"},
          %Connection{from: "if_condition", from_port: "true", to: "true_branch", to_port: "input"},
          %Connection{from: "if_condition", from_port: "false", to: "false_branch", to_port: "input"}
        ],
        settings: %WorkflowSettings{}
      }

      # Compile and execute workflow
      {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "trigger")

      context = %{
        workflow_loader: fn _id -> {:error, "not implemented"} end,
        variables: %{},
        metadata: %{}
      }

      {:ok, result} = GraphExecutor.execute_graph(execution_graph, context)

      # Verify execution results
      assert result.status == :completed
      # trigger, switch, if_condition, false_branch
      assert count_node_executions(result) == 4

      # Verify execution path
      assert get_node_execution(result, "trigger").status == :completed
      assert get_node_execution(result, "switch").status == :completed
      assert get_node_execution(result, "switch").output_port == "case1"
      assert get_node_execution(result, "if_condition").status == :completed
      assert get_node_execution(result, "if_condition").output_port == "false"
      assert get_node_execution(result, "false_branch").status == :completed
      assert get_node_execution(result, "true_branch") == nil
    end
  end
end
