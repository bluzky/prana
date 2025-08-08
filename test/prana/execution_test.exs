defmodule Prana.ExecutionTest do
  use ExUnit.Case

  alias Prana.NodeExecution
  alias Prana.WorkflowExecution

  # doctest Prana.WorkflowExecution

  describe "runtime state rebuilding" do
    test "rebuild_runtime/2 creates runtime state from node executions" do
      # Setup execution with node executions
      execution = %WorkflowExecution{
        id: "exec_1",
        workflow_id: "wf_1",
        workflow_version: 1,
        execution_graph: %{
          trigger_node_key: "node_1",
          connection_map: %{},
          node_map: %{
            "node_1" => %{key: "node_1", name: "Node 1"},
            "node_2" => %{key: "node_2", name: "Node 2"},
            "node_3" => %{key: "node_3", name: "Node 3"}
          },
          reverse_connection_map: %{}
        },
        node_executions: %{
          "node_1" => [
            %NodeExecution{
              node_key: "node_1",
              status: "completed",
              output_data: %{user_id: 123},
              output_port: "main",
              started_at: ~U[2024-01-01 10:00:00Z],
              execution_index: 0,
              run_index: 0
            }
          ],
          "node_2" => [
            %NodeExecution{
              node_key: "node_2",
              status: "completed",
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
              status: "failed",
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
      result = WorkflowExecution.rebuild_runtime(execution, env_data)

      # Verify runtime state structure
      assert result.__runtime["nodes"] == %{
               "node_1" => %{"output" => %{user_id: 123}, "context" => %{}},
               "node_2" => %{"output" => %{email: "test@example.com"}, "context" => %{}}
             }

      assert result.__runtime["env"] == env_data

      # Note: active_paths and executed_nodes not included in simplified rebuild_runtime
    end

    test "rebuild_runtime/2 handles empty node executions" do
      execution = %WorkflowExecution{
        id: "exec_1",
        workflow_id: "wf_1",
        workflow_version: 1,
        node_executions: %{},
        current_execution_index: 0,
        execution_graph: %{
          trigger_node_key: "start_node",
          connection_map: %{},
          node_map: %{},
          reverse_connection_map: %{}
        }
      }

      result = WorkflowExecution.rebuild_runtime(execution, %{})

      assert result.__runtime["nodes"] == %{}
      assert result.__runtime["env"] == %{}
    end

    test "rebuild_runtime/2 filters out non-completed nodes from runtime state" do
      execution = %WorkflowExecution{
        id: "exec_1",
        workflow_id: "wf_1",
        workflow_version: 1,
        execution_graph: %{
          trigger_node_key: "node_1",
          connection_map: %{},
          node_map: %{
            "node_1" => %{key: "node_1", name: "Node 1"},
            "node_2" => %{key: "node_2", name: "Node 2"},
            "node_3" => %{key: "node_3", name: "Node 3"}
          },
          reverse_connection_map: %{}
        },
        node_executions: %{
          "node_1" => [
            %NodeExecution{
              node_key: "node_1",
              status: "pending",
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
              status: "running",
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
              status: "completed",
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

      result = WorkflowExecution.rebuild_runtime(execution, %{})

      # Only completed nodes should be in nodes map
      assert result.__runtime["nodes"] == %{"node_3" => %{"output" => %{result: "success"}, "context" => %{}}}
    end
  end

  describe "complete_node/2" do
    test "completes node and updates both persistent and runtime state" do
      execution = %WorkflowExecution{
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
        "node_1"
        |> NodeExecution.new(0, 0)
        |> NodeExecution.start()

      output_data = %{result: "success"}
      completed_node_execution = NodeExecution.complete(node_execution, output_data, "main")

      result = WorkflowExecution.complete_node(execution, completed_node_execution)

      # Verify persistent state (map structure)
      assert Map.has_key?(result.node_executions, "node_1")
      [completed_node] = result.node_executions["node_1"]
      assert completed_node.status == "completed"
      assert completed_node.output_data == output_data
      assert completed_node.output_port == "main"

      # Verify runtime state
      assert result.__runtime["nodes"]["node_1"] == %{"output" => output_data, "context" => %{}}
    end

    test "integrates completed node execution into execution state" do
      execution = %WorkflowExecution{
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
        "node_1"
        |> NodeExecution.new(0, 0)
        |> NodeExecution.start()

      output_data = %{result: "success"}
      completed_node_execution = NodeExecution.complete(node_execution, output_data, "main")

      result = WorkflowExecution.complete_node(execution, completed_node_execution)

      # Should integrate the completed node execution
      assert map_size(result.node_executions) == 1
      [integrated_node] = result.node_executions["node_1"]
      assert integrated_node == completed_node_execution
      assert integrated_node.node_key == "node_1"
      assert integrated_node.status == "completed"
      assert integrated_node.output_data == output_data
    end

    test "handles nil runtime state gracefully" do
      execution = %WorkflowExecution{
        id: "exec_1",
        workflow_id: "wf_1",
        workflow_version: 1,
        node_executions: %{},
        current_execution_index: 0,
        __runtime: nil
      }

      # Create and complete a NodeExecution first
      node_execution =
        "node_1"
        |> NodeExecution.new(0, 0)
        |> NodeExecution.start()

      completed_node_execution = NodeExecution.complete(node_execution, %{data: "test"}, "main")

      result = WorkflowExecution.complete_node(execution, completed_node_execution)

      # Should still update persistent state
      assert map_size(result.node_executions) == 1
      [integrated_node] = result.node_executions["node_1"]
      assert integrated_node.status == "completed"

      # Runtime should remain nil
      assert result.__runtime == nil
    end
  end

  describe "fail_node/2" do
    test "fails node and updates both persistent and runtime state" do
      execution = %WorkflowExecution{
        id: "exec_1",
        workflow_id: "wf_1",
        workflow_version: 1,
        node_executions: %{
          "node_1" => [
            %NodeExecution{
              node_key: "node_1",
              status: "running",
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

      result = WorkflowExecution.fail_node(execution, failed_node_execution)

      # Verify persistent state
      [failed_node] = result.node_executions["node_1"]
      assert failed_node.status == "failed"
      assert failed_node.error_data == error_data
      assert failed_node.output_port == nil

      # Verify runtime state (failed nodes don't add to nodes map)
      assert result.__runtime["nodes"] == %{}
      # Note: executed_nodes not included in simplified rebuild_runtime
      # Note: active_paths not included in simplified rebuild_runtime
    end

    test "creates new node execution if none exists" do
      execution = %WorkflowExecution{
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
        "node_1"
        |> NodeExecution.new(0, 0)
        |> NodeExecution.start()

      error_data = %{error: "test error"}
      failed_node_execution = NodeExecution.fail(node_execution, error_data)

      result = WorkflowExecution.fail_node(execution, failed_node_execution)

      # Should integrate the failed node execution
      assert map_size(result.node_executions) == 1
      [failed_node] = result.node_executions["node_1"]
      assert failed_node.node_key == "node_1"
      assert failed_node.status == "failed"
      assert failed_node.error_data == error_data
    end
  end

  describe "state synchronization" do
    test "complete_node maintains state synchronization" do
      # Start with execution that has existing completed nodes
      execution = %WorkflowExecution{
        id: "exec_1",
        workflow_id: "wf_1",
        workflow_version: 1,
        node_executions: %{
          "node_1" => [
            %NodeExecution{
              node_key: "node_1",
              status: "completed",
              output_data: %{user_id: 123},
              output_port: "main",
              started_at: ~U[2024-01-01 10:00:00Z],
              execution_index: 0,
              run_index: 0
            }
          ]
        },
        current_execution_index: 1,
        __runtime: %{
          "nodes" => %{"node_1" => %{"output" => %{user_id: 123}}},
          "env" => %{"api_key" => "test"}
        }
      }

      # Complete another node
      node_execution_2 =
        "node_2"
        |> NodeExecution.new(0, 0)
        |> NodeExecution.start()

      completed_node_execution_2 = NodeExecution.complete(node_execution_2, %{email: "test@example.com"}, "primary")

      result = WorkflowExecution.complete_node(execution, completed_node_execution_2)

      # Verify state synchronization
      assert result.__runtime["nodes"]["node_1"] == %{"output" => %{user_id: 123}}
      assert result.__runtime["nodes"]["node_2"] == %{"output" => %{email: "test@example.com"}, "context" => %{}}
      # Note: executed_nodes not included in simplified rebuild_runtime
      # Note: active_paths not included in simplified rebuild_runtime

      # Verify persistent state
      assert map_size(result.node_executions) == 2
      # All nodes in the map are completed (map size check above is sufficient)
      all_executions = result.node_executions |> Map.values() |> List.flatten()
      completed_nodes = Enum.filter(all_executions, &(&1.status == "completed"))
      assert length(completed_nodes) == 2
    end

    test "rebuilding runtime state produces identical results to incremental updates" do
      # Build execution incrementally
      execution = %WorkflowExecution{
        id: "exec_1",
        workflow_id: "wf_1",
        workflow_version: 1,
        node_executions: %{},
        current_execution_index: 0,
        execution_graph: %{
          trigger_node_key: "node_1",
          connection_map: %{},
          node_map: %{
            "node_1" => %{key: "node_1", name: "Node 1"},
            "node_2" => %{key: "node_2", name: "Node 2"},
            "node_3" => %{key: "node_3", name: "Node 3"}
          },
          reverse_connection_map: %{}
        },
        __runtime: %{
          "nodes" => %{},
          "env" => %{"api_key" => "test"}
        }
      }

      # Build incrementally using the new interface
      node_exec_1 = "node_1" |> NodeExecution.new(0, 0) |> NodeExecution.start()
      completed_node_1 = NodeExecution.complete(node_exec_1, %{user_id: 123}, "main")

      node_exec_2 = "node_2" |> NodeExecution.new(0, 0) |> NodeExecution.start()
      completed_node_2 = NodeExecution.complete(node_exec_2, %{email: "test@example.com"}, "primary")

      incremental_result =
        execution
        |> WorkflowExecution.complete_node(completed_node_1)
        |> WorkflowExecution.complete_node(completed_node_2)
        |> then(fn exec ->
          # Create and fail node execution for node_3
          node_exec_3 = "node_3" |> NodeExecution.new(0, 0) |> NodeExecution.start()
          failed_node_3 = NodeExecution.fail(node_exec_3, %{error: "timeout"})
          WorkflowExecution.fail_node(exec, failed_node_3)
        end)

      # Build execution from scratch via rebuild
      execution_for_rebuild = %WorkflowExecution{
        id: "exec_1",
        workflow_id: "wf_1",
        workflow_version: 1,
        node_executions: incremental_result.node_executions,
        execution_graph: incremental_result.execution_graph,
        __runtime: nil
      }

      rebuilt_result = WorkflowExecution.rebuild_runtime(execution_for_rebuild, %{"api_key" => "test"})

      # Runtime states should be identical
      assert rebuilt_result.__runtime["nodes"] == incremental_result.__runtime["nodes"]
      assert rebuilt_result.__runtime["env"] == incremental_result.__runtime["env"]
      # Note: active_paths not included in simplified rebuild_runtime
      # Note: executed_nodes not included in simplified rebuild_runtime
    end
  end

  describe "execution state management" do
    test "update_shared_state/2 merges new values with existing state" do
      execution = %WorkflowExecution{
        id: "exec_1",
        workflow_id: "wf_1",
        execution_data: %{
          "context_data" => %{
            "workflow" => %{"counter" => 5, "email" => "test@example.com"},
            "node" => %{}
          },
          "active_paths" => %{},
          "active_nodes" => %{}
        }
      }

      # Update only counter, email should be preserved
      updates = %{"counter" => 10}
      updated_execution = WorkflowExecution.update_execution_context(execution, updates)

      # Check execution_data workflow context - counter updated, email preserved
      workflow_context = updated_execution.execution_data["context_data"]["workflow"]
      assert workflow_context["counter"] == 10
      assert workflow_context["email"] == "test@example.com"
    end

    test "update_shared_state/2 adds new values while preserving existing" do
      execution = %WorkflowExecution{
        id: "exec_1",
        workflow_id: "wf_1",
        execution_data: %{
          "context_data" => %{
            "workflow" => %{"counter" => 1, "email" => "test@example.com"},
            "node" => %{}
          },
          "active_paths" => %{},
          "active_nodes" => %{}
        }
      }

      # Add user_id, update counter, preserve email
      updates = %{"user_id" => 123, "counter" => 2}
      updated_execution = WorkflowExecution.update_execution_context(execution, updates)

      workflow_context = updated_execution.execution_data["context_data"]["workflow"]
      assert workflow_context["counter"] == 2
      # preserved
      assert workflow_context["email"] == "test@example.com"
      # added
      assert workflow_context["user_id"] == 123
    end

    test "rebuild_runtime/2 no longer restores shared state (now in execution_data)" do
      execution = %WorkflowExecution{
        id: "exec_1",
        workflow_id: "wf_1",
        execution_data: %{
          "context_data" => %{
            "workflow" => %{"counter" => 5, "user_data" => %{"name" => "test"}},
            "node" => %{}
          },
          "active_paths" => %{},
          "active_nodes" => %{}
        },
        node_executions: %{},
        execution_graph: %{trigger_node_key: "trigger", connection_map: %{}},
        __runtime: nil
      }

      rebuilt_execution = WorkflowExecution.rebuild_runtime(execution, %{})

      # Workflow context should remain in execution_data, not in __runtime
      workflow_context = rebuilt_execution.execution_data["context_data"]["workflow"]
      assert workflow_context["counter"] == 5
      assert workflow_context["user_data"]["name"] == "test"

      # __runtime should not have shared_state
      refute Map.has_key?(rebuilt_execution.__runtime, "shared_state")
    end

    test "workflow context survives suspension and resume cycles" do
      # Initial execution with workflow context
      execution = %WorkflowExecution{
        id: "exec_1",
        workflow_id: "wf_1",
        execution_data: %{
          "context_data" => %{
            "workflow" => %{"session_id" => "abc123", "step" => 1},
            "node" => %{}
          },
          "active_paths" => %{},
          "active_nodes" => %{}
        },
        node_executions: %{},
        execution_graph: %{trigger_node_key: "trigger", connection_map: %{}},
        __runtime: %{}
      }

      # Update workflow context before suspension
      updated_execution = WorkflowExecution.update_execution_context(execution, %{"step" => 2, "data" => "important"})

      # Simulate suspension (runtime state lost)
      suspended_execution = %{updated_execution | __runtime: nil}

      # Rebuild runtime (simulating resume)
      resumed_execution = WorkflowExecution.rebuild_runtime(suspended_execution, %{})
      workflow_context = resumed_execution.execution_data["context_data"]["workflow"]

      # Workflow context should be preserved in execution_data
      assert workflow_context["session_id"] == "abc123"
      assert workflow_context["step"] == 2
      assert workflow_context["data"] == "important"

      # __runtime should not have shared_state
      refute Map.has_key?(resumed_execution.__runtime, "shared_state")
    end
  end

  describe "context management API" do
    test "get_node_context/2 returns empty map for non-existent node context" do
      execution = %WorkflowExecution{
        id: "exec_1",
        workflow_id: "wf_1",
        execution_data: %{
          "context_data" => %{
            "workflow" => %{},
            "node" => %{}
          },
          "active_paths" => %{},
          "active_nodes" => %{}
        }
      }

      result = WorkflowExecution.get_node_context(execution, "non_existent_node")
      assert result == %{}
    end

    test "get_node_context/2 returns existing node context" do
      execution = %WorkflowExecution{
        id: "exec_1",
        workflow_id: "wf_1",
        execution_data: %{
          "context_data" => %{
            "workflow" => %{},
            "node" => %{
              "test_node" => %{"counter" => 5, "status" => "active"}
            }
          },
          "active_paths" => %{},
          "active_nodes" => %{}
        }
      }

      result = WorkflowExecution.get_node_context(execution, "test_node")
      assert result == %{"counter" => 5, "status" => "active"}
    end

    test "update_node_context/3 creates new node context when none exists" do
      execution = %WorkflowExecution{
        id: "exec_1",
        workflow_id: "wf_1",
        execution_data: %{
          "context_data" => %{
            "workflow" => %{},
            "node" => %{}
          },
          "active_paths" => %{},
          "active_nodes" => %{}
        }
      }

      result = WorkflowExecution.update_node_context(execution, "new_node", %{"step" => 1})

      node_context = WorkflowExecution.get_node_context(result, "new_node")
      assert node_context == %{"step" => 1}
    end

    test "update_node_context/3 merges updates with existing context" do
      execution = %WorkflowExecution{
        id: "exec_1",
        workflow_id: "wf_1",
        execution_data: %{
          "context_data" => %{
            "workflow" => %{},
            "node" => %{
              "existing_node" => %{"counter" => 3, "name" => "test"}
            }
          },
          "active_paths" => %{},
          "active_nodes" => %{}
        }
      }

      result = WorkflowExecution.update_node_context(execution, "existing_node", %{"counter" => 5, "status" => "updated"})

      node_context = WorkflowExecution.get_node_context(result, "existing_node")
      assert node_context == %{"counter" => 5, "name" => "test", "status" => "updated"}
    end
  end
end
