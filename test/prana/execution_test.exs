defmodule Prana.ExecutionTest do
  use ExUnit.Case
  doctest Prana.Execution

  alias Prana.Execution
  alias Prana.NodeExecution

  describe "runtime state rebuilding" do
    test "rebuild_runtime/2 creates runtime state from node executions" do
      # Setup execution with node executions
      execution = %Execution{
        id: "exec_1",
        workflow_id: "wf_1",
        workflow_version: 1,
        node_executions: [
          %NodeExecution{
            node_id: "node_1",
            status: :completed,
            output_data: %{user_id: 123},
            output_port: "success",
            started_at: ~U[2024-01-01 10:00:00Z]
          },
          %NodeExecution{
            node_id: "node_2",
            status: :completed,
            output_data: %{email: "test@example.com"},
            output_port: "primary",
            started_at: ~U[2024-01-01 10:01:00Z]
          },
          %NodeExecution{
            node_id: "node_3",
            status: :failed,
            error_data: %{error: "network timeout"},
            output_port: nil,
            started_at: ~U[2024-01-01 10:02:00Z]
          }
        ]
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

      assert result.__runtime["active_paths"] == %{
        "node_1_success" => true,
        "node_2_primary" => true
      }

      assert result.__runtime["executed_nodes"] == ["node_1", "node_2", "node_3"]
    end

    test "rebuild_runtime/2 handles empty node executions" do
      execution = %Execution{
        id: "exec_1",
        workflow_id: "wf_1",
        workflow_version: 1,
        node_executions: []
      }

      result = Execution.rebuild_runtime(execution, %{})

      assert result.__runtime["nodes"] == %{}
      assert result.__runtime["env"] == %{}
      assert result.__runtime["active_paths"] == %{}
      assert result.__runtime["executed_nodes"] == []
    end

    test "rebuild_runtime/2 filters out non-completed nodes from runtime state" do
      execution = %Execution{
        id: "exec_1",
        workflow_id: "wf_1",
        workflow_version: 1,
        node_executions: [
          %NodeExecution{
            node_id: "node_1",
            status: :pending,
            output_data: nil,
            output_port: nil,
            started_at: ~U[2024-01-01 10:00:00Z]
          },
          %NodeExecution{
            node_id: "node_2",
            status: :running,
            output_data: nil,
            output_port: nil,
            started_at: ~U[2024-01-01 10:01:00Z]
          },
          %NodeExecution{
            node_id: "node_3",
            status: :completed,
            output_data: %{result: "success"},
            output_port: "done",
            started_at: ~U[2024-01-01 10:02:00Z]
          }
        ]
      }

      result = Execution.rebuild_runtime(execution, %{})

      # Only completed nodes should be in nodes map
      assert result.__runtime["nodes"] == %{"node_3" => %{"output" => %{result: "success"}, "context" => %{}}}
      assert result.__runtime["active_paths"] == %{"node_3_done" => true}
      
      # But all nodes should be in executed_nodes (chronological order)
      assert result.__runtime["executed_nodes"] == ["node_1", "node_2", "node_3"]
    end
  end


  describe "complete_node/2" do
    test "completes node and updates both persistent and runtime state" do
      execution = %Execution{
        id: "exec_1",
        workflow_id: "wf_1",
        workflow_version: 1,
        node_executions: [],
        __runtime: %{
          "nodes" => %{},
          "env" => %{},
          "active_paths" => %{},
          "executed_nodes" => []
        }
      }

      # Create and complete a NodeExecution first
      node_execution = NodeExecution.new("exec_1", "node_1", %{input: "test"})
      |> NodeExecution.start()
      
      output_data = %{result: "success"}
      completed_node_execution = NodeExecution.complete(node_execution, output_data, "success")
      
      result = Execution.complete_node(execution, completed_node_execution)

      # Verify persistent state
      completed_node = Enum.find(result.node_executions, &(&1.node_id == "node_1"))
      assert completed_node.status == :completed
      assert completed_node.output_data == output_data
      assert completed_node.output_port == "success"

      # Verify runtime state
      assert result.__runtime["nodes"]["node_1"] == %{"output" => output_data, "context" => %{}}
      assert result.__runtime["executed_nodes"] == ["node_1"]
      assert result.__runtime["active_paths"]["node_1_success"] == true
    end

    test "integrates completed node execution into execution state" do
      execution = %Execution{
        id: "exec_1",
        workflow_id: "wf_1",
        workflow_version: 1,
        node_executions: [],
        __runtime: %{
          "nodes" => %{},
          "env" => %{},
          "active_paths" => %{},
          "executed_nodes" => []
        }
      }

      # Create and complete a NodeExecution independently
      node_execution = NodeExecution.new("exec_1", "node_1", %{})
      |> NodeExecution.start()
      
      output_data = %{result: "success"}
      completed_node_execution = NodeExecution.complete(node_execution, output_data, "success")
      
      result = Execution.complete_node(execution, completed_node_execution)

      # Should integrate the completed node execution
      assert length(result.node_executions) == 1
      integrated_node = hd(result.node_executions)
      assert integrated_node == completed_node_execution
      assert integrated_node.node_id == "node_1"
      assert integrated_node.status == :completed
      assert integrated_node.output_data == output_data
    end

    test "handles nil runtime state gracefully" do
      execution = %Execution{
        id: "exec_1",
        workflow_id: "wf_1",
        workflow_version: 1,
        node_executions: [],
        __runtime: nil
      }

      # Create and complete a NodeExecution first
      node_execution = NodeExecution.new("exec_1", "node_1", %{})
      |> NodeExecution.start()
      
      completed_node_execution = NodeExecution.complete(node_execution, %{data: "test"}, "success")
      
      result = Execution.complete_node(execution, completed_node_execution)

      # Should still update persistent state
      assert length(result.node_executions) == 1
      integrated_node = hd(result.node_executions)
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
        node_executions: [
          %NodeExecution{
            id: "ne_1",
            execution_id: "exec_1",
            node_id: "node_1",
            status: :running,
            input_data: %{input: "test"},
            started_at: ~U[2024-01-01 10:00:00Z]
          }
        ],
        __runtime: %{
          "nodes" => %{},
          "env" => %{},
          "active_paths" => %{},
          "executed_nodes" => []
        }
      }

      # Create and fail a NodeExecution first
      running_node_execution = Enum.find(execution.node_executions, &(&1.node_id == "node_1"))
      error_data = %{error: "network timeout"}
      failed_node_execution = NodeExecution.fail(running_node_execution, error_data)
      
      result = Execution.fail_node(execution, failed_node_execution)

      # Verify persistent state
      failed_node = Enum.find(result.node_executions, &(&1.node_id == "node_1"))
      assert failed_node.status == :failed
      assert failed_node.error_data == error_data
      assert failed_node.output_port == nil

      # Verify runtime state (failed nodes don't add to nodes map)
      assert result.__runtime["nodes"] == %{}
      assert result.__runtime["executed_nodes"] == ["node_1"]
      assert result.__runtime["active_paths"] == %{}
    end

    test "creates new node execution if none exists" do
      execution = %Execution{
        id: "exec_1",
        workflow_id: "wf_1",
        workflow_version: 1,
        node_executions: [],
        __runtime: %{
          "nodes" => %{},
          "env" => %{},
          "active_paths" => %{},
          "executed_nodes" => []
        }
      }

      # Create and fail a NodeExecution first
      node_execution = NodeExecution.new("exec_1", "node_1", %{})
      |> NodeExecution.start()
      
      error_data = %{error: "test error"}
      failed_node_execution = NodeExecution.fail(node_execution, error_data)
      
      result = Execution.fail_node(execution, failed_node_execution)

      # Should integrate the failed node execution
      assert length(result.node_executions) == 1
      failed_node = hd(result.node_executions)
      assert failed_node.node_id == "node_1"
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
        node_executions: [
          %NodeExecution{
            node_id: "node_1",
            status: :completed,
            output_data: %{user_id: 123},
            output_port: "success",
            started_at: ~U[2024-01-01 10:00:00Z]
          }
        ],
        __runtime: %{
          "nodes" => %{"node_1" => %{"output" => %{user_id: 123}, "context" => %{}}},
          "env" => %{"api_key" => "test"},
          "active_paths" => %{"node_1_success" => true},
          "executed_nodes" => ["node_1"]
        }
      }

      # Complete another node
      node_execution_2 = NodeExecution.new("exec_1", "node_2", %{})
      |> NodeExecution.start()
      
      completed_node_execution_2 = NodeExecution.complete(node_execution_2, %{email: "test@example.com"}, "primary")
      
      result = Execution.complete_node(execution, completed_node_execution_2)

      # Verify state synchronization
      assert result.__runtime["nodes"]["node_1"] == %{"output" => %{user_id: 123}, "context" => %{}}
      assert result.__runtime["nodes"]["node_2"] == %{"output" => %{email: "test@example.com"}, "context" => %{}}
      assert result.__runtime["executed_nodes"] == ["node_1", "node_2"]
      assert result.__runtime["active_paths"]["node_1_success"] == true
      assert result.__runtime["active_paths"]["node_2_primary"] == true

      # Verify persistent state
      assert length(result.node_executions) == 2
      completed_nodes = Enum.filter(result.node_executions, &(&1.status == :completed))
      assert length(completed_nodes) == 2
    end

    test "rebuilding runtime state produces identical results to incremental updates" do
      # Build execution incrementally
      execution = %Execution{
        id: "exec_1",
        workflow_id: "wf_1",
        workflow_version: 1,
        node_executions: [],
        __runtime: %{
          "nodes" => %{},
          "env" => %{"api_key" => "test"},
          "active_paths" => %{},
          "executed_nodes" => []
        }
      }

      # Build incrementally using the new interface
      node_exec_1 = NodeExecution.new("exec_1", "node_1", %{}) |> NodeExecution.start()
      completed_node_1 = NodeExecution.complete(node_exec_1, %{user_id: 123}, "success")
      
      node_exec_2 = NodeExecution.new("exec_1", "node_2", %{}) |> NodeExecution.start()
      completed_node_2 = NodeExecution.complete(node_exec_2, %{email: "test@example.com"}, "primary")
      
      incremental_result = 
        execution
        |> Execution.complete_node(completed_node_1)
        |> Execution.complete_node(completed_node_2)
        |> then(fn exec ->
          # Create and fail node execution for node_3
          node_exec_3 = NodeExecution.new("exec_1", "node_3", %{}) |> NodeExecution.start()
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
      assert rebuilt_result.__runtime["active_paths"] == incremental_result.__runtime["active_paths"]
      assert rebuilt_result.__runtime["executed_nodes"] == incremental_result.__runtime["executed_nodes"]
    end
  end
end