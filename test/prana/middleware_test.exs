defmodule Prana.MiddlewareTest do
  use ExUnit.Case, async: false

  alias Prana.Middleware

  doctest Prana.Middleware

  # Test middleware modules
  defmodule TestMiddleware1 do
    @moduledoc false
    @behaviour Prana.Behaviour.Middleware

    def call(_event, data, next) do
      updated_data = Map.put(data, :middleware1_called, true)
      updated_data = Map.put(updated_data, :call_order, [__MODULE__ | Map.get(updated_data, :call_order, [])])
      next.(updated_data)
    end
  end

  defmodule TestMiddleware2 do
    @moduledoc false
    @behaviour Prana.Behaviour.Middleware

    def call(_event, data, next) do
      updated_data = Map.put(data, :middleware2_called, true)
      updated_data = Map.put(updated_data, :call_order, [__MODULE__ | Map.get(updated_data, :call_order, [])])
      next.(updated_data)
    end
  end

  defmodule TestMiddleware3 do
    @moduledoc false
    @behaviour Prana.Behaviour.Middleware

    def call(_event, data, next) do
      updated_data = Map.put(data, :middleware3_called, true)
      updated_data = Map.put(updated_data, :call_order, [__MODULE__ | Map.get(updated_data, :call_order, [])])
      next.(updated_data)
    end
  end

  defmodule EventFilterMiddleware do
    @moduledoc false
    @behaviour Prana.Behaviour.Middleware

    def call(:execution_started, data, next) do
      updated_data = Map.put(data, :execution_started_handled, true)
      next.(updated_data)
    end

    def call(:node_completed, data, next) do
      updated_data = Map.put(data, :node_completed_handled, true)
      next.(updated_data)
    end

    # Pass through other events unchanged
    def call(_event, data, next), do: next.(data)
  end

  defmodule DataTransformMiddleware do
    @moduledoc false
    @behaviour Prana.Behaviour.Middleware

    def call(_event, data, next) do
      transformed_data =
        data
        |> Map.put(:transformed, true)
        |> Map.update(:count, 1, &(&1 + 1))

      next.(transformed_data)
    end
  end

  defmodule ShortCircuitMiddleware do
    @moduledoc false
    @behaviour Prana.Behaviour.Middleware

    def call(_event, data, _next) do
      # Don't call next - short circuit the pipeline
      Map.put(data, :short_circuited, true)
    end
  end

  defmodule ErrorRaisingMiddleware do
    @moduledoc false
    @behaviour Prana.Behaviour.Middleware

    def call(_event, _data, _next) do
      raise "Middleware error!"
    end
  end

  defmodule ConditionalErrorMiddleware do
    @moduledoc false
    @behaviour Prana.Behaviour.Middleware

    def call(_event, %{should_error: true}, _next) do
      raise "Conditional error!"
    end

    def call(_event, data, next) do
      next.(data)
    end
  end

  setup do
    # Clear middleware before each test
    Middleware.clear_middleware()
    :ok
  end

  describe "get_middleware_modules/0" do
    test "returns empty list when no middleware configured" do
      assert Middleware.get_middleware_modules() == []
    end

    test "returns configured middleware modules" do
      Application.put_env(:prana, :middleware, [TestMiddleware1, TestMiddleware2])

      assert Middleware.get_middleware_modules() == [TestMiddleware1, TestMiddleware2]
    end
  end

  describe "call/2" do
    test "returns data unchanged when no middleware configured" do
      data = %{test: "data"}

      result = Middleware.call(:test_event, data)

      assert result == data
    end

    test "executes single middleware and returns transformed data" do
      Middleware.add_middleware(TestMiddleware1)
      data = %{test: "data"}

      result = Middleware.call(:test_event, data)

      assert result.middleware1_called == true
      assert result.test == "data"
    end

    test "executes multiple middleware in order" do
      Middleware.add_middleware(TestMiddleware1)
      Middleware.add_middleware(TestMiddleware2)
      Middleware.add_middleware(TestMiddleware3)

      data = %{test: "data"}

      result = Middleware.call(:test_event, data)

      assert result.middleware1_called == true
      assert result.middleware2_called == true
      assert result.middleware3_called == true

      # Check order of execution (reversed because we prepend to list)
      assert result.call_order == [TestMiddleware3, TestMiddleware2, TestMiddleware1]
    end

    test "handles different event types" do
      Middleware.add_middleware(EventFilterMiddleware)

      # Test execution_started event
      result1 = Middleware.call(:execution_started, %{})
      assert result1.execution_started_handled == true
      refute Map.has_key?(result1, :node_completed_handled)

      # Test node_completed event
      result2 = Middleware.call(:node_completed, %{})
      assert result2.node_completed_handled == true
      refute Map.has_key?(result2, :execution_started_handled)

      # Test other event (should pass through)
      result3 = Middleware.call(:other_event, %{original: true})
      assert result3.original == true
      refute Map.has_key?(result3, :execution_started_handled)
      refute Map.has_key?(result3, :node_completed_handled)
    end

    test "middleware can transform data" do
      Middleware.add_middleware(DataTransformMiddleware)

      data = %{original: "value"}
      result = Middleware.call(:test_event, data)

      assert result.original == "value"
      assert result.transformed == true
      assert result.count == 1
    end

    test "multiple transforming middleware accumulate changes" do
      Middleware.add_middleware(DataTransformMiddleware)
      Middleware.add_middleware(DataTransformMiddleware)

      data = %{original: "value"}
      result = Middleware.call(:test_event, data)

      assert result.original == "value"
      assert result.transformed == true
      # Both middleware incremented count
      assert result.count == 2
    end

    test "middleware can short-circuit pipeline" do
      Middleware.add_middleware(TestMiddleware1)
      Middleware.add_middleware(ShortCircuitMiddleware)
      # Should not be called
      Middleware.add_middleware(TestMiddleware2)

      data = %{test: "data"}
      result = Middleware.call(:test_event, data)

      assert result.middleware1_called == true
      assert result.short_circuited == true
      refute Map.has_key?(result, :middleware2_called)
    end

    test "continues pipeline on middleware error" do
      import ExUnit.CaptureLog

      Middleware.add_middleware(TestMiddleware1)
      Middleware.add_middleware(ErrorRaisingMiddleware)
      Middleware.add_middleware(TestMiddleware2)

      data = %{test: "data"}

      log =
        capture_log(fn ->
          result = Middleware.call(:test_event, data)

          # First middleware should have executed
          assert result.middleware1_called == true
          # Second middleware should have executed (original data passed through after error)
          assert result.middleware2_called == true
          # Test data should be preserved
          assert result.test == "data"
        end)

      assert log =~ "Middleware"
      assert log =~ "failed for event"
      assert log =~ "Middleware error!"
    end

    test "handles conditional middleware errors" do
      import ExUnit.CaptureLog

      Middleware.add_middleware(ConditionalErrorMiddleware)
      Middleware.add_middleware(TestMiddleware1)

      # Test with error condition
      log =
        capture_log(fn ->
          result = Middleware.call(:test_event, %{should_error: true})

          # Should continue with original data after error
          assert result.middleware1_called == true
          assert result.should_error == true
        end)

      assert log =~ "Conditional error!"

      # Test without error condition
      result = Middleware.call(:test_event, %{should_error: false})
      assert result.middleware1_called == true
      assert result.should_error == false
    end

    test "passes original event to all middleware" do
      defmodule EventCapturingMiddleware do
        @moduledoc false
        @behaviour Prana.Behaviour.Middleware

        def call(event, data, next) do
          updated_data = Map.put(data, :captured_event, event)
          next.(updated_data)
        end
      end

      Middleware.add_middleware(EventCapturingMiddleware)

      result = Middleware.call(:execution_started, %{})
      assert result.captured_event == :execution_started

      result = Middleware.call(:node_failed, %{})
      assert result.captured_event == :node_failed
    end
  end

  describe "execute_pipeline/3" do
    test "returns data unchanged for empty middleware list" do
      data = %{test: "data"}

      result = Middleware.execute_pipeline([], :test_event, data)

      assert result == data
    end

    test "executes middleware in provided order" do
      middleware_list = [TestMiddleware1, TestMiddleware2]
      data = %{test: "data"}

      result = Middleware.execute_pipeline(middleware_list, :test_event, data)

      assert result.middleware1_called == true
      assert result.middleware2_called == true
      assert result.call_order == [TestMiddleware2, TestMiddleware1]
    end

    test "handles error in specific middleware position" do
      import ExUnit.CaptureLog

      middleware_list = [TestMiddleware1, ErrorRaisingMiddleware, TestMiddleware2]
      data = %{test: "data"}

      log =
        capture_log(fn ->
          result = Middleware.execute_pipeline(middleware_list, :test_event, data)

          assert result.middleware1_called == true
          assert result.middleware2_called == true
          assert result.test == "data"
        end)

      assert log =~ "Middleware"
      assert log =~ "failed for event"
    end
  end

  describe "add_middleware/1" do
    test "adds middleware to empty list" do
      Middleware.add_middleware(TestMiddleware1)

      assert Middleware.get_middleware_modules() == [TestMiddleware1]
    end

    test "appends middleware to existing list" do
      Application.put_env(:prana, :middleware, [TestMiddleware1])

      Middleware.add_middleware(TestMiddleware2)

      assert Middleware.get_middleware_modules() == [TestMiddleware1, TestMiddleware2]
    end

    test "allows duplicate middleware" do
      Middleware.add_middleware(TestMiddleware1)
      Middleware.add_middleware(TestMiddleware1)

      assert Middleware.get_middleware_modules() == [TestMiddleware1, TestMiddleware1]
    end
  end

  describe "remove_middleware/1" do
    test "removes middleware from list" do
      Application.put_env(:prana, :middleware, [TestMiddleware1, TestMiddleware2])

      Middleware.remove_middleware(TestMiddleware1)

      assert Middleware.get_middleware_modules() == [TestMiddleware2]
    end

    test "removes all instances of middleware" do
      Application.put_env(:prana, :middleware, [TestMiddleware1, TestMiddleware2, TestMiddleware1])

      Middleware.remove_middleware(TestMiddleware1)

      assert Middleware.get_middleware_modules() == [TestMiddleware2]
    end

    test "handles removing non-existent middleware" do
      Application.put_env(:prana, :middleware, [TestMiddleware1])

      Middleware.remove_middleware(TestMiddleware2)

      assert Middleware.get_middleware_modules() == [TestMiddleware1]
    end

    test "handles removing from empty list" do
      Middleware.remove_middleware(TestMiddleware1)

      assert Middleware.get_middleware_modules() == []
    end
  end

  describe "clear_middleware/0" do
    test "clears all middleware" do
      Application.put_env(:prana, :middleware, [TestMiddleware1, TestMiddleware2])

      Middleware.clear_middleware()

      assert Middleware.get_middleware_modules() == []
    end

    test "handles clearing empty middleware list" do
      Middleware.clear_middleware()

      assert Middleware.get_middleware_modules() == []
    end
  end

  describe "get_stats/0" do
    test "returns stats for empty middleware list" do
      stats = Middleware.get_stats()

      assert stats.total_middleware == 0
      assert stats.middleware_modules == []
    end

    test "returns stats for configured middleware" do
      Application.put_env(:prana, :middleware, [TestMiddleware1, TestMiddleware2])

      stats = Middleware.get_stats()

      assert stats.total_middleware == 2
      assert stats.middleware_modules == [TestMiddleware1, TestMiddleware2]
    end
  end

  describe "integration scenarios" do
    test "realistic workflow execution scenario" do
      defmodule DatabaseMiddleware do
        @moduledoc false
        @behaviour Prana.Behaviour.Middleware

        def call(:execution_started, execution, next) do
          updated = Map.put(execution, :persisted, true)
          next.(updated)
        end

        def call(:node_completed, data, next) do
          updated = Map.update(data, :completed_nodes, 1, &(&1 + 1))
          next.(updated)
        end

        def call(_event, data, next), do: next.(data)
      end

      defmodule NotificationMiddleware do
        @moduledoc false
        @behaviour Prana.Behaviour.Middleware

        def call(:execution_completed, execution, next) do
          updated = Map.put(execution, :notification_sent, true)
          next.(updated)
        end

        def call(_event, data, next), do: next.(data)
      end

      Middleware.add_middleware(DatabaseMiddleware)
      Middleware.add_middleware(NotificationMiddleware)

      # Test execution started
      execution = %{id: "exec_123", status: :running}
      result = Middleware.call(:execution_started, execution)

      assert result.persisted == true
      assert result.id == "exec_123"
      refute Map.has_key?(result, :notification_sent)

      # Test node completed
      node_data = %{node_id: "node_456", execution_id: "exec_123"}
      result = Middleware.call(:node_completed, node_data)

      assert result.completed_nodes == 1
      assert result.node_id == "node_456"

      # Test execution completed
      completed_execution = %{id: "exec_123", status: :completed}
      result = Middleware.call(:execution_completed, completed_execution)

      assert result.notification_sent == true
      assert result.id == "exec_123"
    end

    test "error handling doesn't break workflow" do
      import ExUnit.CaptureLog

      defmodule CriticalMiddleware do
        @moduledoc false
        @behaviour Prana.Behaviour.Middleware

        def call(_event, data, next) do
          updated = Map.put(data, :critical_processed, true)
          next.(updated)
        end
      end

      Middleware.add_middleware(CriticalMiddleware)
      Middleware.add_middleware(ErrorRaisingMiddleware)
      Middleware.add_middleware(CriticalMiddleware)

      data = %{execution_id: "exec_123"}

      log =
        capture_log(fn ->
          result = Middleware.call(:execution_started, data)

          # Both critical middleware should have executed despite error in middle
          assert result.critical_processed == true
          assert result.execution_id == "exec_123"
        end)

      assert log =~ "Middleware error!"
    end

    test "middleware chain with data transformation" do
      defmodule EnrichmentMiddleware do
        @moduledoc false
        @behaviour Prana.Behaviour.Middleware

        def call(_event, data, next) do
          enriched =
            Map.merge(data, %{
              timestamp: DateTime.utc_now(),
              enriched: true
            })

          next.(enriched)
        end
      end

      defmodule ValidationMiddleware do
        @moduledoc false
        @behaviour Prana.Behaviour.Middleware

        def call(_event, data, next) do
          validated = Map.put(data, :validated, Map.has_key?(data, :execution_id))
          next.(validated)
        end
      end

      Middleware.add_middleware(EnrichmentMiddleware)
      Middleware.add_middleware(ValidationMiddleware)

      data = %{execution_id: "exec_123"}
      result = Middleware.call(:execution_started, data)

      assert result.execution_id == "exec_123"
      assert result.enriched == true
      assert result.validated == true
      assert %DateTime{} = result.timestamp
    end
  end

  describe "edge cases" do
    test "handles complex nested data structures" do
      complex_data = %{
        execution: %{
          id: "exec_123",
          nodes: [
            %{id: "node_1", type: :trigger},
            %{id: "node_2", type: :action}
          ]
        },
        context: %{
          variables: %{api_key: "secret"},
          results: %{}
        }
      }

      Middleware.add_middleware(DataTransformMiddleware)

      result = Middleware.call(:execution_started, complex_data)

      # Original structure should be preserved
      assert result.execution.id == "exec_123"
      assert length(result.execution.nodes) == 2
      assert result.context.variables.api_key == "secret"

      # Transformation should be applied
      assert result.transformed == true
      assert result.count == 1
    end

    test "handles very long middleware chains" do
      # Add many middleware to test performance/stack depth
      for _i <- 1..50 do
        Middleware.add_middleware(DataTransformMiddleware)
      end

      data = %{test: "data"}
      result = Middleware.call(:test_event, data)

      assert result.test == "data"
      assert result.transformed == true
      assert result.count == 50
    end
  end
end
