defmodule Prana.ActivePathsTrackingTest do
  @moduledoc """
  Unit tests for active_paths and active_nodes tracking functionality.

  Tests the rebuild_active_paths_and_active_nodes/1 function and 
  complete_node/2 active_paths/active_nodes update logic.
  """

  use ExUnit.Case

  alias Prana.NodeExecution
  alias Prana.WorkflowExecution

  describe "rebuild_active_paths_and_active_nodes" do
    test "correctly builds active_paths and active_nodes from execution data" do
      # Create execution with completed nodes in a simple workflow
      execution = %WorkflowExecution{
        id: "exec_1",
        workflow_id: "wf_1",
        workflow_version: 1,
        execution_graph: %{
          trigger_node_key: "start",
          connection_map: %{
            {"start", "main"} => [%{to: "process"}],
            {"process", "success"} => [%{to: "end"}]
          },
          node_map: %{
            "start" => %{key: "start", name: "Start Node"},
            "process" => %{key: "process", name: "Process Node"},
            "end" => %{key: "end", name: "End Node"}
          }
        },
        node_executions: %{
          "start" => [
            %NodeExecution{
              node_key: "start",
              status: "completed",
              output_data: %{trigger: true},
              output_port: "main",
              execution_index: 0,
              run_index: 0
            }
          ],
          "process" => [
            %NodeExecution{
              node_key: "process",
              status: "completed",
              output_data: %{result: "processed"},
              output_port: "success",
              execution_index: 1,
              run_index: 0
            }
          ]
        },
        current_execution_index: 2
      }

      result = WorkflowExecution.rebuild_runtime(execution, %{})

      # Check active_paths contains completed nodes with their execution indices
      active_paths = result.__runtime["active_paths"]
      assert active_paths["start"] == %{execution_index: 0}
      assert active_paths["process"] == %{execution_index: 1}

      # Check active_nodes contains the next ready node
      active_nodes = result.__runtime["active_nodes"]
      # execution_index + 1 from process node
      assert active_nodes["end"] == 2
    end

    test "handles loop scenarios correctly" do
      # Create execution with a more realistic loop scenario (A -> B -> A)
      execution = %WorkflowExecution{
        id: "exec_1",
        workflow_id: "wf_1",
        workflow_version: 1,
        execution_graph: %{
          trigger_node_key: "start",
          connection_map: %{
            {"start", "main"} => [%{to: "loop_node"}],
            {"loop_node", "continue"} => [%{to: "intermediate"}],
            # Loop back 
            {"intermediate", "loop_back"} => [%{to: "loop_node"}],
            {"loop_node", "exit"} => [%{to: "end"}]
          },
          node_map: %{
            "start" => %{key: "start", name: "Start Node"},
            "loop_node" => %{key: "loop_node", name: "Loop Node"},
            "intermediate" => %{key: "intermediate", name: "Intermediate Node"},
            "end" => %{key: "end", name: "End Node"}
          }
        },
        node_executions: %{
          "start" => [
            %NodeExecution{
              node_key: "start",
              status: "completed",
              output_data: %{trigger: true},
              output_port: "main",
              execution_index: 0,
              run_index: 0
            }
          ],
          "loop_node" => [
            # First execution of loop node
            %NodeExecution{
              node_key: "loop_node",
              status: "completed",
              output_data: %{iteration: 1},
              output_port: "continue",
              execution_index: 1,
              run_index: 0
            }
          ],
          "intermediate" => [
            %NodeExecution{
              node_key: "intermediate",
              status: "completed",
              output_data: %{processed: true},
              output_port: "loop_back",
              execution_index: 2,
              run_index: 0
            }
          ]
        },
        current_execution_index: 3
      }

      result = WorkflowExecution.rebuild_runtime(execution, %{})

      # Check active_paths contains completed nodes
      active_paths = result.__runtime["active_paths"]
      assert active_paths["start"] == %{execution_index: 0}
      assert active_paths["loop_node"] == %{execution_index: 1}
      assert active_paths["intermediate"] == %{execution_index: 2}

      # Check active_nodes - loop_node should be ready for re-execution (loop detected)
      active_nodes = result.__runtime["active_nodes"]
      # execution_index + 1 from intermediate
      assert active_nodes["loop_node"] == 3
    end

    test "handles trigger not executed scenario" do
      execution = %WorkflowExecution{
        id: "exec_1",
        workflow_id: "wf_1",
        workflow_version: 1,
        execution_graph: %{
          trigger_node_key: "start",
          connection_map: %{
            {"start", "main"} => [%{to: "next"}]
          },
          node_map: %{
            "start" => %{key: "start", name: "Start Node"},
            "next" => %{key: "next", name: "Next Node"}
          }
        },
        # No executions yet
        node_executions: %{},
        current_execution_index: 0
      }

      result = WorkflowExecution.rebuild_runtime(execution, %{})

      # Should have empty active_paths and trigger in active_nodes with depth 0
      active_paths = result.__runtime["active_paths"]
      active_nodes = result.__runtime["active_nodes"]

      assert active_paths == %{}
      assert active_nodes["start"] == 0
    end

    test "handles self-referencing loops without infinite recursion" do
      # Test DFS cycle detection with a self-referencing node
      execution = %WorkflowExecution{
        id: "exec_1",
        workflow_id: "wf_1",
        workflow_version: 1,
        execution_graph: %{
          trigger_node_key: "start",
          connection_map: %{
            {"start", "main"} => [%{to: "self_loop"}],
            # Self-referencing loop
            {"self_loop", "continue"} => [%{to: "self_loop"}],
            {"self_loop", "exit"} => [%{to: "end"}]
          },
          node_map: %{
            "start" => %{key: "start", name: "Start Node"},
            "self_loop" => %{key: "self_loop", name: "Self Loop Node"},
            "end" => %{key: "end", name: "End Node"}
          }
        },
        node_executions: %{
          "start" => [
            %NodeExecution{
              node_key: "start",
              status: "completed",
              output_data: %{trigger: true},
              output_port: "main",
              execution_index: 0,
              run_index: 0
            }
          ],
          "self_loop" => [
            %NodeExecution{
              node_key: "self_loop",
              status: "completed",
              output_data: %{iteration: 1},
              output_port: "continue",
              execution_index: 1,
              run_index: 0
            }
          ]
        },
        current_execution_index: 2
      }

      # This should complete without infinite recursion
      result = WorkflowExecution.rebuild_runtime(execution, %{})

      # Verify results
      active_paths = result.__runtime["active_paths"]
      assert active_paths["start"] == %{execution_index: 0}
      assert active_paths["self_loop"] == %{execution_index: 1}

      # self_loop gets added to active_paths (execution_index: 1 > start's 0)
      # When self_loop tries to connect to itself, execution_index comparison (1 == 1) 
      # prevents further traversal and adds it to active_nodes for re-execution
      active_nodes = result.__runtime["active_nodes"]
      # Ready for next iteration
      assert active_nodes["self_loop"] == 2
    end
  end

  describe "complete_node active_paths and active_nodes updates" do
    test "updates active_paths and active_nodes correctly" do
      # Setup execution with runtime state
      execution = %WorkflowExecution{
        id: "exec_1",
        workflow_id: "wf_1",
        workflow_version: 1,
        execution_graph: %{
          trigger_node_key: "start",
          connection_map: %{
            {"node_1", "success"} => [%{to: "node_2"}, %{to: "node_3"}],
            {"node_2", "done"} => [%{to: "node_4"}]
          },
          node_map: %{
            "node_1" => %{key: "node_1", name: "Node 1"},
            "node_2" => %{key: "node_2", name: "Node 2"},
            "node_3" => %{key: "node_3", name: "Node 3"},
            "node_4" => %{key: "node_4", name: "Node 4"}
          }
        },
        node_executions: %{},
        current_execution_index: 1,
        __runtime: %{
          "nodes" => %{},
          "env" => %{},
          # node_1 is ready
          "active_nodes" => %{"node_1" => 0},
          # No completed nodes yet
          "active_paths" => %{}
        }
      }

      # Create and complete node_1
      node_execution =
        "node_1"
        |> NodeExecution.new(0, 0)
        |> NodeExecution.start()
        |> NodeExecution.complete(%{result: "success"}, "success")

      result = WorkflowExecution.complete_node(execution, node_execution)

      # Verify active_paths updated
      active_paths = result.__runtime["active_paths"]
      assert active_paths["node_1"] == %{execution_index: 0}

      # Verify active_nodes updated - node_1 removed, target nodes added
      active_nodes = result.__runtime["active_nodes"]
      # Should be removed
      refute Map.has_key?(active_nodes, "node_1")
      # execution_index + 1
      assert active_nodes["node_2"] == 1
      # execution_index + 1
      assert active_nodes["node_3"] == 1
    end

    test "handles loop-back scenarios in active_paths" do
      # Setup execution where completing a node creates a loop-back
      execution = %WorkflowExecution{
        id: "exec_1",
        workflow_id: "wf_1",
        workflow_version: 1,
        execution_graph: %{
          trigger_node_key: "start",
          connection_map: %{
            {"loop_node", "continue"} => [%{to: "intermediate"}],
            # Loop back
            {"intermediate", "done"} => [%{to: "loop_node"}]
          },
          node_map: %{
            "loop_node" => %{key: "loop_node", name: "Loop Node"},
            "intermediate" => %{key: "intermediate", name: "Intermediate Node"}
          }
        },
        node_executions: %{
          "loop_node" => [
            %NodeExecution{
              node_key: "loop_node",
              status: "completed",
              output_data: %{iteration: 1},
              output_port: "continue",
              execution_index: 0,
              run_index: 0
            }
          ]
        },
        current_execution_index: 2,
        __runtime: %{
          "nodes" => %{
            "loop_node" => %{"output" => %{iteration: 1}}
          },
          "env" => %{},
          "active_nodes" => %{"intermediate" => 1},
          "active_paths" => %{
            "loop_node" => %{execution_index: 0},
            # Simulated future execution
            "some_future_node" => %{execution_index: 5}
          }
        }
      }

      # Complete intermediate node which loops back to loop_node
      node_execution =
        "intermediate"
        |> NodeExecution.new(1, 0)
        |> NodeExecution.start()
        |> NodeExecution.complete(%{processed: true}, "done")

      result = WorkflowExecution.complete_node(execution, node_execution)

      # Check active_paths - should add intermediate and clean up future nodes if loop detected
      active_paths = result.__runtime["active_paths"]
      assert active_paths["intermediate"] == %{execution_index: 1}

      # If loop_node already exists in active_paths, future nodes should be cleaned up
      # In this case, loop_node has execution_index: 0, so some_future_node (index: 5) should be removed
      refute Map.has_key?(active_paths, "some_future_node")
      # Should remain unchanged
      assert active_paths["loop_node"] == %{execution_index: 0}

      # Check active_nodes - should add loop_node for re-execution
      active_nodes = result.__runtime["active_nodes"]
      # Should be removed
      refute Map.has_key?(active_nodes, "intermediate")
      # execution_index + 1
      assert active_nodes["loop_node"] == 2
    end

    test "with no execution_graph handles gracefully" do
      # Test defensive programming for missing execution_graph
      execution = %WorkflowExecution{
        id: "exec_1",
        workflow_id: "wf_1",
        workflow_version: 1,
        # Missing execution graph
        execution_graph: nil,
        node_executions: %{},
        current_execution_index: 1,
        __runtime: %{
          "nodes" => %{},
          "env" => %{},
          "active_nodes" => %{"node_1" => 0},
          "active_paths" => %{}
        }
      }

      node_execution =
        "node_1"
        |> NodeExecution.new(0, 0)
        |> NodeExecution.start()
        |> NodeExecution.complete(%{result: "success"}, "success")

      result = WorkflowExecution.complete_node(execution, node_execution)

      # Should still update active_paths and remove completed node from active_nodes
      active_paths = result.__runtime["active_paths"]
      assert active_paths["node_1"] == %{execution_index: 0}

      active_nodes = result.__runtime["active_nodes"]
      refute Map.has_key?(active_nodes, "node_1")
    end
  end
end
