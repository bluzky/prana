defmodule Prana.WorkflowExecution.SimpleLoopTest do
  @moduledoc """
  Unit tests for simple loop patterns using existing Logic integration

  Tests loop patterns using conditional branching with loop-back connections:
  - Counter-based while loops
  - Condition-based do-while loops
  - Retry patterns with max attempts
  - Integration with existing Logic integration
  """

  use ExUnit.Case, async: false

  alias Prana.Connection
  # alias Prana.WorkflowExecution
  # alias Prana.ExecutionGraph
  alias Prana.GraphExecutor
  alias Prana.Integrations.Data
  alias Prana.Integrations.Logic
  alias Prana.Integrations.Manual
  alias Prana.Integrations.Workflow, as: WorkflowIntegration
  alias Prana.Node
  alias Prana.Workflow
  alias Prana.WorkflowCompiler

  # ============================================================================
  # Setup and Helpers
  # ============================================================================

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
    # Start integration registry for each test
    Code.ensure_loaded(Logic)
    Code.ensure_loaded(Manual)
    Code.ensure_loaded(Data)
    Code.ensure_loaded(WorkflowIntegration)
    {:ok, registry_pid} = Prana.IntegrationRegistry.start_link()

    # Register required integrations with error handling
    case Prana.IntegrationRegistry.register_integration(Logic) do
      :ok ->
        :ok

      {:error, reason} ->
        GenServer.stop(registry_pid)
        raise "Failed to register Logic integration: #{inspect(reason)}"
    end

    case Prana.IntegrationRegistry.register_integration(Manual) do
      :ok ->
        :ok

      {:error, reason} ->
        GenServer.stop(registry_pid)
        raise "Failed to register Manual integration: #{inspect(reason)}"
    end

    case Prana.IntegrationRegistry.register_integration(Data) do
      :ok ->
        :ok

      {:error, reason} ->
        GenServer.stop(registry_pid)
        raise "Failed to register Data integration: #{inspect(reason)}"
    end

    case Prana.IntegrationRegistry.register_integration(WorkflowIntegration) do
      :ok ->
        :ok

      {:error, reason} ->
        GenServer.stop(registry_pid)
        raise "Failed to register Workflow integration: #{inspect(reason)}"
    end

    on_exit(fn ->
      if Process.alive?(registry_pid) do
        GenServer.stop(registry_pid)
      end
    end)

    :ok
  end

  defp create_simple_counter_loop_workflow do
    %Workflow{
      id: "counter_loop_test",
      name: "Counter Loop Test Workflow",
      nodes: [
        # Start/trigger node
        %Node{
          key: "start",
          name: "Start",
          type: "manual.trigger",
          params: %{}
        },

        # Initialize counter
        %Node{
          key: "init_counter",
          name: "Initialize Counter",
          type: "data.set_data",
          params: %{"counter" => 0, "max_count" => 3}
        },

        # Loop body - increment counter using runIndex
        %Node{
          key: "increment",
          name: "Increment Counter",
          type: "data.set_data",
          params: %{
            "counter" => "{{$execution.run_index + 1}}"
          }
        },

        # Loop condition - check if counter < max_count
        %Node{
          key: "loop_condition",
          name: "Loop Condition",
          type: "logic.if_condition",
          params: %{
            "condition" => "{{$execution.run_index < 3}}"
          }
        },

        # Final result node
        %Node{
          key: "complete",
          name: "Complete",
          type: "data.set_data",
          params: %{"result" => "loop_completed"}
        }
      ],
      connections: [
        # Start -> Initialize Counter
        %Connection{
          from: "start",
          from_port: "main",
          to: "init_counter",
          to_port: "main"
        },

        # Initialize Counter -> Increment (first iteration)
        %Connection{
          from: "init_counter",
          from_port: "main",
          to: "increment",
          to_port: "main"
        },

        # Increment -> Loop Condition
        %Connection{
          from: "increment",
          from_port: "main",
          to: "loop_condition",
          to_port: "main"
        },

        # Loop Condition -> Increment (loop back - true branch)
        %Connection{
          from: "loop_condition",
          from_port: "true",
          to: "increment",
          to_port: "main"
        },

        # Loop Condition -> Complete (exit loop - false branch)
        %Connection{
          from: "loop_condition",
          from_port: "false",
          to: "complete",
          to_port: "main"
        }
      ],
      variables: %{}
    }
  end

  # ============================================================================
  # Test Cases
  # ============================================================================

  describe "simple counter loop" do
    test "executes counter-based loop correctly" do
      workflow = convert_connections_to_map(create_simple_counter_loop_workflow())

      # Compile workflow into execution graph
      {:ok, execution_graph} =
        WorkflowCompiler.compile(workflow, "start")

      # Create execution context
      context = %{
        workflow_loader: fn _id -> {:error, "not implemented"} end,
        variables: %{}
      }

      # Execute the workflow
      {:ok, execution} = GraphExecutor.execute_workflow(execution_graph, context)

      # Verify execution completed successfully
      assert execution.status == "completed"

      # Verify that multiple iterations occurred
      # The increment node should have been executed multiple times
      increment_executions =
        length(Map.get(execution.node_executions, "increment", []))

      # Should have 4 iterations (counter: 0 -> 1 -> 2 -> 3, then exit)
      assert increment_executions == 4

      # Verify the final complete node was executed
      complete_executions =
        length(Map.get(execution.node_executions, "complete", []))

      assert complete_executions == 1
    end
  end

  describe "loop termination" do
    test "prevents infinite loops with proper condition design" do
      workflow = convert_connections_to_map(create_simple_counter_loop_workflow())

      # Compile workflow into execution graph
      {:ok, execution_graph} = WorkflowCompiler.compile(workflow, "start")

      # Create execution context
      context = %{
        workflow_loader: fn _id -> {:error, "not implemented"} end,
        variables: %{}
      }

      # Execute the workflow with a timeout to prevent infinite loops
      task =
        Task.async(fn ->
          GraphExecutor.execute_workflow(execution_graph, context)
        end)

      # Should complete within reasonable time (5 seconds)
      result = Task.await(task, 5000)

      assert {:ok, execution} = result
      assert execution.status == "completed"

      # Total node executions should be reasonable (not infinite)
      total_executions = execution.node_executions |> Map.values() |> List.flatten() |> length()
      # Should be much less for a 3-iteration loop
      assert total_executions < 20
    end
  end
end
