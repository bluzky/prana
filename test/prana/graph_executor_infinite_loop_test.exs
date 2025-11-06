defmodule Prana.GraphExecutorInfiniteLoopTest do
  use ExUnit.Case, async: false

  alias Prana.Connection
  alias Prana.GraphExecutor
  alias Prana.IntegrationRegistry
  alias Prana.Node
  alias Prana.TestSupport.TestIntegration
  alias Prana.Workflow
  alias Prana.WorkflowCompiler
  alias Prana.WorkflowExecution

  setup do
    {:ok, registry_pid} = IntegrationRegistry.start_link()
    :ok = IntegrationRegistry.register_integration(TestIntegration)

    on_exit(fn ->
      if Process.alive?(registry_pid) do
        GenServer.stop(registry_pid)
      end
    end)

    :ok
  end

  describe "infinite loop protection" do
    test "iteration count stays at 0 for linear workflows (no loopbacks)" do
      # Create a simple linear workflow
      workflow = %Workflow{
        id: "linear_test",
        name: "Linear Workflow",
        nodes: [
          %Node{key: "trigger", type: "test.trigger_action", params: %{}},
          %Node{key: "action1", type: "test.simple_action", params: %{}},
          %Node{key: "action2", type: "test.simple_action", params: %{}}
        ],
        connections: %{
          "trigger" => %{
            "main" => [
              %Connection{
                from: "trigger",
                from_port: "main",
                to: "action1",
                to_port: "input"
              }
            ]
          },
          "action1" => %{
            "main" => [
              %Connection{
                from: "action1",
                from_port: "main",
                to: "action2",
                to_port: "input"
              }
            ]
          }
        }
      }

      {:ok, graph} = WorkflowCompiler.compile(workflow, "trigger")
      {:ok, execution, _} = GraphExecutor.execute_workflow(graph, %{})

      # Verify execution completed successfully
      assert execution.status == "completed"
      assert map_size(execution.node_executions) == 3

      # Key assertion: iteration count should be 0 (no loopbacks in linear workflow)
      assert WorkflowExecution.get_iteration_count(execution) == 0
    end

    test "iteration count increments only on loopbacks in loop structure" do
      # Create a workflow with a loop structure
      # trigger -> check -> process -> check (loop back)
      workflow = %Workflow{
        id: "loop_test",
        name: "Loop Workflow",
        nodes: [
          %Node{
            key: "trigger",
            type: "test.trigger_action",
            params: %{},
            metadata: %{}
          },
          %Node{
            key: "check",
            type: "test.simple_action",
            params: %{},
            # This will be marked as part of a loop by LoopDetector
            metadata: %{}
          },
          %Node{
            key: "process",
            type: "test.simple_action",
            params: %{},
            metadata: %{}
          }
        ],
        connections: %{
          "trigger" => %{
            "main" => [
              %Connection{
                from: "trigger",
                from_port: "main",
                to: "check",
                to_port: "input"
              }
            ]
          },
          "check" => %{
            "main" => [
              %Connection{
                from: "check",
                from_port: "main",
                to: "process",
                to_port: "input"
              }
            ]
          },
          "process" => %{
            "main" => [
              %Connection{
                from: "process",
                from_port: "main",
                to: "check",
                to_port: "input"
              }
            ]
          }
        }
      }

      # Compile the workflow - LoopDetector will annotate nodes
      {:ok, graph} = WorkflowCompiler.compile(workflow, "trigger")

      # Verify loop detection worked
      check_node = graph.node_map["check"]
      assert check_node.metadata[:loop_level] > 0, "Check node should be detected as part of a loop"

      # For this test, we'll manually set max_iterations low to trigger the protection
      # Set low max_iterations to trigger protection quickly
      original_max = Application.get_env(:prana, :max_execution_iterations)

      try do
        Application.put_env(:prana, :max_execution_iterations, 5)

        # Execute - should hit infinite loop protection
        result = GraphExecutor.execute_workflow(graph, %{})

        # Should return an error due to infinite loop protection
        assert {:error, failed_execution} = result
        assert failed_execution.status == "failed"
        assert failed_execution.error.type == "infinite_loop_protection"

        # Verify iteration count reached the limit
        iteration_count = WorkflowExecution.get_iteration_count(failed_execution)
        assert iteration_count == 5, "Should have incremented to max_iterations (5)"
      after
        # Restore original setting
        if original_max do
          Application.put_env(:prana, :max_execution_iterations, original_max)
        else
          Application.delete_env(:prana, :max_execution_iterations)
        end
      end
    end

    test "large iteration workflows don't trigger false positives" do
      # Create a workflow that executes many nodes sequentially (no loops)
      nodes =
        for i <- 1..100 do
          %Node{
            key: "action_#{i}",
            type: "test.simple_action",
            params: %{}
          }
        end

      trigger = %Node{key: "trigger", type: "test.trigger_action", params: %{}}
      all_nodes = [trigger | nodes]

      # Create sequential connections
      connections =
        [trigger | nodes]
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.reduce(%{}, fn [from, to], acc ->
          Map.put(acc, from.key, %{
            "main" => [
              %Connection{
                from: from.key,
                from_port: "main",
                to: to.key,
                to_port: "input"
              }
            ]
          })
        end)

      workflow = %Workflow{
        id: "large_linear_test",
        name: "Large Linear Workflow",
        nodes: all_nodes,
        connections: connections
      }

      {:ok, graph} = WorkflowCompiler.compile(workflow, "trigger")
      {:ok, execution, _} = GraphExecutor.execute_workflow(graph, %{})

      # Should complete successfully
      assert execution.status == "completed"
      assert map_size(execution.node_executions) == 101

      # Iteration count should still be 0 (no loopbacks)
      assert WorkflowExecution.get_iteration_count(execution) == 0
    end
  end
end
