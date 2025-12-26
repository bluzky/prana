defmodule Prana.ErrorTrackerTest do
  use ExUnit.Case, async: false

  alias Prana.ErrorTracker

  # Test error tracker implementations
  defmodule TestErrorTracker do
    @moduledoc false
    @behaviour Prana.Behaviour.ErrorTracker

    def capture_error(exception, stacktrace) do
      # Store in test process dictionary for verification
      captured = Process.get(:captured_errors, [])
      Process.put(:captured_errors, [{exception, stacktrace} | captured])
      :ok
    end
  end

  defmodule FailingErrorTracker do
    @moduledoc false
    @behaviour Prana.Behaviour.ErrorTracker

    def capture_error(_exception, _stacktrace) do
      raise RuntimeError, "Error tracker failure"
    end
  end

  setup do
    # Clear any captured errors
    Process.delete(:captured_errors)

    # Store original config
    original_config = Application.get_env(:prana, :error_tracker)

    on_exit(fn ->
      # Restore original config
      if original_config do
        Application.put_env(:prana, :error_tracker, original_config)
      else
        Application.delete_env(:prana, :error_tracker)
      end
    end)

    :ok
  end

  describe "ErrorTracker.Console" do
    import ExUnit.CaptureLog

    test "captures error and logs to console" do
      exception = %RuntimeError{message: "Test error"}
      stacktrace = [{SomeModule, :some_function, 1, [file: "test.ex", line: 42]}]

      log =
        capture_log(fn ->
          assert :ok = Prana.ErrorTracker.Console.capture_error(exception, stacktrace)
        end)

      assert log =~ "Workflow error captured"
      assert log =~ "RuntimeError"
      assert log =~ "Test error"
    end

    test "formats stacktrace in log output" do
      exception = %ArgumentError{message: "Invalid argument"}

      stacktrace = [
        {MyApp.Worker, :process, 2, [file: "lib/worker.ex", line: 15]},
        {Prana.NodeExecutor, :execute, 2, [file: "lib/prana/node_executor.ex", line: 100]}
      ]

      log =
        capture_log(fn ->
          Prana.ErrorTracker.Console.capture_error(exception, stacktrace)
        end)

      assert log =~ "ArgumentError"
      assert log =~ "Invalid argument"
    end

    test "handles exceptions without stacktrace" do
      exception = %RuntimeError{message: "No stacktrace"}
      stacktrace = []

      log =
        capture_log(fn ->
          assert :ok = Prana.ErrorTracker.Console.capture_error(exception, stacktrace)
        end)

      assert log =~ "RuntimeError"
      assert log =~ "No stacktrace"
    end
  end

  describe "ErrorTracker.get_error_tracker/0" do
    test "returns configured error tracker module" do
      Application.put_env(:prana, :error_tracker, TestErrorTracker)
      assert ErrorTracker.get_error_tracker() == TestErrorTracker
    end

    test "returns default Console tracker when not configured" do
      Application.delete_env(:prana, :error_tracker)
      assert ErrorTracker.get_error_tracker() == Prana.ErrorTracker.Console
    end
  end

  describe "ErrorTracker.capture_error/2" do
    test "delegates to configured error tracker" do
      Application.put_env(:prana, :error_tracker, TestErrorTracker)

      exception = %RuntimeError{message: "Test error"}
      stacktrace = [{SomeModule, :func, 1, [file: "test.ex", line: 10]}]

      assert :ok = ErrorTracker.capture_error(exception, stacktrace)

      captured = Process.get(:captured_errors, [])
      assert length(captured) == 1
      assert [{^exception, ^stacktrace}] = captured
    end

    test "uses default Console tracker when not configured" do
      import ExUnit.CaptureLog

      Application.delete_env(:prana, :error_tracker)

      exception = %RuntimeError{message: "Default tracker test"}
      stacktrace = []

      log =
        capture_log(fn ->
          assert :ok = ErrorTracker.capture_error(exception, stacktrace)
        end)

      assert log =~ "Workflow error captured"
      assert log =~ "Default tracker test"
    end

    test "falls back to Console when configured tracker fails" do
      import ExUnit.CaptureLog

      Application.put_env(:prana, :error_tracker, FailingErrorTracker)

      exception = %RuntimeError{message: "Original error"}
      stacktrace = [{Module, :func, 0, []}]

      log =
        capture_log(fn ->
          assert :ok = ErrorTracker.capture_error(exception, stacktrace)
        end)

      # Should fall back to console and log the original error
      assert log =~ "Workflow error captured"
      assert log =~ "Original error"
      assert log =~ "RuntimeError"
    end

    test "always returns :ok even when tracker fails" do
      Application.put_env(:prana, :error_tracker, FailingErrorTracker)

      exception = %RuntimeError{message: "Test"}
      stacktrace = []

      # Should not raise, even though the tracker fails
      assert :ok = ErrorTracker.capture_error(exception, stacktrace)
    end

    test "handles different exception types" do
      Application.put_env(:prana, :error_tracker, TestErrorTracker)

      exceptions = [
        %RuntimeError{message: "Runtime error"},
        %ArgumentError{message: "Argument error"},
        %KeyError{key: :missing, term: %{}},
        %MatchError{term: {:error, "something"}}
      ]

      for exception <- exceptions do
        stacktrace = [{SomeModule, :func, 1, []}]
        assert :ok = ErrorTracker.capture_error(exception, stacktrace)
      end

      captured = Process.get(:captured_errors, [])
      assert length(captured) == length(exceptions)
    end

    test "captures complex stacktraces" do
      Application.put_env(:prana, :error_tracker, TestErrorTracker)

      exception = %RuntimeError{message: "Deep error"}

      stacktrace = [
        {Module1, :function1, 3, [file: "lib/module1.ex", line: 42]},
        {Module2, :function2, 1, [file: "lib/module2.ex", line: 15]},
        {Module3, :function3, 0, [file: "lib/module3.ex", line: 99]},
        {:elixir_eval, :eval, 2, [file: "elixir_eval.ex", line: 10]}
      ]

      assert :ok = ErrorTracker.capture_error(exception, stacktrace)

      captured = Process.get(:captured_errors, [])
      assert [{^exception, ^stacktrace}] = captured
    end
  end

  describe "integration with real exceptions" do
    test "captures actual raised exceptions" do
      Application.put_env(:prana, :error_tracker, TestErrorTracker)

      try do
        raise RuntimeError, "Actual exception"
      rescue
        exception ->
          stacktrace = __STACKTRACE__
          ErrorTracker.capture_error(exception, stacktrace)
      end

      captured = Process.get(:captured_errors, [])
      assert length(captured) == 1
      [{exception, stacktrace}] = captured

      assert %RuntimeError{message: "Actual exception"} = exception
      assert is_list(stacktrace)
      assert length(stacktrace) > 0
    end

    test "captures exceptions from nested function calls" do
      Application.put_env(:prana, :error_tracker, TestErrorTracker)

      defmodule TestHelper do
        def level3 do
          raise ArgumentError, "Deep error"
        end

        def level2, do: level3()
        def level1, do: level2()
      end

      try do
        TestHelper.level1()
      rescue
        exception ->
          stacktrace = __STACKTRACE__
          ErrorTracker.capture_error(exception, stacktrace)
      end

      captured = Process.get(:captured_errors, [])
      assert length(captured) == 1
      [{exception, stacktrace}] = captured

      assert %ArgumentError{message: "Deep error"} = exception
      # Stacktrace should show the nested calls
      assert Enum.any?(stacktrace, fn {mod, _fun, _arity, _info} ->
               mod == TestHelper
             end)
    end
  end
end
