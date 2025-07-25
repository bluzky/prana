defmodule Prana.WorkflowExecution.GraphExecutorSubWorkflowTest do
  use ExUnit.Case, async: false

  alias Prana.Connection
  alias Prana.GraphExecutor
  alias Prana.IntegrationRegistry
  alias Prana.Integrations.Manual
  alias Prana.Node
  alias Prana.Workflow
  alias Prana.WorkflowCompiler
  alias Prana.WorkflowExecution

  # Helper function to convert list-based connections to map-based
  defp convert_connections_to_map(workflow) do
    connections_list = workflow.connections

    # Convert to proper map structure using add_connection
    workflow_with_empty_connections = %{workflow | connections: %{}}

    Enum.reduce(connections_list, workflow_with_empty_connections, fn connection, acc_workflow ->
      {:ok, updated_workflow} = Workflow.add_connection(acc_workflow, connection)
      updated_workflow
    end)
  end

  setup do
    # Start registry and register integrations
    {:ok, registry_pid} = IntegrationRegistry.start_link()

    # Ensure modules are loaded before registration
    Code.ensure_loaded!(Prana.Integrations.Workflow)
    Code.ensure_loaded!(Manual)

    :ok = IntegrationRegistry.register_integration(Prana.Integrations.Workflow)
    :ok = IntegrationRegistry.register_integration(Manual)

    # Track middleware events for testing
    test_pid = self()

    # Store test_pid in process dictionary for TestMiddleware to access
    Process.put(:test_pid, test_pid)

    # Configure middleware to capture events
    Application.put_env(:prana, :middleware, [
      __MODULE__.TestMiddleware
    ])

    on_exit(fn ->
      if Process.alive?(registry_pid) do
        GenServer.stop(registry_pid)
      end
    end)

    :ok
  end

  describe "execute_graph/3 with sub-workflow suspension" do
    test "suspends workflow execution for synchronous sub-workflow" do
      # Create workflow: trigger -> sub_workflow -> output
      workflow = %Workflow{
        id: "parent_workflow",
        name: "Parent Workflow",
        nodes: [
          %Node{
            key: "trigger",
            type: "manual.trigger"
          },
          %Node{
            key: "sub_workflow_node",
            type: "workflow.execute_workflow",
            params: %{
              "workflow_id" => "child_workflow",
              "execution_mode" => "sync",
              "timeout_ms" => 300_000
            }
          },
          %Node{
            key: "output",
            type: "manual.process_adult",
            params: %{"data" => "$input"}
          }
        ],
        connections: [
          %Connection{
            from: "trigger",
            to: "sub_workflow_node",
            from_port: "main",
            to_port: "main"
          },
          %Connection{
            from: "sub_workflow_node",
            to: "output",
            from_port: "main",
            to_port: "main"
          }
        ]
      }

      # Compile workflow
      {:ok, execution_graph} = WorkflowCompiler.compile(convert_connections_to_map(workflow), "trigger")

      # Execute workflow
      result = GraphExecutor.execute_workflow(execution_graph, %{})

      # Should suspend at sub-workflow node
      assert {:suspend, suspended_execution, _} = result

      # Verify suspended execution state
      assert suspended_execution.status == "suspended"
      assert suspended_execution.workflow_id == "parent_workflow"
      assert suspended_execution.suspended_node_id == "sub_workflow_node"

      # Verify node executions - trigger should be completed, sub_workflow suspended
      all_executions = suspended_execution.node_executions |> Map.values() |> List.flatten()
      completed_nodes = Enum.filter(all_executions, &(&1.status == "completed"))
      suspended_nodes = Enum.filter(all_executions, &(&1.status == "suspended"))

      assert length(completed_nodes) == 1
      assert length(suspended_nodes) == 1

      trigger_execution = Enum.find(completed_nodes, &(&1.node_key == "trigger"))
      sub_execution = Enum.find(suspended_nodes, &(&1.node_key == "sub_workflow_node"))

      assert trigger_execution.status == "completed"
      assert sub_execution.status == "suspended"

      # Verify suspension data contains synchronous sub-workflow data
      assert sub_execution.suspension_type == :sub_workflow_sync
      assert sub_execution.suspension_data.workflow_id == "child_workflow"
      assert sub_execution.suspension_data.execution_mode == "sync"

      # Verify middleware events were emitted
      assert_receive {:middleware_event, :execution_started, _}
      assert_receive {:middleware_event, :node_starting, %{node: %{key: "trigger"}}}
      assert_receive {:middleware_event, :node_completed, %{node: %{key: "trigger"}}}
      assert_receive {:middleware_event, :node_starting, %{node: %{key: "sub_workflow_node"}}}
      assert_receive {:middleware_event, :node_suspended, %{node: %{key: "sub_workflow_node"}}}
      assert_receive {:middleware_event, :execution_suspended, _}
    end

    test "suspends for fire-and-forget sub-workflow (caller handles immediate resume)" do
      # Create simple workflow: trigger -> fire_and_forget_sub -> output
      workflow = %Workflow{
        id: "fire_forget_workflow",
        name: "Fire and Forget Workflow",
        nodes: [
          %Node{
            key: "trigger",
            type: "manual.trigger"
          },
          %Node{
            key: "fire_forget_sub",
            type: "workflow.execute_workflow",
            params: %{
              "workflow_id" => "background_task",
              "execution_mode" => "fire_and_forget"
            }
          },
          %Node{
            key: "output",
            type: "manual.process_adult",
            params: %{"data" => "$input"}
          }
        ],
        connections: [
          %Connection{
            from: "trigger",
            to: "fire_forget_sub",
            from_port: "main",
            to_port: "main"
          },
          %Connection{
            from: "fire_forget_sub",
            to: "output",
            from_port: "main",
            to_port: "main"
          }
        ]
      }

      # Compile and execute
      {:ok, execution_graph} = WorkflowCompiler.compile(convert_connections_to_map(workflow), "trigger")

      result = GraphExecutor.execute_workflow(execution_graph, %{})

      # Should suspend at fire-and-forget node (caller-driven pattern)
      assert {:suspend, suspended_execution, _} = result

      # Verify suspended execution state
      assert suspended_execution.status == "suspended"
      assert suspended_execution.workflow_id == "fire_forget_workflow"
      assert suspended_execution.suspended_node_id == "fire_forget_sub"

      # Verify node executions - trigger completed, fire_forget_sub suspended
      all_executions = suspended_execution.node_executions |> Map.values() |> List.flatten()
      completed_nodes = Enum.filter(all_executions, &(&1.status == "completed"))
      suspended_nodes = Enum.filter(all_executions, &(&1.status == "suspended"))

      assert length(completed_nodes) == 1
      assert length(suspended_nodes) == 1

      trigger_execution = Enum.find(completed_nodes, &(&1.node_key == "trigger"))
      fire_forget_execution = Enum.find(suspended_nodes, &(&1.node_key == "fire_forget_sub"))

      assert trigger_execution.status == "completed"
      assert fire_forget_execution.status == "suspended"

      # Verify suspension data contains fire-and-forget data
      assert fire_forget_execution.suspension_type == :sub_workflow_fire_forget
      assert fire_forget_execution.suspension_data.workflow_id == "background_task"
      assert fire_forget_execution.suspension_data.execution_mode == "fire_and_forget"

      # Simulate caller handling fire-and-forget: trigger child async + immediate resume
      resume_data = %{workflow_id: "background_task"}
      execution_context = build_resume_context(suspended_execution, resume_data)

      resume_result =
        GraphExecutor.resume_workflow(
          suspended_execution,
          resume_data,
          %{env: execution_context}
        )

      # Should complete after immediate resume
      assert {:ok, completed_execution, _} = resume_result
      assert completed_execution.status == "completed"

      # All nodes should be completed
      assert completed_execution.node_executions |> Map.values() |> List.flatten() |> length() == 3

      # Verify fire-and-forget node completed with triggered status
      all_completed_executions = completed_execution.node_executions |> Map.values() |> List.flatten()
      fire_forget_completed = Enum.find(all_completed_executions, &(&1.node_key == "fire_forget_sub"))
      assert fire_forget_completed.status == "completed"
    end
  end

  describe "resume_workflow/4" do
    test "resumes suspended workflow with sub-workflow results" do
      # Create and suspend a workflow first
      workflow = convert_connections_to_map(create_simple_sub_workflow())
      {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "trigger")

      # Execute until suspension
      {:suspend, suspended_execution, _} =
        GraphExecutor.execute_workflow(execution_graph, %{"user_id" => 456})

      # Resume with sub-workflow results
      resume_data = %{
        "output" => %{"processed_user_id" => 456, "status" => "completed"},
        "execution_time_ms" => 2500
      }

      execution_context = build_resume_context(suspended_execution, resume_data)

      result =
        GraphExecutor.resume_workflow(
          suspended_execution,
          resume_data,
          %{env: execution_context}
        )

      # Should complete successfully
      assert {:ok, completed_execution, _} = result

      # Verify completion
      assert completed_execution.status == "completed"

      # Verify all nodes executed
      assert completed_execution.node_executions |> Map.values() |> List.flatten() |> length() == 3

      # Verify output node received sub-workflow results
      all_completed_executions = completed_execution.node_executions |> Map.values() |> List.flatten()
      output_execution = Enum.find(all_completed_executions, &(&1.node_key == "output"))
      assert output_execution.status == "completed"
    end

    test "handles resume with nested suspension" do
      # Test case where resumed workflow triggers another suspension
      workflow = convert_connections_to_map(create_nested_sub_workflow())
      {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "trigger")

      # Execute until first suspension
      {:suspend, first_suspended, _} =
        GraphExecutor.execute_workflow(
          execution_graph,
          %{"stage" => 1}
        )

      # Resume first suspension
      first_resume_data = %{"stage_1_result" => "completed"}
      execution_context = build_resume_context(first_suspended, first_resume_data)

      result =
        GraphExecutor.resume_workflow(
          first_suspended,
          first_resume_data,
          %{env: execution_context}
        )

      # Should suspend again at second sub-workflow
      assert {:suspend, second_suspended, _} = result

      # Verify we're suspended at the second node
      assert second_suspended.suspended_node_id == "second_sub_workflow"

      # Resume second suspension
      second_resume_data = %{"stage_2_result" => "completed"}
      second_context = build_resume_context(second_suspended, second_resume_data)

      final_result =
        GraphExecutor.resume_workflow(
          second_suspended,
          second_resume_data,
          %{env: second_context}
        )

      # Should complete after second resume
      assert {:ok, final_execution, _} = final_result
      assert final_execution.status == "completed"
    end

    test "returns error for invalid execution status" do
      # Try to resume a completed execution
      completed_execution = %WorkflowExecution{
        id: "test",
        workflow_id: "test",
        status: "completed",
        node_executions: []
      }

      result =
        GraphExecutor.resume_workflow(
          completed_execution,
          %{},
          %{}
        )

      assert {:error, error_data} = result
      assert error_data.code == "invalid_execution_status"
      assert error_data.message == "Can only resume suspended executions"
      assert error_data.details["status"] == "completed"
    end

    test "returns error for invalid suspended execution" do
      # Create suspended execution without proper suspended_node_id
      invalid_suspended = %WorkflowExecution{
        id: "test",
        workflow_id: "test",
        workflow_version: 1,
        execution_graph: %Prana.ExecutionGraph{
          workflow_id: "test",
          trigger_node_key: "trigger",
          dependency_graph: %{},
          connection_map: %{},
          reverse_connection_map: %{},
          node_map: %{},
          variables: %{}
        },
        parent_execution_id: nil,
        execution_mode: :async,
        status: "suspended",
        trigger_type: "manual",
        trigger_data: %{},
        vars: %{},
        node_executions: %{},
        current_execution_index: 0,
        # Missing suspended_node_id which makes it invalid
        suspended_node_id: nil,
        suspension_type: nil,
        suspension_data: nil,
        suspended_at: nil,
        started_at: nil,
        completed_at: nil,
        metadata: %{}
      }

      result =
        GraphExecutor.resume_workflow(
          invalid_suspended,
          %{},
          %{}
        )

      assert {:error, error_data} = result
      assert error_data.code == "invalid_suspended_execution"
      assert error_data.message == "Cannot find suspended node ID"
    end
  end

  describe "middleware integration" do
    test "emits correct middleware events for sub-workflow coordination" do
      workflow = convert_connections_to_map(create_simple_sub_workflow())
      {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "trigger")

      # Execute until suspension
      {:suspend, _suspended, _} =
        GraphExecutor.execute_workflow(
          execution_graph,
          %{"user_id" => 789}
        )

      # Verify middleware event sequence
      assert_receive {:middleware_event, :execution_started, event_data}
      assert event_data.execution.workflow_id == "simple_sub_workflow"

      assert_receive {:middleware_event, :node_starting, event_data}
      assert event_data.node.key == "trigger"

      assert_receive {:middleware_event, :node_completed, event_data}
      assert event_data.node.key == "trigger"

      assert_receive {:middleware_event, :node_starting, event_data}
      assert event_data.node.key == "sub_workflow_node"

      assert_receive {:middleware_event, :node_suspended, event_data}
      assert event_data.node.key == "sub_workflow_node"
      assert event_data.suspension_type == :sub_workflow_sync
      assert event_data.suspension_data.workflow_id == "child_workflow"

      assert_receive {:middleware_event, :execution_suspended, event_data}
      assert event_data.execution.status == "suspended"
      assert event_data.suspended_node.key == "sub_workflow_node"
    end
  end

  # Helper functions

  defp create_simple_sub_workflow do
    %Workflow{
      id: "simple_sub_workflow",
      name: "Simple Sub-workflow Test",
      nodes: [
        %Node{
          key: "trigger",
          type: "manual.trigger"
        },
        %Node{
          key: "sub_workflow_node",
          type: "workflow.execute_workflow",
          params: %{
            "workflow_id" => "child_workflow",
            "execution_mode" => "sync"
          }
        },
        %Node{
          key: "output",
          type: "manual.process_adult"
        }
      ],
      connections: [
        %Connection{
          from: "trigger",
          to: "sub_workflow_node",
          from_port: "main",
          to_port: "input"
        },
        %Connection{
          from: "sub_workflow_node",
          to: "output",
          from_port: "main",
          to_port: "input"
        }
      ]
    }
  end

  defp create_nested_sub_workflow do
    %Workflow{
      id: "nested_sub_workflow",
      name: "Nested Sub-workflow Test",
      nodes: [
        %Node{
          key: "trigger",
          type: "manual.trigger"
        },
        %Node{
          key: "first_sub_workflow",
          type: "workflow.execute_workflow",
          params: %{
            "workflow_id" => "stage_1_workflow",
            "execution_mode" => "sync"
          }
        },
        %Node{
          key: "second_sub_workflow",
          type: "workflow.execute_workflow",
          params: %{
            "workflow_id" => "stage_2_workflow",
            "execution_mode" => "sync"
          }
        },
        %Node{
          key: "output",
          type: "manual.process_adult"
        }
      ],
      connections: [
        %Connection{from: "trigger", to: "first_sub_workflow", from_port: "main", to_port: "input"},
        %Connection{from: "first_sub_workflow", to: "second_sub_workflow", from_port: "main", to_port: "input"},
        %Connection{from: "second_sub_workflow", to: "output", from_port: "main", to_port: "input"}
      ]
    }
  end

  defp build_resume_context(suspended_execution, resume_data) do
    executed_nodes = suspended_execution.node_executions |> Map.values() |> List.flatten() |> Enum.map(& &1.node_key)

    # Find suspended node and add resume data
    suspended_node_id = suspended_execution.suspended_node_id

    all_executions = suspended_execution.node_executions |> Map.values() |> List.flatten()

    nodes =
      Enum.reduce(all_executions, %{}, fn node_exec, acc ->
        if node_exec.node_key == suspended_node_id do
          Map.put(acc, node_exec.node_key, resume_data)
        else
          Map.put(acc, node_exec.node_key, node_exec.output_data || %{})
        end
      end)

    # Build active paths from completed nodes - this is critical for resume to work
    active_paths = %{
      "trigger_success" => true,
      "#{suspended_node_id}_success" => true
    }

    %{
      "input" => %{},
      "nodes" => nodes,
      "variables" => %{},
      "executed_nodes" => executed_nodes,
      "active_paths" => active_paths
    }
  end

  # Test middleware module
  defmodule TestMiddleware do
    @moduledoc false
    @behaviour Prana.Behaviour.Middleware

    def call(event, data, next) do
      test_pid = Process.get(:test_pid)

      if test_pid do
        send(test_pid, {:middleware_event, event, data})
      end

      next.(data)
    end
  end
end
