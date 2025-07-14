defmodule Prana.ExecutionTest do
  use ExUnit.Case

  alias Prana.Execution
  alias Prana.NodeExecution

  doctest Prana.Execution

  describe "runtime state rebuilding" do
    test "rebuild_runtime/2 creates runtime state from node executions" do
      # Setup execution with node executions
      execution = %Execution{
        id: "exec_1",
        workflow_id: "wf_1",
        workflow_version: 1,
        node_executions: %{
          "node_1" => [
            %NodeExecution{
              node_key: "node_1",
              status: :completed,
              output_data: %{user_id: 123},
              output_port: "success",
              started_at: ~U[2024-01-01 10:00:00Z],
              execution_index: 0,
              run_index: 0
            }
          ],
          "node_2" => [
            %NodeExecution{
              node_key: "node_2",
              status: :completed,
              output_data: %{email: "test@example.com"},
              output_port: "primary",
              started_at: ~U[2024-01-01 10:01:00Z],
              execution_index: 1,
              run_index: 0
            }
          ],
          "node_3" => [
            %NodeExecution{
              node_key: "node_3",
              status: :failed,
              error_data: %{error: "network timeout"},
              output_port: nil,
              started_at: ~U[2024-01-01 10:02:00Z],
              execution_index: 2,
              run_index: 0
            }
          ]
        },
        current_execution_index: 3
      }

      env_data = %{"api_key" => "test_key", "base_url" => "https://api.test.com"}

      # Rebuild runtime state
      result = Execution.rebuild_runtime(execution, env_data)

      # Verify runtime state structure
      assert result.__runtime["nodes"] == %{
               "node_1" => %{"output" => %{user_id: 123}, "context" => %{}},
               "node_2" => %{"output" => %{email: "test@example.com"}, "context" => %{}}
             }

      assert result.__runtime["env"] == env_data

      # Note: active_paths and executed_nodes not included in simplified rebuild_runtime
    end

    test "rebuild_runtime/2 handles empty node executions" do
      execution = %Execution{
        id: "exec_1",
        workflow_id: "wf_1",
        workflow_version: 1,
        node_executions: %{},
        current_execution_index: 0
      }

      result = Execution.rebuild_runtime(execution, %{})

      assert result.__runtime["nodes"] == %{}
      assert result.__runtime["env"] == %{}
    end

    test "rebuild_runtime/2 filters out non-completed nodes from runtime state" do
      execution = %Execution{
        id: "exec_1",
        workflow_id: "wf_1",
        workflow_version: 1,
        node_executions: %{
          "node_1" => [
            %NodeExecution{
              node_key: "node_1",
              status: :pending,
              output_data: nil,
              output_port: nil,
              started_at: ~U[2024-01-01 10:00:00Z],
              execution_index: 0,
              run_index: 0
            }
          ],
          "node_2" => [
            %NodeExecution{
              node_key: "node_2",
              status: :running,
              output_data: nil,
              output_port: nil,
              started_at: ~U[2024-01-01 10:01:00Z],
              execution_index: 1,
              run_index: 0
            }
          ],
          "node_3" => [
            %NodeExecution{
              node_key: "node_3",
              status: :completed,
              output_data: %{result: "success"},
              output_port: "done",
              started_at: ~U[2024-01-01 10:02:00Z],
              execution_index: 2,
              run_index: 0
            }
          ]
        },
        current_execution_index: 3
      }

      result = Execution.rebuild_runtime(execution, %{})

      # Only completed nodes should be in nodes map
      assert result.__runtime["nodes"] == %{"node_3" => %{"output" => %{result: "success"}, "context" => %{}}}
    end
  end

  describe "complete_node/2" do
    test "completes node and updates both persistent and runtime state" do
      execution = %Execution{
        id: "exec_1",
        workflow_id: "wf_1",
        workflow_version: 1,
        node_executions: %{},
        current_execution_index: 0,
        __runtime: %{
          "nodes" => %{},
          "env" => %{}
        }
      }

      # Create and complete a NodeExecution first
      node_execution =
        "exec_1"
        |> NodeExecution.new("node_1", 0, 0)
        |> NodeExecution.start()

      output_data = %{result: "success"}
      completed_node_execution = NodeExecution.complete(node_execution, output_data, "success")

      result = Execution.complete_node(execution, completed_node_execution)

      # Verify persistent state (map structure)
      assert Map.has_key?(result.node_executions, "node_1")
      [completed_node] = result.node_executions["node_1"]
      assert completed_node.status == :completed
      assert completed_node.output_data == output_data
      assert completed_node.output_port == "success"

      # Verify runtime state
      assert result.__runtime["nodes"]["node_1"] == %{"output" => output_data, "context" => %{}}
    end

    test "integrates completed node execution into execution state" do
      execution = %Execution{
        id: "exec_1",
        workflow_id: "wf_1",
        workflow_version: 1,
        node_executions: %{},
        current_execution_index: 0,
        __runtime: %{
          "nodes" => %{},
          "env" => %{}
        }
      }

      # Create and complete a NodeExecution independently
      node_execution =
        "exec_1"
        |> NodeExecution.new("node_1", 0, 0)
        |> NodeExecution.start()

      output_data = %{result: "success"}
      completed_node_execution = NodeExecution.complete(node_execution, output_data, "success")

      result = Execution.complete_node(execution, completed_node_execution)

      # Should integrate the completed node execution
      assert map_size(result.node_executions) == 1
      [integrated_node] = result.node_executions["node_1"]
      assert integrated_node == completed_node_execution
      assert integrated_node.node_key == "node_1"
      assert integrated_node.status == :completed
      assert integrated_node.output_data == output_data
    end

    test "handles nil runtime state gracefully" do
      execution = %Execution{
        id: "exec_1",
        workflow_id: "wf_1",
        workflow_version: 1,
        node_executions: %{},
        current_execution_index: 0,
        __runtime: nil
      }

      # Create and complete a NodeExecution first
      node_execution =
        "exec_1"
        |> NodeExecution.new("node_1", 0, 0)
        |> NodeExecution.start()

      completed_node_execution = NodeExecution.complete(node_execution, %{data: "test"}, "success")

      result = Execution.complete_node(execution, completed_node_execution)

      # Should still update persistent state
      assert map_size(result.node_executions) == 1
      [integrated_node] = result.node_executions["node_1"]
      assert integrated_node.status == :completed

      # Runtime should remain nil
      assert result.__runtime == nil
    end
  end

  describe "fail_node/2" do
    test "fails node and updates both persistent and runtime state" do
      execution = %Execution{
        id: "exec_1",
        workflow_id: "wf_1",
        workflow_version: 1,
        node_executions: %{
          "node_1" => [
            %NodeExecution{
              id: "ne_1",
              execution_id: "exec_1",
              node_key: "node_1",
              status: :running,
              started_at: ~U[2024-01-01 10:00:00Z],
              execution_index: 0,
              run_index: 0
            }
          ]
        },
        current_execution_index: 1,
        __runtime: %{
          "nodes" => %{},
          "env" => %{}
        }
      }

      # Create and fail a NodeExecution first
      [running_node_execution] = execution.node_executions["node_1"]
      error_data = %{error: "network timeout"}
      failed_node_execution = NodeExecution.fail(running_node_execution, error_data)

      result = Execution.fail_node(execution, failed_node_execution)

      # Verify persistent state
      [failed_node] = result.node_executions["node_1"]
      assert failed_node.status == :failed
      assert failed_node.error_data == error_data
      assert failed_node.output_port == nil

      # Verify runtime state (failed nodes don't add to nodes map)
      assert result.__runtime["nodes"] == %{}
      # Note: executed_nodes not included in simplified rebuild_runtime
      # Note: active_paths not included in simplified rebuild_runtime
    end

    test "creates new node execution if none exists" do
      execution = %Execution{
        id: "exec_1",
        workflow_id: "wf_1",
        workflow_version: 1,
        node_executions: %{},
        current_execution_index: 0,
        __runtime: %{
          "nodes" => %{},
          "env" => %{}
        }
      }

      # Create and fail a NodeExecution first
      node_execution =
        "exec_1"
        |> NodeExecution.new("node_1", 0, 0)
        |> NodeExecution.start()

      error_data = %{error: "test error"}
      failed_node_execution = NodeExecution.fail(node_execution, error_data)

      result = Execution.fail_node(execution, failed_node_execution)

      # Should integrate the failed node execution
      assert map_size(result.node_executions) == 1
      [failed_node] = result.node_executions["node_1"]
      assert failed_node.node_key == "node_1"
      assert failed_node.status == :failed
      assert failed_node.error_data == error_data
    end
  end

  describe "state synchronization" do
    test "complete_node maintains state synchronization" do
      # Start with execution that has existing completed nodes
      execution = %Execution{
        id: "exec_1",
        workflow_id: "wf_1",
        workflow_version: 1,
        node_executions: %{
          "node_1" => [
            %NodeExecution{
              node_key: "node_1",
              status: :completed,
              output_data: %{user_id: 123},
              output_port: "success",
              started_at: ~U[2024-01-01 10:00:00Z],
              execution_index: 0,
              run_index: 0
            }
          ]
        },
        current_execution_index: 1,
        __runtime: %{
          "nodes" => %{"node_1" => %{"output" => %{user_id: 123}, "context" => %{}}},
          "env" => %{"api_key" => "test"}
        }
      }

      # Complete another node
      node_execution_2 =
        "exec_1"
        |> NodeExecution.new("node_2", 0, 0)
        |> NodeExecution.start()

      completed_node_execution_2 = NodeExecution.complete(node_execution_2, %{email: "test@example.com"}, "primary")

      result = Execution.complete_node(execution, completed_node_execution_2)

      # Verify state synchronization
      assert result.__runtime["nodes"]["node_1"] == %{"output" => %{user_id: 123}, "context" => %{}}
      assert result.__runtime["nodes"]["node_2"] == %{"output" => %{email: "test@example.com"}, "context" => %{}}
      # Note: executed_nodes not included in simplified rebuild_runtime
      # Note: active_paths not included in simplified rebuild_runtime

      # Verify persistent state
      assert map_size(result.node_executions) == 2
      # All nodes in the map are completed (map size check above is sufficient)
      all_executions = result.node_executions |> Map.values() |> List.flatten()
      completed_nodes = Enum.filter(all_executions, &(&1.status == :completed))
      assert length(completed_nodes) == 2
    end

    test "rebuilding runtime state produces identical results to incremental updates" do
      # Build execution incrementally
      execution = %Execution{
        id: "exec_1",
        workflow_id: "wf_1",
        workflow_version: 1,
        node_executions: %{},
        current_execution_index: 0,
        __runtime: %{
          "nodes" => %{},
          "env" => %{"api_key" => "test"}
        }
      }

      # Build incrementally using the new interface
      node_exec_1 = "exec_1" |> NodeExecution.new("node_1", 0, 0) |> NodeExecution.start()
      completed_node_1 = NodeExecution.complete(node_exec_1, %{user_id: 123}, "success")

      node_exec_2 = "exec_1" |> NodeExecution.new("node_2", 0, 0) |> NodeExecution.start()
      completed_node_2 = NodeExecution.complete(node_exec_2, %{email: "test@example.com"}, "primary")

      incremental_result =
        execution
        |> Execution.complete_node(completed_node_1)
        |> Execution.complete_node(completed_node_2)
        |> then(fn exec ->
          # Create and fail node execution for node_3
          node_exec_3 = "exec_1" |> NodeExecution.new("node_3", 0, 0) |> NodeExecution.start()
          failed_node_3 = NodeExecution.fail(node_exec_3, %{error: "timeout"})
          Execution.fail_node(exec, failed_node_3)
        end)

      # Build execution from scratch via rebuild
      execution_for_rebuild = %Execution{
        id: "exec_1",
        workflow_id: "wf_1",
        workflow_version: 1,
        node_executions: incremental_result.node_executions,
        __runtime: nil
      }

      rebuilt_result = Execution.rebuild_runtime(execution_for_rebuild, %{"api_key" => "test"})

      # Runtime states should be identical
      assert rebuilt_result.__runtime["nodes"] == incremental_result.__runtime["nodes"]
      assert rebuilt_result.__runtime["env"] == incremental_result.__runtime["env"]
      # Note: active_paths not included in simplified rebuild_runtime
      # Note: executed_nodes not included in simplified rebuild_runtime
    end
  end
end
