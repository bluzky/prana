defmodule Prana.Execution.SimpleLoopTest do
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
  alias Prana.Execution
  alias Prana.ExecutionGraph
  alias Prana.GraphExecutor
  alias Prana.Integrations.Logic
  alias Prana.Integrations.Manual
  alias Prana.Node
  alias Prana.Workflow
  alias Prana.WorkflowCompiler

  # ============================================================================
  # Setup and Helpers
  # ============================================================================

  setup do
    # Start integration registry for each test
    Code.ensure_loaded(Prana.Integrations.Logic)
    Code.ensure_loaded(Prana.Integrations.Manual)
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
      description: "Test simple counter-based loop using Logic integration",
      nodes: [
        # Start/trigger node
        %Node{
          id: "start",
          custom_id: "start",
          name: "Start",
          integration_name: "manual",
          action_name: "trigger",
          params: %{},
          output_ports: ["success"],
          input_ports: [],
          error_handling: %Prana.ErrorHandling{},
          retry_policy: nil,
          timeout_seconds: nil,
          metadata: %{}
        },

        # Initialize counter
        %Node{
          id: "init_counter",
          custom_id: "init_counter",
          name: "Initialize Counter",
          integration_name: "manual",
          action_name: "set_data",
          params: %{"counter" => 0, "max_count" => 3},
          output_ports: ["success"],
          input_ports: ["input"],
          error_handling: %Prana.ErrorHandling{},
          retry_policy: nil,
          timeout_seconds: nil,
          metadata: %{}
        },

        # Loop body - increment counter
        %Node{
          id: "increment",
          custom_id: "increment",
          name: "Increment Counter",
          integration_name: "manual",
          action_name: "increment_counter",
          params: %{},
          output_ports: ["success"],
          input_ports: ["input"],
          error_handling: %Prana.ErrorHandling{},
          retry_policy: nil,
          timeout_seconds: nil,
          metadata: %{}
        },

        # Loop condition - check if counter < max_count
        %Node{
          id: "loop_condition",
          custom_id: "loop_condition",
          name: "Loop Condition",
          integration_name: "logic",
          action_name: "if_condition",
          params: %{
            "condition" => "$input.continue_loop"
          },
          output_ports: ["true", "false"],
          input_ports: ["input"],
          error_handling: %Prana.ErrorHandling{},
          retry_policy: nil,
          timeout_seconds: nil,
          metadata: %{}
        },

        # Final result node
        %Node{
          id: "complete",
          custom_id: "complete",
          name: "Complete",
          integration_name: "manual",
          action_name: "set_data",
          params: %{"result" => "loop_completed"},
          output_ports: ["success"],
          input_ports: ["input"],
          error_handling: %Prana.ErrorHandling{},
          retry_policy: nil,
          timeout_seconds: nil,
          metadata: %{}
        }
      ],
      connections: [
        # Start -> Initialize Counter
        %Connection{
          from: "start",
          from_port: "success",
          to: "init_counter",
          to_port: "input",
          metadata: %{}
        },

        # Initialize Counter -> Increment (first iteration)
        %Connection{
          from: "init_counter",
          from_port: "success",
          to: "increment",
          to_port: "input",
          metadata: %{}
        },

        # Increment -> Loop Condition
        %Connection{
          from: "increment",
          from_port: "success",
          to: "loop_condition",
          to_port: "input",
          metadata: %{}
        },

        # Loop Condition -> Increment (loop back - true branch)
        %Connection{
          from: "loop_condition",
          from_port: "true",
          to: "increment",
          to_port: "input",
          metadata: %{}
        },

        # Loop Condition -> Complete (exit loop - false branch)
        %Connection{
          from: "loop_condition",
          from_port: "false",
          to: "complete",
          to_port: "input",
          metadata: %{}
        }
      ],
      variables: %{},
      settings: %Prana.WorkflowSettings{},
      metadata: %{}
    }
  end

  defp create_retry_loop_workflow do
    %Workflow{
      id: "retry_loop_test",
      name: "Retry Loop Test Workflow",
      description: "Test retry pattern using Logic integration",
      nodes: [
        # Start/trigger node
        %Node{
          id: "start",
          custom_id: "start",
          name: "Start",
          integration_name: "manual",
          action_name: "trigger",
          params: %{},
          output_ports: ["success"],
          input_ports: [],
          error_handling: %Prana.ErrorHandling{},
          retry_policy: nil,
          timeout_seconds: nil,
          metadata: %{}
        },

        # Initialize retry state
        %Node{
          id: "init_retry",
          custom_id: "init_retry",
          name: "Initialize Retry",
          integration_name: "manual",
          action_name: "set_data",
          params: %{"retry_count" => 0, "max_retries" => 3, "success" => false},
          output_ports: ["success"],
          input_ports: ["input"],
          error_handling: %Prana.ErrorHandling{},
          retry_policy: nil,
          timeout_seconds: nil,
          metadata: %{}
        },

        # Attempt operation (simulated to fail first 2 times)
        %Node{
          id: "attempt_operation",
          custom_id: "attempt_operation",
          name: "Attempt Operation",
          integration_name: "manual",
          action_name: "attempt_operation",
          params: %{},
          output_ports: ["success"],
          input_ports: ["input"],
          error_handling: %Prana.ErrorHandling{},
          retry_policy: nil,
          timeout_seconds: nil,
          metadata: %{}
        },

        # Check if retry needed
        %Node{
          id: "retry_check",
          custom_id: "retry_check",
          name: "Retry Check",
          integration_name: "logic",
          action_name: "if_condition",
          params: %{
            "condition" => "$input.should_retry"
          },
          output_ports: ["true", "false"],
          input_ports: ["input"],
          error_handling: %Prana.ErrorHandling{},
          retry_policy: nil,
          timeout_seconds: nil,
          metadata: %{}
        },

        # Increment retry counter
        %Node{
          id: "increment_retry",
          custom_id: "increment_retry",
          name: "Increment Retry",
          integration_name: "manual",
          action_name: "increment_retry",
          params: %{},
          output_ports: ["success"],
          input_ports: ["input"],
          error_handling: %Prana.ErrorHandling{},
          retry_policy: nil,
          timeout_seconds: nil,
          metadata: %{}
        },

        # Complete (success or failure)
        %Node{
          id: "complete",
          custom_id: "complete",
          name: "Complete",
          integration_name: "manual",
          action_name: "set_data",
          params: %{"result" => "operation_completed"},
          output_ports: ["success"],
          input_ports: ["input"],
          error_handling: %Prana.ErrorHandling{},
          retry_policy: nil,
          timeout_seconds: nil,
          metadata: %{}
        }
      ],
      connections: [
        # Start -> Initialize Retry
        %Connection{
          from: "start",
          from_port: "success",
          to: "init_retry",
          to_port: "input",
          metadata: %{}
        },

        # Initialize Retry -> Attempt Operation (first iteration)
        %Connection{
          from: "init_retry",
          from_port: "success",
          to: "attempt_operation",
          to_port: "input",
          metadata: %{}
        },

        # Attempt Operation -> Retry Check
        %Connection{
          from: "attempt_operation",
          from_port: "success",
          to: "retry_check",
          to_port: "input",
          metadata: %{}
        },

        # Retry Check -> Increment Retry (retry needed - true branch)
        %Connection{
          from: "retry_check",
          from_port: "true",
          to: "increment_retry",
          to_port: "input",
          metadata: %{}
        },

        # Increment Retry -> Attempt Operation (loop back)
        %Connection{
          from: "increment_retry",
          from_port: "success",
          to: "attempt_operation",
          to_port: "input",
          metadata: %{}
        },

        # Retry Check -> Complete (no retry needed - false branch)
        %Connection{
          from: "retry_check",
          from_port: "false",
          to: "complete",
          to_port: "input",
          metadata: %{}
        }
      ],
      variables: %{},
      settings: %Prana.WorkflowSettings{},
      metadata: %{}
    }
  end

  # ============================================================================
  # Test Cases
  # ============================================================================

  describe "simple counter loop" do
    test "executes counter-based loop correctly" do
      workflow = create_simple_counter_loop_workflow()

      # Compile workflow into execution graph
      {:ok, execution_graph} = WorkflowCompiler.compile(workflow)

      # Create execution context
      context = %{
        workflow_loader: fn _id -> {:error, "not implemented"} end,
        variables: %{},
        metadata: %{}
      }

      # Execute the workflow
      {:ok, execution} = GraphExecutor.execute_graph(execution_graph, context)

      # Verify execution completed successfully
      assert execution.status == :completed

      # Verify that multiple iterations occurred
      # The increment node should have been executed multiple times
      increment_executions =
        Enum.count(execution.node_executions, &(&1.node_id == "increment"))

      # Should have 3 iterations (counter: 0 -> 1 -> 2 -> 3, then exit)
      assert increment_executions == 3

      # Verify the final complete node was executed
      complete_executions =
        Enum.count(execution.node_executions, &(&1.node_id == "complete"))

      assert complete_executions == 1
    end
  end

  describe "simple retry loop" do
    test "executes retry pattern correctly" do
      workflow = create_retry_loop_workflow()

      # Compile workflow into execution graph
      {:ok, execution_graph} = WorkflowCompiler.compile(workflow)

      # Create execution context
      context = %{
        workflow_loader: fn _id -> {:error, "not implemented"} end,
        variables: %{},
        metadata: %{}
      }

      # Execute the workflow
      {:ok, execution} = GraphExecutor.execute_graph(execution_graph, context)

      # Verify execution completed successfully
      assert execution.status == :completed

      # Verify that retry attempts occurred
      # The attempt_operation node should have been executed multiple times
      attempt_executions =
        Enum.count(execution.node_executions, &(&1.node_id == "attempt_operation"))

      # Should have multiple attempts based on the retry logic
      assert attempt_executions > 1

      # Verify the final complete node was executed
      complete_executions =
        Enum.count(execution.node_executions, &(&1.node_id == "complete"))

      assert complete_executions == 1
    end
  end

  describe "loop termination" do
    test "prevents infinite loops with proper condition design" do
      workflow = create_simple_counter_loop_workflow()

      # Compile workflow into execution graph
      {:ok, execution_graph} = WorkflowCompiler.compile(workflow)

      # Create execution context
      context = %{
        workflow_loader: fn _id -> {:error, "not implemented"} end,
        variables: %{},
        metadata: %{}
      }

      # Execute the workflow with a timeout to prevent infinite loops
      task =
        Task.async(fn ->
          GraphExecutor.execute_graph(execution_graph, context)
        end)

      # Should complete within reasonable time (5 seconds)
      result = Task.await(task, 5000)

      assert {:ok, execution} = result
      assert execution.status == :completed

      # Total node executions should be reasonable (not infinite)
      total_executions = length(execution.node_executions)
      # Should be much less for a 3-iteration loop
      assert total_executions < 20
    end
  end
end
