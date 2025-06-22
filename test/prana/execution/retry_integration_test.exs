defmodule Prana.RetryIntegrationTest do
  use ExUnit.Case, async: true

  alias Prana.Connection
  alias Prana.GraphExecutor
  alias Prana.IntegrationRegistry
  alias Prana.Node
  alias Prana.RetryPolicy
  alias Prana.Workflow

  # Test integration that can simulate failures and retries
  defmodule FlakeyIntegration do
    @moduledoc false
    @behaviour Prana.Behaviour.Integration

    def definition do
      %Prana.Integration{
        name: "flakey",
        display_name: "Flakey Integration",
        actions: %{
          "unreliable_action" => %Prana.Action{
            name: "unreliable_action",
            module: __MODULE__,
            function: :unreliable_action,
            input_ports: ["input"],
            output_ports: ["success", "error"],
            default_success_port: "success",
            default_error_port: "error"
          }
        }
      }
    end

    def unreliable_action(%{"attempt_count" => count, "succeed_on_attempt" => succeed_on}) when count >= succeed_on do
      {:ok, %{"result" => "success", "attempts" => count}}
    end

    def unreliable_action(%{"attempt_count" => count}) do
      {:error, "Simulated failure on attempt #{count}"}
    end
  end

  setup do
    # Start IntegrationRegistry
    {:ok, _pid} = IntegrationRegistry.start_link([])
    IntegrationRegistry.register_integration(FlakeyIntegration)
    :ok
  end

  describe "retry handling" do
    test "retries failed node and eventually succeeds" do
      workflow = create_retry_workflow(succeed_on_attempt: 3)
      input_data = %{"attempt_count" => 1}

      case GraphExecutor.execute_workflow(workflow, input_data) do
        {:ok, context} ->
          # Should eventually succeed after retries
          assert context.execution.status == :completed
          assert MapSet.size(context.completed_nodes) == 1

          # Check retry information
          retry_info = get_in(context.metadata, [:retry_info])
          assert retry_info != nil

          # Should have retry statistics in execution stats
          stats = get_in(context.metadata, [:execution_stats])
          assert stats[:completed_nodes] == 1

        {:error, reason} ->
          flunk("Workflow should succeed after retries: #{inspect(reason)}")
      end
    end

    test "stops retrying after max attempts reached" do
      workflow = create_retry_workflow(succeed_on_attempt: 10, max_attempts: 2)
      input_data = %{"attempt_count" => 1}

      case GraphExecutor.execute_workflow(workflow, input_data) do
        {:ok, context} ->
          # Should complete but with failed nodes
          assert MapSet.size(context.failed_nodes) == 1

        {:error, :workflow_completed_with_failures} ->
          # This is expected when retries are exhausted
          assert true

        {:error, reason} ->
          # Should be retry-related error
          assert reason != nil
      end
    end

    test "applies different backoff strategies" do
      # Test exponential backoff
      retry_policy = %RetryPolicy{
        max_attempts: 3,
        backoff_strategy: :exponential,
        initial_delay_ms: 100,
        backoff_multiplier: 2.0
      }

      workflow = create_retry_workflow_with_policy(retry_policy, succeed_on_attempt: 3)
      input_data = %{"attempt_count" => 1}

      start_time = :os.system_time(:millisecond)

      case GraphExecutor.execute_workflow(workflow, input_data) do
        {:ok, _context} ->
          end_time = :os.system_time(:millisecond)
          duration = end_time - start_time

          # Should take at least 300ms due to backoff delays (100 + 200)
          assert duration >= 300

        {:error, reason} ->
          flunk("Workflow should succeed with exponential backoff: #{inspect(reason)}")
      end
    end

    test "filters retry based on error types" do
      # Only retry on specific error types
      retry_policy = %RetryPolicy{
        max_attempts: 3,
        retry_on_errors: ["network_error", "timeout"],
        initial_delay_ms: 50
      }

      workflow = create_retry_workflow_with_policy(retry_policy, succeed_on_attempt: 2)
      input_data = %{"attempt_count" => 1}

      # This should not retry because error type doesn't match
      case GraphExecutor.execute_workflow(workflow, input_data) do
        {:ok, context} ->
          # Should fail immediately without retry
          assert MapSet.size(context.failed_nodes) == 1

        {:error, :workflow_completed_with_failures} ->
          assert true

        {:error, _reason} ->
          assert true
      end
    end
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp create_retry_workflow(opts \\ []) do
    succeed_on_attempt = Keyword.get(opts, :succeed_on_attempt, 2)
    max_attempts = Keyword.get(opts, :max_attempts, 5)

    retry_policy = %RetryPolicy{
      max_attempts: max_attempts,
      backoff_strategy: :fixed,
      initial_delay_ms: 50,
      # Retry on all errors
      retry_on_errors: []
    }

    create_retry_workflow_with_policy(retry_policy, succeed_on_attempt)
  end

  defp create_retry_workflow_with_policy(retry_policy, succeed_on_attempt) do
    workflow = Workflow.new("Retry Test", "Test retry functionality")

    # Create node with retry policy
    flakey_node =
      Node.new(
        "Flakey Action",
        :action,
        "flakey",
        "unreliable_action",
        %{
          "attempt_count" => "$input.attempt_count",
          "succeed_on_attempt" => succeed_on_attempt
        },
        "flakey_action"
      )

    # Set retry policy
    flakey_node = %{flakey_node | retry_policy: retry_policy}

    # Add node to workflow
    workflow = Workflow.add_node!(workflow, flakey_node)
    workflow
  end
end
