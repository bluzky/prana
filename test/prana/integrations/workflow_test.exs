defmodule Prana.Integrations.WorkflowTest do
  use ExUnit.Case, async: true

  alias Prana.Integrations.Workflow

  describe "definition/0" do
    test "returns integration definition with workflow actions" do
      definition = Workflow.definition()

      assert definition.name == "workflow"
      assert definition.display_name == "Workflow"
      assert definition.description == "Sub-workflow orchestration and coordination operations"
      assert definition.version == "1.0.0"
      assert definition.category == "coordination"
      assert Map.has_key?(definition.actions, "execute_workflow")

      execute_action = definition.actions["execute_workflow"]
      assert execute_action.name == "execute_workflow"
      assert execute_action.display_name == "Execute Sub-workflow"
      assert execute_action.module == Workflow
      assert execute_action.function == :execute_workflow
      assert execute_action.input_ports == ["input"]
      assert execute_action.output_ports == ["success", "error", "timeout"]
      assert execute_action.default_success_port == "success"
      assert execute_action.default_error_port == "error"
    end
  end

  describe "execute_workflow/1" do
    test "returns suspension for synchronous execution with valid parameters" do
      input_map = %{
        "workflow_id" => "user_onboarding",
        "input_data" => %{"user_id" => 123},
        "execution_mode" => "sync",
        "timeout_ms" => 300_000,
        "failure_strategy" => "fail_parent"
      }

      result = Workflow.execute_workflow(input_map)

      assert {:suspend, :sub_workflow_sync, suspend_data} = result
      assert suspend_data.workflow_id == "user_onboarding"
      assert suspend_data.input_data == %{"user_id" => 123}
      assert suspend_data.execution_mode == "sync"
      assert suspend_data.timeout_ms == 300_000
      assert suspend_data.failure_strategy == "fail_parent"
      assert %DateTime{} = suspend_data.triggered_at
    end

    test "returns suspension for fire-and-forget execution" do
      input_map = %{
        "workflow_id" => "notification_flow",
        "input_data" => %{"message" => "hello"},
        "execution_mode" => "fire_and_forget",
        "timeout_ms" => 60_000
      }

      result = Workflow.execute_workflow(input_map)

      assert {:suspend, :sub_workflow_fire_forget, suspend_data} = result
      assert suspend_data.workflow_id == "notification_flow"
      assert suspend_data.input_data == %{"message" => "hello"}
      assert suspend_data.execution_mode == "fire_and_forget"
      assert suspend_data.timeout_ms == 60_000
    end

    test "returns suspension for asynchronous execution" do
      input_map = %{
        "workflow_id" => "user_processing",
        "input_data" => %{"user_id" => 789},
        "execution_mode" => "async",
        "timeout_ms" => 600_000,
        "failure_strategy" => "continue"
      }

      result = Workflow.execute_workflow(input_map)

      assert {:suspend, :sub_workflow_async, suspend_data} = result
      assert suspend_data.workflow_id == "user_processing"
      assert suspend_data.input_data == %{"user_id" => 789}
      assert suspend_data.execution_mode == "async"
      assert suspend_data.timeout_ms == 600_000
      assert suspend_data.failure_strategy == "continue"
      assert %DateTime{} = suspend_data.triggered_at
    end

    test "uses default values for optional parameters" do
      input_map = %{
        "workflow_id" => "simple_flow"
      }

      result = Workflow.execute_workflow(input_map)

      assert {:suspend, :sub_workflow_sync, suspend_data} = result
      assert suspend_data.workflow_id == "simple_flow"
      assert suspend_data.input_data == input_map  # defaults to full input
      assert suspend_data.execution_mode == "sync"  # default
      assert suspend_data.timeout_ms == 300_000  # default 5 minutes
      assert suspend_data.failure_strategy == "fail_parent"  # default
    end

    test "returns error for missing workflow_id" do
      input_map = %{"input_data" => %{"test" => true}}

      result = Workflow.execute_workflow(input_map)

      assert {:error, error_data, "error"} = result
      assert error_data.type == "sub_workflow_setup_error"
      assert error_data.message == "workflow_id is required"
    end

    test "returns error for empty workflow_id" do
      input_map = %{"workflow_id" => ""}

      result = Workflow.execute_workflow(input_map)

      assert {:error, error_data, "error"} = result
      assert error_data.type == "sub_workflow_setup_error"
      assert error_data.message == "workflow_id cannot be empty"
    end

    test "returns error for non-string workflow_id" do
      input_map = %{"workflow_id" => 123}

      result = Workflow.execute_workflow(input_map)

      assert {:error, error_data, "error"} = result
      assert error_data.type == "sub_workflow_setup_error"
      assert error_data.message == "workflow_id must be a string"
    end

    test "returns error for non-map input_data" do
      input_map = %{
        "workflow_id" => "test_flow",
        "input_data" => "invalid_data"
      }

      result = Workflow.execute_workflow(input_map)

      assert {:error, error_data, "error"} = result
      assert error_data.type == "sub_workflow_setup_error"
      assert error_data.message == "input_data must be a map"
    end

    test "returns error for invalid execution_mode" do
      input_map = %{
        "workflow_id" => "test_flow",
        "execution_mode" => "invalid_mode"
      }

      result = Workflow.execute_workflow(input_map)

      assert {:error, error_data, "error"} = result
      assert error_data.type == "sub_workflow_setup_error"
      assert error_data.message == "execution_mode must be 'sync', 'async', or 'fire_and_forget'"
    end

    test "returns error for invalid timeout_ms" do
      input_map = %{
        "workflow_id" => "test_flow",
        "timeout_ms" => -1000
      }

      result = Workflow.execute_workflow(input_map)

      assert {:error, error_data, "error"} = result
      assert error_data.type == "sub_workflow_setup_error"
      assert error_data.message == "timeout_ms must be a positive integer"
    end

    test "returns error for invalid failure_strategy" do
      input_map = %{
        "workflow_id" => "test_flow",
        "failure_strategy" => "invalid_strategy"
      }

      result = Workflow.execute_workflow(input_map)

      assert {:error, error_data, "error"} = result
      assert error_data.type == "sub_workflow_setup_error"
      assert error_data.message == "failure_strategy must be 'fail_parent' or 'continue'"
    end

    test "accepts 'continue' failure_strategy" do
      input_map = %{
        "workflow_id" => "test_flow",
        "failure_strategy" => "continue"
      }

      result = Workflow.execute_workflow(input_map)

      assert {:suspend, :sub_workflow_sync, suspend_data} = result
      assert suspend_data.failure_strategy == "continue"
    end

    test "handles complex input_data structures" do
      complex_input = %{
        "user" => %{
          "id" => 123,
          "profile" => %{"name" => "John", "age" => 30},
          "preferences" => ["email", "sms"]
        },
        "metadata" => %{"source" => "api", "timestamp" => "2024-01-01T00:00:00Z"}
      }

      input_map = %{
        "workflow_id" => "complex_flow",
        "input_data" => complex_input
      }

      result = Workflow.execute_workflow(input_map)

      assert {:suspend, :sub_workflow_sync, suspend_data} = result
      assert suspend_data.input_data == complex_input
    end

    test "correctly handles different execution modes" do
      # Test sync mode
      input_map = %{
        "workflow_id" => "test_flow",
        "execution_mode" => "sync"
      }

      result = Workflow.execute_workflow(input_map)
      assert {:suspend, :sub_workflow_sync, _} = result

      # Test fire_and_forget mode  
      input_map = %{
        "workflow_id" => "test_flow",
        "execution_mode" => "fire_and_forget"
      }

      result = Workflow.execute_workflow(input_map)
      assert {:suspend, :sub_workflow_fire_forget, _} = result
    end

    test "preserves all configuration in suspend_data for middleware handling" do
      input_map = %{
        "workflow_id" => "detailed_flow",
        "input_data" => %{"config" => "test"},
        "execution_mode" => "sync",
        "timeout_ms" => 120_000,
        "failure_strategy" => "continue"
      }

      result = Workflow.execute_workflow(input_map)

      assert {:suspend, :sub_workflow_sync, suspend_data} = result
      
      # Verify all configuration is preserved for middleware
      assert suspend_data.workflow_id == "detailed_flow"
      assert suspend_data.input_data == %{"config" => "test"}
      assert suspend_data.execution_mode == "sync"
      assert suspend_data.timeout_ms == 120_000
      assert suspend_data.failure_strategy == "continue"
      assert is_struct(suspend_data.triggered_at, DateTime)
    end
  end
end