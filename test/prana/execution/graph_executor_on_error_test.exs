defmodule Prana.Execution.GraphExecutorOnErrorTest do
  @moduledoc """
  Integration tests for on_error node setting with GraphExecutor.

  These tests verify that the on_error setting works correctly at the workflow level,
  ensuring proper integration between NodeExecutor and GraphExecutor.
  """
  use ExUnit.Case, async: false

  alias Prana.Connection
  alias Prana.GraphExecutor
  alias Prana.IntegrationRegistry
  alias Prana.Integrations.Data
  alias Prana.Node
  alias Prana.NodeSettings
  alias Prana.TestSupport.TestIntegration
  alias Prana.Workflow
  alias Prana.WorkflowCompiler

  setup do
    # Start IntegrationRegistry
    {:ok, registry_pid} = IntegrationRegistry.start_link()

    # Ensure modules are loaded before registration
    Code.ensure_loaded!(TestIntegration)
    Code.ensure_loaded!(Data)

    # Register test integration and Data integration
    :ok = IntegrationRegistry.register_integration(TestIntegration)
    :ok = IntegrationRegistry.register_integration(Data)

    on_exit(fn ->
      if Process.alive?(registry_pid) do
        GenServer.stop(registry_pid)
      end
    end)

    :ok
  end

  # Helper to count node executions
  defp count_node_executions(execution) do
    case execution.node_executions do
      node_executions_map when is_map(node_executions_map) ->
        node_executions_map
        |> Enum.flat_map(fn {_node_id, executions} -> executions end)
        |> length()

      node_executions_list when is_list(node_executions_list) ->
        length(node_executions_list)
    end
  end

  # Helper to get all node executions sorted by execution_index
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

  # Helper to get a specific node execution by key
  defp get_node_execution(execution, node_key) do
    execution
    |> get_all_node_executions()
    |> Enum.find(&(&1.node_key == node_key))
  end

  describe "workflow continuation with on_error: continue" do
    test "workflow continues execution when node errors with on_error: continue" do
      # Workflow: trigger -> failing_node (on_error: continue) -> set_data_node
      # The failing node should complete successfully and route to set_data_node
      trigger = %Node{key: "trigger", type: "test.trigger_action", settings: NodeSettings.default()}

      failing_node = %Node{
        key: "failing_node",
        type: "test.failing_action",
        settings: %NodeSettings{on_error: "continue"}
      }

      set_data_node = %Node{
        key: "set_data_node",
        type: "data.set_data",
        params: %{
          "mode" => "manual",
          "mapping_map" => %{
            "message" => "error handled successfully",
            "error_code" => "{{ $input.main.code }}"
          }
        },
        settings: NodeSettings.default()
      }

      workflow = %Workflow{
        id: "test_workflow",
        version: "1.0.0",
        name: "On Error Continue Test",
        nodes: [trigger, failing_node, set_data_node],
        connections: %{},
        variables: %{}
      }

      connections = [
        %Connection{from: "trigger", from_port: "main", to: "failing_node", to_port: "input"},
        %Connection{from: "failing_node", from_port: "main", to: "set_data_node", to_port: "main"}
      ]

      workflow =
        Enum.reduce(connections, workflow, fn connection, acc_workflow ->
          {:ok, updated_workflow} = Workflow.add_connection(acc_workflow, connection)
          updated_workflow
        end)

      {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "trigger")

      context = %{
        workflow_loader: fn _id -> {:error, "not implemented"} end,
        variables: %{}
      }

      # Execute workflow
      result = GraphExecutor.execute_workflow(execution_graph, context)

      # Workflow should complete successfully (not fail)
      assert {:ok, execution, output} = result
      assert execution.status == "completed"

      # All three nodes should have executed
      assert count_node_executions(execution) == 3

      # Failing node should be completed (not failed)
      failing_node_exec = get_node_execution(execution, "failing_node")
      assert failing_node_exec.status == "completed"
      assert failing_node_exec.output_port == "main"
      assert failing_node_exec.output_data.code == "action_error"

      # Verify final output contains set_data result with error code from failed node
      assert output["message"] == "error handled successfully"
      assert output["error_code"] == "action_error"
    end
  end

  describe "workflow continuation with on_error: continue_error_output" do
    test "workflow routes through virtual error port to connected node" do
      # Workflow: trigger -> failing_node (on_error: continue_error_output) -> error_handler
      # Connection from failing_node.error to error_handler
      trigger = %Node{key: "trigger", type: "test.trigger_action", settings: NodeSettings.default()}

      failing_node = %Node{
        key: "failing_node",
        type: "test.failing_action",
        settings: %NodeSettings{on_error: "continue_error_output"}
      }

      error_handler = %Node{
        key: "error_handler",
        type: "data.set_data",
        params: %{
          "mode" => "manual",
          "mapping_map" => %{
            "handled" => "true",
            "error_message" => "Action returned error"
          }
        },
        settings: NodeSettings.default()
      }

      workflow = %Workflow{
        id: "test_workflow",
        version: "1.0.0",
        name: "Error Port Routing Test",
        nodes: [trigger, failing_node, error_handler],
        connections: %{},
        variables: %{}
      }

      connections = [
        %Connection{from: "trigger", from_port: "main", to: "failing_node", to_port: "input"},
        %Connection{from: "failing_node", from_port: "error", to: "error_handler", to_port: "main"}
      ]

      workflow =
        Enum.reduce(connections, workflow, fn connection, acc_workflow ->
          {:ok, updated_workflow} = Workflow.add_connection(acc_workflow, connection)
          updated_workflow
        end)

      {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "trigger")

      context = %{
        workflow_loader: fn _id -> {:error, "not implemented"} end,
        variables: %{}
      }

      result = GraphExecutor.execute_workflow(execution_graph, context)

      assert {:ok, execution, output} = result
      assert execution.status == "completed"
      assert count_node_executions(execution) == 3

      # Failing node should complete with error port
      failing_node_exec = get_node_execution(execution, "failing_node")
      assert failing_node_exec.status == "completed"
      assert failing_node_exec.output_port == "error"
      assert failing_node_exec.output_data.code == "action_error"

      # Verify final output shows error was handled through error port
      assert output["handled"] == "true"
      assert output["error_message"] == "Action returned error"
    end

    test "workflow completes without error handler if no error port connection exists" do
      # Workflow: trigger -> failing_node (on_error: continue_error_output)
      # No connection from error port - workflow should complete
      trigger = %Node{key: "trigger", type: "test.trigger_action", settings: NodeSettings.default()}

      failing_node = %Node{
        key: "failing_node",
        type: "test.failing_action",
        settings: %NodeSettings{on_error: "continue_error_output"}
      }

      workflow = %Workflow{
        id: "test_workflow",
        version: "1.0.0",
        name: "Error Port No Connection",
        nodes: [trigger, failing_node],
        connections: %{},
        variables: %{}
      }

      connections = [
        %Connection{from: "trigger", from_port: "main", to: "failing_node", to_port: "input"}
      ]

      workflow =
        Enum.reduce(connections, workflow, fn connection, acc_workflow ->
          {:ok, updated_workflow} = Workflow.add_connection(acc_workflow, connection)
          updated_workflow
        end)

      {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "trigger")

      context = %{
        workflow_loader: fn _id -> {:error, "not implemented"} end,
        variables: %{}
      }

      result = GraphExecutor.execute_workflow(execution_graph, context)

      assert {:ok, execution, _} = result
      assert execution.status == "completed"
      assert count_node_executions(execution) == 2

      # Failing node should complete with error port
      failing_node_exec = get_node_execution(execution, "failing_node")
      assert failing_node_exec.status == "completed"
      assert failing_node_exec.output_port == "error"
    end
  end

  describe "workflow failure with on_error: stop_workflow" do
    test "workflow fails when node errors with default on_error setting" do
      # Workflow: trigger -> failing_node (default: stop_workflow) -> success_node
      # Workflow should fail at failing_node
      trigger = %Node{key: "trigger", type: "test.trigger_action", settings: NodeSettings.default()}

      failing_node = %Node{
        key: "failing_node",
        type: "test.failing_action",
        settings: %NodeSettings{on_error: "stop_workflow"}
      }

      success_node = %Node{key: "success_node", type: "test.simple_action", settings: NodeSettings.default()}

      workflow = %Workflow{
        id: "test_workflow",
        version: "1.0.0",
        name: "Stop Workflow Test",
        nodes: [trigger, failing_node, success_node],
        connections: %{},
        variables: %{}
      }

      connections = [
        %Connection{from: "trigger", from_port: "main", to: "failing_node", to_port: "input"},
        %Connection{from: "failing_node", from_port: "main", to: "success_node", to_port: "main"}
      ]

      workflow =
        Enum.reduce(connections, workflow, fn connection, acc_workflow ->
          {:ok, updated_workflow} = Workflow.add_connection(acc_workflow, connection)
          updated_workflow
        end)

      {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "trigger")

      context = %{
        workflow_loader: fn _id -> {:error, "not implemented"} end,
        variables: %{}
      }

      result = GraphExecutor.execute_workflow(execution_graph, context)

      # Workflow should fail
      assert {:error, execution} = result
      assert execution.status == "failed"

      # Only trigger and failing_node should have executed
      assert count_node_executions(execution) == 2

      # Failing node should be failed
      failing_node_exec = get_node_execution(execution, "failing_node")
      assert failing_node_exec.status == "failed"
      assert failing_node_exec.output_port == nil

      # Success node should NOT have executed
      assert get_node_execution(execution, "success_node") == nil
    end
  end

  describe "mixed on_error settings" do
    test "workflow handles different on_error settings for different nodes" do
      # Workflow: trigger -> failing_1 (continue) -> set_data -> failing_2 (stop_workflow)
      # Should continue through failing_1, execute set_data, then fail at failing_2
      trigger = %Node{key: "trigger", type: "test.trigger_action", settings: NodeSettings.default()}
      failing_1 = %Node{key: "failing_1", type: "test.failing_action", settings: %NodeSettings{on_error: "continue"}}

      set_data_node = %Node{
        key: "set_data_node",
        type: "data.set_data",
        params: %{
          "mode" => "manual",
          "mapping_map" => %{
            "step" => "between_failures",
            "first_error" => "{{ $input.main.code }}"
          }
        },
        settings: NodeSettings.default()
      }

      failing_2 = %Node{key: "failing_2", type: "test.failing_action", settings: %NodeSettings{on_error: "stop_workflow"}}

      workflow = %Workflow{
        id: "test_workflow",
        version: "1.0.0",
        name: "Mixed On Error Test",
        nodes: [trigger, failing_1, set_data_node, failing_2],
        connections: %{},
        variables: %{}
      }

      connections = [
        %Connection{from: "trigger", from_port: "main", to: "failing_1", to_port: "input"},
        %Connection{from: "failing_1", from_port: "main", to: "set_data_node", to_port: "main"},
        %Connection{from: "set_data_node", from_port: "main", to: "failing_2", to_port: "input"}
      ]

      workflow =
        Enum.reduce(connections, workflow, fn connection, acc_workflow ->
          {:ok, updated_workflow} = Workflow.add_connection(acc_workflow, connection)
          updated_workflow
        end)

      {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "trigger")

      context = %{
        workflow_loader: fn _id -> {:error, "not implemented"} end,
        variables: %{}
      }

      result = GraphExecutor.execute_workflow(execution_graph, context)

      # Workflow should fail at failing_2
      assert {:error, execution} = result
      assert execution.status == "failed"
      assert count_node_executions(execution) == 4

      # failing_1 should be completed (continued)
      assert get_node_execution(execution, "failing_1").status == "completed"

      # set_data should have executed successfully
      set_data_exec = get_node_execution(execution, "set_data_node")
      assert set_data_exec.status == "completed"
      assert set_data_exec.output_data["step"] == "between_failures"
      assert set_data_exec.output_data["first_error"] == "action_error"

      # failing_2 should be failed (stopped workflow)
      assert get_node_execution(execution, "failing_2").status == "failed"
    end
  end
end
