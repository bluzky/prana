defmodule Prana.Integrations.Workflow.ExecuteWorkflowActionTest do
  use ExUnit.Case, async: false

  alias Prana.Integrations.Workflow.ExecuteWorkflowAction

  describe "execute/1" do
    test "returns suspension for synchronous execution with valid parameters" do
      input_map = %{
        "workflow_id" => "user_onboarding",
        "execution_mode" => "sync",
        "timeout_ms" => 300_000,
        "failure_strategy" => "fail_parent"
      }

      result = ExecuteWorkflowAction.execute(input_map, %{})

      assert {:suspend, :sub_workflow_sync, suspension_data} = result
      assert suspension_data.workflow_id == "user_onboarding"
      assert suspension_data.execution_mode == "sync"
      assert suspension_data.timeout_ms == 300_000
      assert suspension_data.failure_strategy == "fail_parent"
      assert %DateTime{} = suspension_data.triggered_at
    end

    test "returns suspension for fire-and-forget execution" do
      input_map = %{
        "workflow_id" => "notification_flow",
        "execution_mode" => "fire_and_forget",
        "timeout_ms" => 60_000
      }

      result = ExecuteWorkflowAction.execute(input_map, %{})

      assert {:suspend, :sub_workflow_fire_forget, suspension_data} = result
      assert suspension_data.workflow_id == "notification_flow"
      assert suspension_data.execution_mode == "fire_and_forget"
      assert suspension_data.timeout_ms == 60_000
    end

    test "returns suspension for asynchronous execution" do
      input_map = %{
        "workflow_id" => "user_processing",
        "execution_mode" => "async",
        "timeout_ms" => 600_000,
        "failure_strategy" => "continue"
      }

      result = ExecuteWorkflowAction.execute(input_map, %{})

      assert {:suspend, :sub_workflow_async, suspension_data} = result
      assert suspension_data.workflow_id == "user_processing"
      assert suspension_data.execution_mode == "async"
      assert suspension_data.timeout_ms == 600_000
      assert suspension_data.failure_strategy == "continue"
      assert %DateTime{} = suspension_data.triggered_at
    end

    test "uses default values for optional parameters" do
      input_map = %{
        "workflow_id" => "simple_flow"
      }

      result = ExecuteWorkflowAction.execute(input_map, %{})

      assert {:suspend, :sub_workflow_sync, suspension_data} = result
      assert suspension_data.workflow_id == "simple_flow"
      # default
      assert suspension_data.execution_mode == "sync"
      # default 5 minutes
      assert suspension_data.timeout_ms == 300_000
      # default
      assert suspension_data.failure_strategy == "fail_parent"
    end

    test "returns error for missing workflow_id" do
      input_map = %{}

      result = ExecuteWorkflowAction.execute(input_map, %{})

      assert {:error, error_data, "error"} = result
      assert error_data.code == "action_error"
      assert error_data.message == "errors: %{workflow_id: [\"is required\"]}"
    end

    test "returns error for empty workflow_id" do
      input_map = %{"workflow_id" => ""}

      result = ExecuteWorkflowAction.execute(input_map, %{})

      assert {:error, error_data, "error"} = result
      assert error_data.code == "action_error"
      assert error_data.message == "errors: %{workflow_id: [\"length must be greater than or equal to 1\"]}"
    end

    test "returns error for non-string workflow_id" do
      input_map = %{"workflow_id" => 123}

      result = ExecuteWorkflowAction.execute(input_map, %{})

      assert {:error, error_data, "error"} = result
      assert error_data.code == "action_error"
      assert error_data.message == "errors: %{workflow_id: [\"is required\"]}"
    end

    test "returns error for invalid execution_mode" do
      input_map = %{
        "workflow_id" => "test_flow",
        "execution_mode" => "invalid_mode"
      }

      result = ExecuteWorkflowAction.execute(input_map, %{})

      assert {:error, error_data, "error"} = result
      assert error_data.code == "action_error"
      assert error_data.message == "errors: %{execution_mode: [\"not be in the inclusion list\"]}"
    end

    test "returns error for invalid timeout_ms" do
      input_map = %{
        "workflow_id" => "test_flow",
        "timeout_ms" => -1000
      }

      result = ExecuteWorkflowAction.execute(input_map, %{})

      assert {:error, error_data, "error"} = result
      assert error_data.code == "action_error"
      assert error_data.message == "errors: %{timeout_ms: [\"must be greater than or equal to 1\"]}"
    end

    test "returns error for invalid failure_strategy" do
      input_map = %{
        "workflow_id" => "test_flow",
        "failure_strategy" => "invalid_strategy"
      }

      result = ExecuteWorkflowAction.execute(input_map, %{})

      assert {:error, error_data, "error"} = result
      assert error_data.code == "action_error"
      assert error_data.message == "errors: %{failure_strategy: [\"not be in the inclusion list\"]}"
    end

    test "accepts 'continue' failure_strategy" do
      input_map = %{
        "workflow_id" => "test_flow",
        "failure_strategy" => "continue"
      }

      result = ExecuteWorkflowAction.execute(input_map, %{})

      assert {:suspend, :sub_workflow_sync, suspension_data} = result
      assert suspension_data.failure_strategy == "continue"
    end

    test "correctly handles different execution modes" do
      # Test sync mode
      input_map = %{
        "workflow_id" => "test_flow",
        "execution_mode" => "sync"
      }

      result = ExecuteWorkflowAction.execute(input_map, %{})
      assert {:suspend, :sub_workflow_sync, _} = result

      # Test fire_and_forget mode
      input_map = %{
        "workflow_id" => "test_flow",
        "execution_mode" => "fire_and_forget"
      }

      result = ExecuteWorkflowAction.execute(input_map, %{})
      assert {:suspend, :sub_workflow_fire_forget, _} = result
    end

    test "preserves all configuration in suspension_data for middleware handling" do
      input_map = %{
        "workflow_id" => "detailed_flow",
        "execution_mode" => "sync",
        "timeout_ms" => 120_000,
        "failure_strategy" => "continue"
      }

      result = ExecuteWorkflowAction.execute(input_map, %{})

      assert {:suspend, :sub_workflow_sync, suspension_data} = result

      # Verify all configuration is preserved for middleware
      assert suspension_data.workflow_id == "detailed_flow"
      assert suspension_data.execution_mode == "sync"
      assert suspension_data.timeout_ms == 120_000
      assert suspension_data.failure_strategy == "continue"
      assert is_struct(suspension_data.triggered_at, DateTime)
    end

    test "batch mode defaults to 'all' and wraps non-array input in list" do
      input_map = %{
        "workflow_id" => "test_workflow"
      }

      context = %{
        "$input" => %{
          "main" => %{"user_id" => 123, "name" => "John"}
        }
      }

      result = ExecuteWorkflowAction.execute(input_map, context)

      assert {:suspend, :sub_workflow_sync, suspension_data} = result
      assert suspension_data.batch_mode == "all"
      # Non-array input should be wrapped in list for single mode
      assert suspension_data.input_data == [%{"user_id" => 123, "name" => "John"}]
    end

    test "batch mode 'single' keeps array input as-is" do
      input_map = %{
        "workflow_id" => "test_workflow",
        "batch_mode" => "single"
      }

      context = %{
        "$input" => %{
          "main" => [%{"user_id" => 123}, %{"user_id" => 456}]
        }
      }

      result = ExecuteWorkflowAction.execute(input_map, context)

      assert {:suspend, :sub_workflow_sync, suspension_data} = result
      assert suspension_data.batch_mode == "single"
      # Array input should remain as array for single mode
      assert suspension_data.input_data == [%{"user_id" => 123}, %{"user_id" => 456}]
    end

    test "batch mode 'batch' passes input data as-is without wrapping" do
      input_map = %{
        "workflow_id" => "test_workflow",
        "batch_mode" => "all"
      }

      context = %{
        "$input" => %{
          "main" => %{"user_id" => 123, "name" => "John"}
        }
      }

      result = ExecuteWorkflowAction.execute(input_map, context)

      assert {:suspend, :sub_workflow_sync, suspension_data} = result
      assert suspension_data.batch_mode == "all"
      # Batch mode passes input as-is (no wrapping in list)
      assert suspension_data.input_data == %{"user_id" => 123, "name" => "John"}
    end

    test "batch mode 'batch' with array input passes array as-is" do
      input_map = %{
        "workflow_id" => "test_workflow",
        "batch_mode" => "all"
      }

      context = %{
        "$input" => %{
          "main" => [%{"user_id" => 123}, %{"user_id" => 456}]
        }
      }

      result = ExecuteWorkflowAction.execute(input_map, context)

      assert {:suspend, :sub_workflow_sync, suspension_data} = result
      assert suspension_data.batch_mode == "all"
      # Batch mode passes array input as-is
      assert suspension_data.input_data == [%{"user_id" => 123}, %{"user_id" => 456}]
    end

    test "returns error for invalid batch_mode" do
      input_map = %{
        "workflow_id" => "test_workflow",
        "batch_mode" => "invalid_mode"
      }

      result = ExecuteWorkflowAction.execute(input_map, %{})

      assert {:error, error_data, "error"} = result
      assert error_data.code == "action_error"
      assert error_data.message == "errors: %{batch_mode: [\"not be in the inclusion list\"]}"
    end

    test "handles missing input context gracefully" do
      input_map = %{
        "workflow_id" => "test_workflow",
        "batch_mode" => "single"
      }

      # Context with no input
      context = %{}

      result = ExecuteWorkflowAction.execute(input_map, context)

      assert {:suspend, :sub_workflow_sync, suspension_data} = result
      assert suspension_data.batch_mode == "single"
      # Missing input should default to empty list for single mode
      assert suspension_data.input_data == []
    end

    test "handles missing main port in input context" do
      input_map = %{
        "workflow_id" => "test_workflow",
        "batch_mode" => "all"
      }

      # Context with input but no main port
      context = %{
        "$input" => %{}
      }

      result = ExecuteWorkflowAction.execute(input_map, context)

      assert {:suspend, :sub_workflow_sync, suspension_data} = result
      assert suspension_data.batch_mode == "all"
      # Missing main port should default to empty map
      assert suspension_data.input_data == %{}
    end

    test "async mode applies batch_mode normalization" do
      input_map = %{
        "workflow_id" => "test_workflow",
        "execution_mode" => "async",
        "batch_mode" => "single"
      }

      context = %{"$input" => %{"main" => %{"user_id" => 123}}}

      result = ExecuteWorkflowAction.execute(input_map, context)

      assert {:suspend, :sub_workflow_async, suspension_data} = result
      assert suspension_data.input_data == [%{"user_id" => 123}]
    end

    test "fire_and_forget mode applies batch_mode normalization" do
      input_map = %{
        "workflow_id" => "test_workflow",
        "execution_mode" => "fire_and_forget",
        "batch_mode" => "single"
      }

      context = %{"$input" => %{"main" => %{"notification_id" => "123"}}}

      result = ExecuteWorkflowAction.execute(input_map, context)

      assert {:suspend, :sub_workflow_fire_forget, suspension_data} = result
      assert suspension_data.input_data == [%{"notification_id" => "123"}]
    end
  end
end
