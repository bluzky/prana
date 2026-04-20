defmodule Prana.Execution.GraphExecutorDebugApiTest do
  @moduledoc """
  Tests for the debug-oriented GraphExecutor APIs:
    - execute_node/3        – runs a single node and stops
    - execute_from_node/3   – runs a node then continues the workflow to completion
  """
  use ExUnit.Case, async: false

  alias Prana.Connection
  alias Prana.GraphExecutor
  alias Prana.IntegrationRegistry
  alias Prana.Node
  alias Prana.NodeSettings
  alias Prana.TestSupport.TestIntegration
  alias Prana.Workflow
  alias Prana.WorkflowCompiler
  alias Prana.WorkflowExecution

  setup do
    {:ok, registry_pid} = IntegrationRegistry.start_link()

    Code.ensure_loaded!(TestIntegration)
    :ok = IntegrationRegistry.register_integration(TestIntegration)

    on_exit(fn ->
      if Process.alive?(registry_pid) do
        GenServer.stop(registry_pid)
      end
    end)

    :ok
  end

  # ── helpers ──────────────────────────────────────────────────────────────────

  defp build_workflow(nodes, connections) do
    workflow = %Workflow{
      id: "debug_test_workflow",
      version: "1.0.0",
      name: "Debug Test Workflow",
      nodes: nodes,
      connections: %{},
      variables: %{}
    }

    Enum.reduce(connections, workflow, fn conn, acc ->
      {:ok, updated} = Workflow.add_connection(acc, conn)
      updated
    end)
  end

  defp compile_workflow!(workflow, trigger_key \\ "trigger") do
    {:ok, graph} = WorkflowCompiler.compile(workflow, trigger_key)
    graph
  end

  defp initialized_execution(graph) do
    {:ok, execution} = GraphExecutor.initialize_execution(graph)
    WorkflowExecution.rebuild_runtime(execution)
  end

  defp node_execution_for(execution, node_key) do
    execution.node_executions
    |> Map.get(node_key, [])
    |> List.first()
  end

  defp all_executed_keys(execution) do
    execution.node_executions |> Map.keys() |> Enum.sort()
  end

  defp trigger_node(key \\ "trigger"),
    do: %Node{key: key, type: "test.trigger_action", settings: NodeSettings.default()}

  defp action_node(key),
    do: %Node{key: key, type: "test.simple_action", settings: NodeSettings.default()}

  defp failing_node(key),
    do: %Node{key: key, type: "test.failing_action", settings: NodeSettings.default()}

  # ── execute_node/3 ────────────────────────────────────────────────────────────

  describe "execute_node/3 – single node execution" do
    test "returns {:ok, node_execution, updated_execution} for a successful node" do
      graph =
        build_workflow(
          [trigger_node(), action_node("step")],
          [%Connection{from: "trigger", from_port: "main", to: "step", to_port: "input"}]
        )
        |> compile_workflow!()

      execution = initialized_execution(graph)

      assert {:ok, node_exec, updated_execution} = GraphExecutor.execute_node(execution, "trigger")

      assert node_exec.node_key == "trigger"
      assert node_exec.status == "completed"
      assert node_exec.output_port == "main"

      # Workflow should NOT be complete – only one node ran
      assert updated_execution.status == "running"
      assert map_size(updated_execution.node_executions) == 1
    end

    test "executes only the requested node – downstream nodes are not run" do
      graph =
        build_workflow(
          [trigger_node(), action_node("step")],
          [%Connection{from: "trigger", from_port: "main", to: "step", to_port: "input"}]
        )
        |> compile_workflow!()

      execution = initialized_execution(graph)

      {:ok, _node_exec, updated_execution} = GraphExecutor.execute_node(execution, "trigger")

      assert Map.has_key?(updated_execution.node_executions, "trigger")
      refute Map.has_key?(updated_execution.node_executions, "step")
    end

    test "accepts custom input_data and passes it to the node" do
      graph =
        build_workflow(
          [trigger_node(), action_node("step")],
          [%Connection{from: "trigger", from_port: "main", to: "step", to_port: "input"}]
        )
        |> compile_workflow!()

      execution = initialized_execution(graph)
      custom_input = %{"custom_key" => "custom_value"}

      assert {:ok, node_exec, _updated} = GraphExecutor.execute_node(execution, "trigger", custom_input)
      assert node_exec.status == "completed"
      assert node_exec.node_key == "trigger"
    end

    test "returned node_execution matches the record stored in updated_execution" do
      graph =
        build_workflow([trigger_node()], [])
        |> compile_workflow!()

      execution = initialized_execution(graph)

      {:ok, node_exec, updated_execution} = GraphExecutor.execute_node(execution, "trigger")

      stored = node_execution_for(updated_execution, "trigger")
      assert stored == node_exec
    end

    test "returns {:error, reason} when node_key does not exist" do
      graph =
        build_workflow([trigger_node()], [])
        |> compile_workflow!()

      execution = initialized_execution(graph)

      assert {:error, reason} = GraphExecutor.execute_node(execution, "nonexistent_node")
      assert reason.code == "node_not_found"
      assert reason.details.node_key == "nonexistent_node"
    end

    test "returns {:error, failed_execution} when node action fails" do
      # trigger -> failing_node; execute only failing_node with trigger output pre-loaded
      graph =
        build_workflow(
          [trigger_node(), failing_node("bad")],
          [%Connection{from: "trigger", from_port: "main", to: "bad", to_port: "input"}]
        )
        |> compile_workflow!()

      execution =
        graph
        |> initialized_execution()
        |> put_in([Access.key!(:__runtime), "nodes", "trigger"], %{
          "output" => %{"triggered" => true},
          "context" => %{}
        })

      assert {:error, failed_execution} = GraphExecutor.execute_node(execution, "bad")
      assert failed_execution.status == "failed"
    end

    test "returns {:suspend, suspended_execution, suspension_data} for a suspending node" do
      Code.ensure_loaded!(Prana.Integrations.Workflow)
      :ok = IntegrationRegistry.register_integration(Prana.Integrations.Workflow)

      graph =
        build_workflow(
          [
            trigger_node(),
            %Node{
              key: "sub_wf",
              type: "workflow.execute_workflow",
              params: %{"workflow_id" => "child", "execution_mode" => "sync", "timeout_ms" => 5000},
              settings: NodeSettings.default()
            }
          ],
          [%Connection{from: "trigger", from_port: "main", to: "sub_wf", to_port: "main"}]
        )
        |> compile_workflow!()

      execution =
        graph
        |> initialized_execution()
        |> put_in([Access.key!(:__runtime), "nodes", "trigger"], %{
          "output" => %{"triggered" => true},
          "context" => %{}
        })

      assert {:suspend, suspended_execution, suspension_data} =
               GraphExecutor.execute_node(execution, "sub_wf")

      assert suspended_execution.status == "suspended"
      assert suspended_execution.suspended_node_id == "sub_wf"
      assert is_map(suspension_data)
    end
  end

  # ── execute_from_node/3 ───────────────────────────────────────────────────────

  describe "execute_from_node/3 – run node then continue to completion" do
    test "runs the starting node and continues the workflow to completion" do
      graph =
        build_workflow(
          [trigger_node(), action_node("step")],
          [%Connection{from: "trigger", from_port: "main", to: "step", to_port: "input"}]
        )
        |> compile_workflow!()

      execution = initialized_execution(graph)

      assert {:ok, completed_execution, _output} =
               GraphExecutor.execute_from_node(execution, "trigger")

      assert completed_execution.status == "completed"
      assert all_executed_keys(completed_execution) == ["step", "trigger"]
    end

    test "runs a mid-workflow node and continues downstream only" do
      graph =
        build_workflow(
          [trigger_node(), action_node("step_a"), action_node("step_b")],
          [
            %Connection{from: "trigger", from_port: "main", to: "step_a", to_port: "input"},
            %Connection{from: "step_a", from_port: "main", to: "step_b", to_port: "input"}
          ]
        )
        |> compile_workflow!()

      # Pre-load trigger output into runtime so step_a can read input
      execution =
        graph
        |> initialized_execution()
        |> put_in([Access.key!(:__runtime), "nodes", "trigger"], %{
          "output" => %{"triggered" => true},
          "context" => %{}
        })

      assert {:ok, completed_execution, _output} =
               GraphExecutor.execute_from_node(execution, "step_a")

      assert completed_execution.status == "completed"

      executed = all_executed_keys(completed_execution)
      assert "step_a" in executed
      assert "step_b" in executed
      refute "trigger" in executed
    end

    test "returns {:error, reason} when node_key does not exist" do
      graph =
        build_workflow([trigger_node()], [])
        |> compile_workflow!()

      execution = initialized_execution(graph)

      assert {:error, reason} = GraphExecutor.execute_from_node(execution, "no_such_node")
      assert reason.code == "node_not_found"
    end

    test "propagates failure when starting node fails" do
      graph =
        build_workflow(
          [trigger_node(), failing_node("bad")],
          [%Connection{from: "trigger", from_port: "main", to: "bad", to_port: "input"}]
        )
        |> compile_workflow!()

      execution =
        graph
        |> initialized_execution()
        |> put_in([Access.key!(:__runtime), "nodes", "trigger"], %{
          "output" => %{"triggered" => true},
          "context" => %{}
        })

      assert {:error, failed_execution} = GraphExecutor.execute_from_node(execution, "bad")
      assert failed_execution.status == "failed"
    end

    test "accepts custom input_data and drives execution from that point" do
      graph =
        build_workflow(
          [trigger_node(), action_node("step")],
          [%Connection{from: "trigger", from_port: "main", to: "step", to_port: "input"}]
        )
        |> compile_workflow!()

      execution = initialized_execution(graph)
      custom_input = %{"debug" => true}

      assert {:ok, completed_execution, _output} =
               GraphExecutor.execute_from_node(execution, "trigger", custom_input)

      assert completed_execution.status == "completed"

      trigger_exec = node_execution_for(completed_execution, "trigger")
      assert trigger_exec.status == "completed"
    end

    test "suspends mid-workflow when a downstream node suspends" do
      Code.ensure_loaded!(Prana.Integrations.Workflow)
      :ok = IntegrationRegistry.register_integration(Prana.Integrations.Workflow)

      graph =
        build_workflow(
          [
            trigger_node(),
            %Node{
              key: "sub_wf",
              type: "workflow.execute_workflow",
              params: %{"workflow_id" => "child", "execution_mode" => "sync", "timeout_ms" => 5000},
              settings: NodeSettings.default()
            }
          ],
          [%Connection{from: "trigger", from_port: "main", to: "sub_wf", to_port: "main"}]
        )
        |> compile_workflow!()

      execution = initialized_execution(graph)

      # Start from trigger – it will complete, then sub_wf suspends
      assert {:suspend, suspended_execution, suspension_data} =
               GraphExecutor.execute_from_node(execution, "trigger")

      assert suspended_execution.status == "suspended"
      assert suspended_execution.suspended_node_id == "sub_wf"
      assert is_map(suspension_data)
    end
  end
end
