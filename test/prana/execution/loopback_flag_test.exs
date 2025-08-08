defmodule Prana.Execution.LoopbackFlagTest do
  @moduledoc """
  Unit tests for loopback flag functionality in execution context.
  
  Tests verify that:
  - loopback flag is false on first node execution
  - loopback flag is true when node is executed again (loop-back scenario)
  - loopback flag is accessible in template context
  - loopback flag works correctly with complex loop patterns
  """

  use ExUnit.Case, async: false

  alias Prana.Connection
  alias Prana.GraphExecutor
  alias Prana.Integrations.Data
  alias Prana.Integrations.Logic
  alias Prana.Integrations.Manual
  alias Prana.Node
  alias Prana.Workflow
  alias Prana.WorkflowCompiler
  alias Prana.WorkflowExecution

  # ============================================================================
  # Setup and Helpers
  # ============================================================================

  setup do
    # Start integration registry for each test
    Code.ensure_loaded(Logic)
    Code.ensure_loaded(Manual)
    Code.ensure_loaded(Data)
    {:ok, registry_pid} = Prana.IntegrationRegistry.start_link()

    # Register required integrations
    :ok = Prana.IntegrationRegistry.register_integration(Logic)
    :ok = Prana.IntegrationRegistry.register_integration(Manual)
    :ok = Prana.IntegrationRegistry.register_integration(Data)

    on_exit(fn ->
      if Process.alive?(registry_pid) do
        GenServer.stop(registry_pid)
      end
    end)

    :ok
  end

  defp convert_connections_to_map(workflow) do
    connections_list = workflow.connections

    # Convert to proper map structure using add_connection
    workflow_with_empty_connections = %{workflow | connections: %{}}

    Enum.reduce(connections_list, workflow_with_empty_connections, fn connection, acc_workflow ->
      {:ok, updated_workflow} = Workflow.add_connection(acc_workflow, connection)
      updated_workflow
    end)
  end

  defp create_test_execution do
    %WorkflowExecution{
      id: "test_execution",
      workflow_id: "test_workflow",
      workflow_version: 1,
      execution_mode: :async,
      status: "running",
      vars: %{},
      node_executions: %{},
      current_execution_index: 0,
      __runtime: %{
        "env" => %{},
        "executed_nodes" => [],
        "nodes" => %{}
      },
      execution_data: %{
        "context_data" => %{
          "workflow" => %{},
          "node" => %{}
        },
        "active_paths" => %{},
        "active_nodes" => %{}
      }
    }
  end


  # ============================================================================
  # Unit Tests - Direct NodeExecutor Testing
  # ============================================================================

  describe "loopback_node? function" do
    test "returns false when node not in active_paths" do
      node = %Node{
        key: "new_node",
        name: "New Node", 
        type: "data.set_data",
        params: %{}
      }

      # Create execution with different node in active_paths
      execution = %{create_test_execution() | 
        __runtime: %{
          "env" => %{},
          "executed_nodes" => ["other_node"],
          "nodes" => %{}
        },
        execution_data: %{
          "context_data" => %{
            "workflow" => %{},
            "node" => %{}
          },
          "active_paths" => %{"other_node" => %{execution_index: 0}},
          "active_nodes" => %{}
        }
      }

      # Test loopback_node? function directly
      assert WorkflowExecution.loopback_node?(execution, node) == false
    end

    test "returns true when node exists in active_paths" do
      node = %Node{
        key: "loop_node",
        name: "Loop Node",
        type: "data.set_data",
        params: %{}
      }

      # Create execution with node already in active_paths
      execution = %{create_test_execution() | 
        __runtime: %{
          "env" => %{},
          "executed_nodes" => ["loop_node"],
          "nodes" => %{}
        },
        execution_data: %{
          "context_data" => %{
            "workflow" => %{},
            "node" => %{}
          },
          "active_paths" => %{"loop_node" => %{execution_index: 0}},
          "active_nodes" => %{}
        }
      }

      # Test loopback_node? function directly
      assert WorkflowExecution.loopback_node?(execution, node) == true
    end

    test "returns false when active_paths is empty" do
      node = %Node{
        key: "test_node",
        name: "Test Node",
        type: "data.set_data",
        params: %{}
      }

      execution = create_test_execution()

      assert WorkflowExecution.loopback_node?(execution, node) == false
    end
  end

  # ============================================================================
  # Integration Tests - Full Workflow Execution
  # ============================================================================

  describe "loopback flag in workflow execution" do
    defp create_simple_loop_workflow_with_capture do
      %Workflow{
        id: "loopback_test_workflow",
        name: "Loopback Flag Test Workflow",
        nodes: [
          # Start node
          %Node{
            key: "start",
            name: "Start",
            type: "manual.trigger",
            params: %{}
          },

          # Initialize counter
          %Node{
            key: "init",
            name: "Initialize",
            type: "data.set_data", 
            params: %{"counter" => 0}
          },

          # Loop node that captures loopback flag using template
          %Node{
            key: "loop_capture",
            name: "Loop with Capture",
            type: "data.set_data",
            params: %{
              "mapping_map" => %{
                "loopback_captured" => "{{$execution.loopback}}",
                "execution_index" => "{{$execution.execution_index}}",
                "run_index" => "{{$execution.run_index}}"
              }
            }
          },

          # Increment counter
          %Node{
            key: "increment",
            name: "Increment",
            type: "data.set_data",
            params: %{
              "counter" => "{{$execution.run_index + 1}}"
            }
          },

          # Loop condition
          %Node{
            key: "condition",
            name: "Loop Condition", 
            type: "logic.if_condition",
            params: %{
              "condition" => "{{$execution.run_index < 2}}"
            }
          },

          # Complete
          %Node{
            key: "complete",
            name: "Complete",
            type: "data.set_data",
            params: %{"result" => "done"}
          }
        ],
        connections: [
          %Connection{from: "start", from_port: "main", to: "init", to_port: "main"},
          %Connection{from: "init", from_port: "main", to: "loop_capture", to_port: "main"},
          %Connection{from: "loop_capture", from_port: "main", to: "increment", to_port: "main"},
          %Connection{from: "increment", from_port: "main", to: "condition", to_port: "main"},
          # Loop back connection
          %Connection{from: "condition", from_port: "true", to: "loop_capture", to_port: "main"},
          # Exit connection
          %Connection{from: "condition", from_port: "false", to: "complete", to_port: "main"}
        ],
        variables: %{}
      }
    end

    test "loopback flag progression through loop iterations" do
      workflow = convert_connections_to_map(create_simple_loop_workflow_with_capture())

      # Compile workflow
      {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "start")

      # Create execution context
      context = %{
        workflow_loader: fn _id -> {:error, "not implemented"} end,
        variables: %{}
      }

      # Execute workflow
      {:ok, execution, _} = GraphExecutor.execute_workflow(execution_graph, context)

      assert execution.status == "completed"

      # Get all executions of loop_capture node
      loop_capture_executions = Map.get(execution.node_executions, "loop_capture", [])
      
      # Should have multiple executions (3 iterations: 0, 1, 2)
      assert length(loop_capture_executions) == 3

      # Sort by run_index to check progression
      sorted_executions = Enum.sort_by(loop_capture_executions, & &1.run_index)

      # First execution (run_index 0) - should have loopback: false
      first_execution = Enum.at(sorted_executions, 0)
      assert first_execution.output_data["loopback_captured"] == false
      assert first_execution.output_data["run_index"] == 0

      # Second execution (run_index 1) - should have loopback: true
      second_execution = Enum.at(sorted_executions, 1) 
      assert second_execution.output_data["loopback_captured"] == true
      assert second_execution.output_data["run_index"] == 1

      # Third execution (run_index 2) - should have loopback: true
      third_execution = Enum.at(sorted_executions, 2)
      assert third_execution.output_data["loopback_captured"] == true
      assert third_execution.output_data["run_index"] == 2
    end
  end

  # ============================================================================
  # Loop Metadata Tests
  # ============================================================================

  describe "loop metadata in execution context" do
    test "provides loop metadata for nodes with loop annotations" do
      # Create a simple workflow where we can manually add loop metadata to test nodes
      workflow = %Workflow{
        id: "loop_metadata_test",
        name: "Loop Metadata Test",
        nodes: [
          %Node{
            key: "start",
            name: "Start",
            type: "manual.trigger",
            params: %{}
          },
          
          %Node{
            key: "loop_node",
            name: "Loop Node",
            type: "data.set_data",
            params: %{
              "mapping_map" => %{
                "loop_level" => "{{$execution.loop.loop_level}}",
                "loop_role" => "{{$execution.loop.loop_role}}",
                "loop_ids" => "{{$execution.loop.loop_ids}}",
                "loopback" => "{{$execution.loop.loopback}}"
              }
            },
            # Manually add loop metadata to test the functionality
            metadata: %{
              loop_level: 1,
              loop_role: :start_loop,
              loop_ids: ["loop_1"]
            }
          }
        ],
        connections: %{
          "start" => %{
            "main" => [%Connection{from: "start", from_port: "main", to: "loop_node", to_port: "main"}]
          }
        },
        variables: %{}
      }

      # Compile and execute
      {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "start")
      
      context = %{
        workflow_loader: fn _id -> {:error, "not implemented"} end,
        variables: %{}
      }

      {:ok, execution, _} = GraphExecutor.execute_workflow(execution_graph, context)

      assert execution.status == "completed"

      # Check loop_node execution captured the loop metadata
      loop_executions = Map.get(execution.node_executions, "loop_node", [])
      assert length(loop_executions) == 1
      
      loop_execution = List.first(loop_executions)
      assert loop_execution.output_data["loop_level"] == 1
      assert loop_execution.output_data["loop_role"] == "start_loop"
      assert loop_execution.output_data["loop_ids"] == ["loop_1"]
      assert loop_execution.output_data["loopback"] == false  # First execution, no loopback
    end

    test "provides default loop metadata for non-loop nodes" do
      workflow = %Workflow{
        id: "non_loop_test",
        name: "Non-Loop Test",
        nodes: [
          %Node{
            key: "start",
            name: "Start",
            type: "manual.trigger",
            params: %{}
          },
          
          %Node{
            key: "regular_node",
            name: "Regular Node",
            type: "data.set_data",
            params: %{
              "mapping_map" => %{
                "loop_level" => "{{$execution.loop.loop_level}}",
                "loop_role" => "{{$execution.loop.loop_role}}",
                "loop_ids" => "{{$execution.loop.loop_ids}}",
                "loopback" => "{{$execution.loop.loopback}}"
              }
            }
            # No loop metadata in this node
          }
        ],
        connections: %{
          "start" => %{
            "main" => [%Connection{from: "start", from_port: "main", to: "regular_node", to_port: "main"}]
          }
        },
        variables: %{}
      }

      {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "start")
      
      context = %{
        workflow_loader: fn _id -> {:error, "not implemented"} end,
        variables: %{}
      }

      {:ok, execution, _} = GraphExecutor.execute_workflow(execution_graph, context)

      assert execution.status == "completed"

      # Check regular_node got default loop metadata
      regular_executions = Map.get(execution.node_executions, "regular_node", [])
      assert length(regular_executions) == 1
      
      regular_execution = List.first(regular_executions)
      assert regular_execution.output_data["loop_level"] == 0
      assert regular_execution.output_data["loop_role"] == "not_in_loop" 
      assert regular_execution.output_data["loop_ids"] == []
      assert regular_execution.output_data["loopback"] == false
    end
  end

  # ============================================================================
  # Template Context Tests
  # ============================================================================

  describe "loopback flag in template context" do
    defp create_template_access_workflow do
      %Workflow{
        id: "template_loopback_test",
        name: "Template Loopback Access Test",
        nodes: [
          %Node{
            key: "start",
            name: "Start", 
            type: "manual.trigger",
            params: %{}
          },

          %Node{
            key: "template_test",
            name: "Template Test",
            type: "data.set_data",
            params: %{
              "mapping_map" => %{
                # Use template to access loopback flag
                "is_loopback" => "{{$execution.loopback}}",
                "run_count" => "{{$execution.run_index}}"
              }
            }
          },

          %Node{
            key: "condition",
            name: "Condition",
            type: "logic.if_condition", 
            params: %{
              "condition" => "{{$execution.run_index < 1}}"
            }
          },

          %Node{
            key: "complete",
            name: "Complete",
            type: "data.set_data",
            params: %{"done" => true}
          }
        ],
        connections: [
          %Connection{from: "start", from_port: "main", to: "template_test", to_port: "main"},
          %Connection{from: "template_test", from_port: "main", to: "condition", to_port: "main"},
          # Loop back
          %Connection{from: "condition", from_port: "true", to: "template_test", to_port: "main"},
          # Exit
          %Connection{from: "condition", from_port: "false", to: "complete", to_port: "main"}
        ],
        variables: %{}
      }
    end

    test "template can access loopback flag correctly" do
      workflow = convert_connections_to_map(create_template_access_workflow())

      {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "start")

      context = %{
        workflow_loader: fn _id -> {:error, "not implemented"} end,
        variables: %{}
      }

      {:ok, execution, _} = GraphExecutor.execute_workflow(execution_graph, context)

      assert execution.status == "completed"

      # Get template_test executions
      template_executions = Map.get(execution.node_executions, "template_test", [])
      assert length(template_executions) == 2

      sorted_executions = Enum.sort_by(template_executions, & &1.run_index)

      # First execution - loopback should be false
      first = Enum.at(sorted_executions, 0)
      assert first.output_data["is_loopback"] == false
      assert first.output_data["run_count"] == 0

      # Second execution - loopback should be true  
      second = Enum.at(sorted_executions, 1)
      assert second.output_data["is_loopback"] == true
      assert second.output_data["run_count"] == 1
    end
  end
end