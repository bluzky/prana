defmodule PranaDemo.DemoWorkflow do
  @moduledoc """
  Demo workflow examples using the WorkflowRunner with ETS storage.

  This module demonstrates how to create and run workflows using the built-in
  integrations available in Prana.
  """

  alias Prana.Workflow
  alias Prana.Node
  alias Prana.Connection
  alias PranaDemo.WorkflowRunner
  alias PranaDemo.ETSStorage

  require Logger

  @doc """
  Create a simple sequential workflow using manual integration.

  Flow: trigger -> set_data -> process_adult -> end
  """
  def create_simple_workflow do
    # Create workflow
    workflow = Workflow.new("Simple Demo Workflow", "A simple workflow for demonstration")

    # Create nodes
    trigger_node = Node.new("Trigger", "manual", "trigger", %{}, "trigger")

    set_data_node =
      Node.new(
        "Set Data",
        "manual",
        "set_data",
        %{
          "data" => %{
            "user_id" => "$input.user_id",
            "name" => "$input.name",
            "age" => "$input.age"
          }
        },
        "set_data"
      )

    process_node =
      Node.new(
        "Process Adult",
        "manual",
        "process_adult",
        %{
          "user_data" => "$nodes.set_data.data"
        },
        "process_adult"
      )

    # Add nodes to workflow
    {:ok, workflow} = Workflow.add_node(workflow, trigger_node)
    {:ok, workflow} = Workflow.add_node(workflow, set_data_node)
    {:ok, workflow} = Workflow.add_node(workflow, process_node)

    # Create connections
    conn1 = %Connection{
      from: "trigger",
      from_port: "success",
      to: "set_data",
      to_port: "input"
    }

    conn2 = %Connection{
      from: "set_data",
      from_port: "success",
      to: "process_adult",
      to_port: "input"
    }

    # Add connections
    {:ok, workflow} = Workflow.add_connection(workflow, conn1)
    {:ok, workflow} = Workflow.add_connection(workflow, conn2)

    workflow
  end

  @doc """
  Create a conditional workflow using logic integration.

  Flow: trigger -> set_data -> if_condition -> (process_adult OR process_minor)
  """
  def create_conditional_workflow do
    # Create workflow
    workflow =
      Workflow.new("Conditional Demo Workflow", "A conditional workflow for demonstration")

    # Create nodes
    trigger_node = Node.new("Trigger", "manual", "trigger", %{}, "trigger")

    set_data_node =
      Node.new(
        "Set Data",
        "manual",
        "set_data",
        %{
          "data" => %{
            "user_id" => "$input.user_id",
            "name" => "$input.name",
            "age" => "$input.age"
          }
        },
        "set_data"
      )

    condition_node =
      Node.new(
        "Age Check",
        "logic",
        "if_condition",
        %{
          "condition" => "$nodes.set_data.data.age >= 18"
        },
        "age_check"
      )

    process_adult_node =
      Node.new(
        "Process Adult",
        "manual",
        "process_adult",
        %{
          "user_data" => "$nodes.set_data.data"
        },
        "process_adult"
      )

    process_minor_node =
      Node.new(
        "Process Minor",
        "manual",
        "process_minor",
        %{
          "user_data" => "$nodes.set_data.data"
        },
        "process_minor"
      )

    # Add nodes to workflow
    {:ok, workflow} = Workflow.add_node(workflow, trigger_node)
    {:ok, workflow} = Workflow.add_node(workflow, set_data_node)
    {:ok, workflow} = Workflow.add_node(workflow, condition_node)
    {:ok, workflow} = Workflow.add_node(workflow, process_adult_node)
    {:ok, workflow} = Workflow.add_node(workflow, process_minor_node)

    # Create connections
    connections = [
      %Connection{from: "trigger", from_port: "success", to: "set_data", to_port: "input"},
      %Connection{from: "set_data", from_port: "success", to: "age_check", to_port: "input"},
      %Connection{from: "age_check", from_port: "true", to: "process_adult", to_port: "input"},
      %Connection{from: "age_check", from_port: "false", to: "process_minor", to_port: "input"}
    ]

    # Add connections
    workflow =
      Enum.reduce(connections, workflow, fn conn, acc_workflow ->
        {:ok, updated_workflow} = Workflow.add_connection(acc_workflow, conn)
        updated_workflow
      end)

    workflow
  end

  @doc """
  Run a simple workflow demonstration.
  """
  def run_simple_demo do
    Logger.info("Starting simple workflow demo")

    # Start storage
    case WorkflowRunner.start_storage() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    # Create and store workflow
    workflow = create_simple_workflow()
    {:ok, _} = ETSStorage.store_workflow(workflow)

    # Input data
    input_data = %{
      "user_id" => "user123",
      "name" => "John Doe",
      "age" => 25
    }

    # Execute workflow
    case WorkflowRunner.execute_workflow(workflow, input_data, %{}) do
      {:ok, execution} ->
        Logger.info("Workflow completed successfully!")
        Logger.info("Final execution status: #{execution.status}")
        Logger.info("Execution ID: #{execution.id}")
        {:ok, execution}

      {:error, reason} ->
        Logger.error("Workflow failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Run a conditional workflow demonstration.
  """
  def run_conditional_demo do
    Logger.info("Starting conditional workflow demo")

    # Start storage
    case WorkflowRunner.start_storage() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    # Create and store workflow
    workflow = create_conditional_workflow()
    {:ok, _} = ETSStorage.store_workflow(workflow)

    # Test with adult user
    adult_input = %{
      "user_id" => "user123",
      "name" => "John Doe",
      "age" => 25
    }

    Logger.info("Testing with adult user (age 25)")

    case WorkflowRunner.execute_workflow(workflow, adult_input, %{}) do
      {:ok, execution} ->
        Logger.info("Adult workflow completed successfully!")
        Logger.info("Final execution status: #{execution.status}")

      {:error, reason} ->
        Logger.error("Adult workflow failed: #{inspect(reason)}")
    end

    # Test with minor user
    minor_input = %{
      "user_id" => "user456",
      "name" => "Jane Smith",
      "age" => 16
    }

    Logger.info("Testing with minor user (age 16)")

    case WorkflowRunner.execute_workflow(workflow, minor_input, %{}) do
      {:ok, execution} ->
        Logger.info("Minor workflow completed successfully!")
        Logger.info("Final execution status: #{execution.status}")
        {:ok, execution}

      {:error, reason} ->
        Logger.error("Minor workflow failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Create a loop workflow demonstrating retry patterns.

  Flow: trigger -> attempt_operation -> if_condition -> (increment_retry OR process_success)
  """
  def create_loop_workflow do
    # Create workflow
    workflow = Workflow.new("Loop Demo Workflow", "A loop workflow demonstrating retry patterns")

    # Create nodes
    trigger_node = Node.new("Trigger", "manual", "trigger", %{}, "trigger")

    attempt_node =
      Node.new(
        "Attempt Operation",
        "manual",
        "attempt_operation",
        %{
          "max_attempts" => 3,
          "data" => "$input"
        },
        "attempt_operation"
      )

    # Check if retry is needed (attempt_count < max_attempts)
    retry_check_node =
      Node.new(
        "Check Retry",
        "logic",
        "if_condition",
        %{
          "condition" =>
            "$nodes.attempt_operation.attempt_count < $nodes.attempt_operation.max_attempts"
        },
        "retry_check"
      )

    increment_node =
      Node.new(
        "Increment Retry",
        "manual",
        "increment_retry",
        %{
          "attempt_count" => "$nodes.attempt_operation.attempt_count"
        },
        "increment_retry"
      )

    process_success_node =
      Node.new(
        "Process Success",
        "manual",
        "process_adult",
        %{
          "result" => "$nodes.attempt_operation"
        },
        "process_success"
      )

    # Add nodes to workflow
    {:ok, workflow} = Workflow.add_node(workflow, trigger_node)
    {:ok, workflow} = Workflow.add_node(workflow, attempt_node)
    {:ok, workflow} = Workflow.add_node(workflow, retry_check_node)
    {:ok, workflow} = Workflow.add_node(workflow, increment_node)
    {:ok, workflow} = Workflow.add_node(workflow, process_success_node)

    # Create connections for loop pattern
    connections = [
      %Connection{
        from: "trigger",
        from_port: "success",
        to: "attempt_operation",
        to_port: "input"
      },
      %Connection{
        from: "attempt_operation",
        from_port: "success",
        to: "process_success",
        to_port: "input"
      },
      %Connection{
        from: "attempt_operation",
        from_port: "error",
        to: "retry_check",
        to_port: "input"
      },
      %Connection{
        from: "retry_check",
        from_port: "true",
        to: "increment_retry",
        to_port: "input"
      },
      %Connection{
        from: "retry_check",
        from_port: "false",
        to: "process_success",
        to_port: "input"
      },
      %Connection{
        from: "increment_retry",
        from_port: "success",
        to: "attempt_operation",
        to_port: "input"
      }
    ]

    # Add connections
    workflow =
      Enum.reduce(connections, workflow, fn conn, acc_workflow ->
        {:ok, updated_workflow} = Workflow.add_connection(acc_workflow, conn)
        updated_workflow
      end)

    workflow
  end

  @doc """
  Create a sub workflow demo with different execution modes.

  Flow: trigger -> execute_sub_workflow (sync/async/fire_and_forget) -> process_result
  """
  def create_sub_workflow_demo(execution_mode \\ "fire_and_forget") do
    # Create main workflow
    main_workflow =
      Workflow.new(
        "Sub Workflow Demo - #{execution_mode}",
        "Demonstrates sub-workflow execution patterns"
      )

    # Create sub workflow first
    sub_workflow = create_simple_sub_workflow()

    # Create main workflow nodes
    trigger_node = Node.new("Trigger", "manual", "trigger", %{}, "trigger")

    sub_workflow_node =
      Node.new(
        "Execute Sub Workflow",
        "workflow",
        "execute_workflow",
        %{
          "workflow_id" => sub_workflow.id,
          "execution_mode" => execution_mode,
          "input" => %{
            "sub_task" => "process_data",
            "data" => "$input"
          }
        },
        "execute_sub_workflow"
      )

    process_result_node =
      Node.new(
        "Process Result",
        "manual",
        "process_adult",
        %{
          "sub_workflow_result" => "$nodes.execute_sub_workflow"
        },
        "process_result"
      )

    # Add nodes to main workflow
    {:ok, main_workflow} = Workflow.add_node(main_workflow, trigger_node)
    {:ok, main_workflow} = Workflow.add_node(main_workflow, sub_workflow_node)
    {:ok, main_workflow} = Workflow.add_node(main_workflow, process_result_node)

    # Create connections
    connections = [
      %Connection{
        from: "trigger",
        from_port: "success",
        to: "execute_sub_workflow",
        to_port: "input"
      },
      %Connection{
        from: "execute_sub_workflow",
        from_port: "success",
        to: "process_result",
        to_port: "input"
      }
    ]

    # Add connections
    main_workflow =
      Enum.reduce(connections, main_workflow, fn conn, acc_workflow ->
        {:ok, updated_workflow} = Workflow.add_connection(acc_workflow, conn)
        updated_workflow
      end)

    {main_workflow, sub_workflow}
  end

  defp create_simple_sub_workflow do
    # Create a simple sub workflow
    sub_workflow = Workflow.new("Simple Sub Workflow", "A simple sub workflow for demonstration")

    # Create nodes
    trigger_node = Node.new("Sub Trigger", "manual", "trigger", %{}, "sub_trigger")

    process_node =
      Node.new(
        "Sub Process",
        "manual",
        "set_data",
        %{
          "result" => %{
            "sub_task_completed" => true,
            "processed_data" => "$input.data",
            "task_type" => "$input.sub_task"
          }
        },
        "sub_process"
      )

    # Add nodes to sub workflow
    {:ok, sub_workflow} = Workflow.add_node(sub_workflow, trigger_node)
    {:ok, sub_workflow} = Workflow.add_node(sub_workflow, process_node)

    # Create connection
    conn = %Connection{
      from: "sub_trigger",
      from_port: "success",
      to: "sub_process",
      to_port: "input"
    }

    {:ok, sub_workflow} = Workflow.add_connection(sub_workflow, conn)

    sub_workflow
  end

  @doc """
  Create a wait demo workflow with timer patterns.

  Flow: trigger -> set_data -> wait (timer) -> process_after_wait
  """
  def create_wait_demo do
    # Create workflow
    workflow = Workflow.new("Wait Demo Workflow", "Demonstrates wait operations with timers")

    # Create nodes
    trigger_node = Node.new("Trigger", "manual", "trigger", %{}, "trigger")

    set_data_node =
      Node.new(
        "Set Data",
        "manual",
        "set_data",
        %{
          "data" => %{
            "task_id" => "$input.task_id",
            "started_at" => "$input.started_at"
          }
        },
        "set_data"
      )

    wait_node =
      Node.new(
        "Wait Timer",
        "wait",
        "wait",
        %{
          "mode" => "interval",
          # 2 second delay
          "duration" => 2000,
          "unit" => "ms"
        },
        "wait_timer"
      )

    process_after_wait_node =
      Node.new(
        "Process After Wait",
        "manual",
        "process_adult",
        %{
          "original_data" => "$nodes.set_data.data",
          "wait_completed" => true
        },
        "process_after_wait"
      )

    # Add nodes to workflow
    {:ok, workflow} = Workflow.add_node(workflow, trigger_node)
    {:ok, workflow} = Workflow.add_node(workflow, set_data_node)
    {:ok, workflow} = Workflow.add_node(workflow, wait_node)
    {:ok, workflow} = Workflow.add_node(workflow, process_after_wait_node)

    # Create connections
    connections = [
      %Connection{from: "trigger", from_port: "success", to: "set_data", to_port: "input"},
      %Connection{from: "set_data", from_port: "success", to: "wait_timer", to_port: "input"},
      %Connection{
        from: "wait_timer",
        from_port: "success",
        to: "process_after_wait",
        to_port: "input"
      }
    ]

    # Add connections
    workflow =
      Enum.reduce(connections, workflow, fn conn, acc_workflow ->
        {:ok, updated_workflow} = Workflow.add_connection(acc_workflow, conn)
        updated_workflow
      end)

    workflow
  end

  @doc """
  Run a loop workflow demonstration.
  """
  def run_loop_demo do
    Logger.info("Starting loop workflow demo")

    # Start storage
    case WorkflowRunner.start_storage() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    # Create and store workflow
    workflow = create_loop_workflow()
    {:ok, _} = ETSStorage.store_workflow(workflow)

    # Input data
    input_data = %{
      "task_id" => "loop_task_123",
      "data" => "test_data"
    }

    # Execute workflow
    case WorkflowRunner.execute_workflow(workflow, input_data, %{}) do
      {:ok, execution} ->
        Logger.info("Loop workflow completed successfully!")
        Logger.info("Final execution status: #{execution.status}")
        Logger.info("Execution ID: #{execution.id}")
        {:ok, execution}

      {:error, reason} ->
        Logger.error("Loop workflow failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Run a sub workflow demonstration with a specific execution mode.
  """
  def run_sub_workflow_demo(execution_mode \\ "fire_and_forget") do
    Logger.info("Starting sub workflow demo with execution mode: #{execution_mode}")

    # Start storage
    case WorkflowRunner.start_storage() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    # Create and store workflows
    {main_workflow, sub_workflow} = create_sub_workflow_demo(execution_mode)
    {:ok, _} = ETSStorage.store_workflow(main_workflow)
    {:ok, _} = ETSStorage.store_workflow(sub_workflow)

    # Input data
    input_data = %{
      "main_task_id" => "main_task_123",
      "data" => "main_workflow_data"
    }

    # Execute workflow
    case WorkflowRunner.execute_workflow(main_workflow, input_data, %{}) do
      {:ok, execution} when is_struct(execution) ->
        Logger.info("Sub workflow demo (#{execution_mode}) completed successfully!")
        Logger.info("Final execution status: #{execution.status}")
        Logger.info("Execution ID: #{execution.id}")
        {:ok, execution}

      {:ok, :suspended} ->
        Logger.info("Sub workflow demo (#{execution_mode}) suspended successfully!")
        Logger.info("This demonstrates sub-workflow coordination patterns")
        Logger.info("In a real application, the sub-workflow would be executed in the background")
        {:ok, :suspended}

      {:error, {:suspend, execution}} ->
        Logger.info(
          "Sub workflow demo (#{execution_mode}) suspended as expected - GraphExecutor returned suspension!"
        )

        Logger.info("Suspension type: #{execution.suspension_type}")
        Logger.info("Execution mode: #{execution.suspension_data.execution_mode}")
        Logger.info("This demonstrates proper sub-workflow suspension behavior")
        {:ok, :suspended}

      {:error, reason} ->
        Logger.error("Sub workflow demo (#{execution_mode}) failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Run all sub workflow execution modes.
  """
  def run_all_sub_workflow_demos do
    Logger.info("Running all sub workflow execution modes")

    execution_modes = ["sync", "async", "fire_and_forget"]

    results =
      Enum.map(execution_modes, fn mode ->
        Logger.info("\\n=== Testing #{mode} execution mode ===")
        result = run_sub_workflow_demo(mode)
        {mode, result}
      end)

    Logger.info("\\n=== Sub-workflow Demo Results ===")

    Enum.each(results, fn {mode, result} ->
      case result do
        {:ok, _} -> Logger.info("✓ #{mode} mode: SUCCESS")
        {:error, _} -> Logger.error("✗ #{mode} mode: FAILED")
      end
    end)

    results
  end

  @doc """
  Run a wait workflow demonstration.
  """
  def run_wait_demo do
    Logger.info("Starting wait workflow demo")

    # Start storage
    case WorkflowRunner.start_storage() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    # Create and store workflow
    workflow = create_wait_demo()
    {:ok, _} = ETSStorage.store_workflow(workflow)

    # Input data
    input_data = %{
      "task_id" => "wait_task_123",
      "started_at" => DateTime.utc_now()
    }

    # Execute workflow
    Logger.info("Executing workflow with 2 second wait...")
    start_time = System.monotonic_time(:millisecond)

    case WorkflowRunner.execute_workflow(workflow, input_data, %{}) do
      {:ok, execution} ->
        end_time = System.monotonic_time(:millisecond)
        duration = end_time - start_time
        Logger.info("Wait workflow completed successfully!")
        Logger.info("Total execution time: #{duration}ms")
        Logger.info("Final execution status: #{execution.status}")
        Logger.info("Execution ID: #{execution.id}")
        {:ok, execution}

      {:error, reason} ->
        Logger.error("Wait workflow failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Run all demos in sequence.
  """
  def run_all_demos do
    Logger.info("Running all workflow demos")

    results = [
      {"Simple", run_simple_demo()},
      {"Conditional", run_conditional_demo()},
      {"Loop", run_loop_demo()},
      {"Sub Workflow", run_sub_workflow_demo()},
      {"Wait", run_wait_demo()}
    ]

    Logger.info("Demo results:")

    Enum.each(results, fn {name, result} ->
      case result do
        {:ok, _} -> Logger.info("✓ #{name} demo: SUCCESS")
        {:error, _} -> Logger.error("✗ #{name} demo: FAILED")
      end
    end)

    results
  end
end
