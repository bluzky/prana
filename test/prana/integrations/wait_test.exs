defmodule Prana.Integrations.WaitTest do
  use ExUnit.Case

  alias Prana.Core.Error
  alias Prana.IntegrationRegistry
  alias Prana.Integrations.Wait

  describe "definition/0" do
    test "returns correct integration definition" do
      definition = Wait.definition()

      assert definition.name == "wait"
      assert definition.display_name == "Wait"
      assert definition.version == "1.0.0"
      assert definition.category == "control"
      assert Map.has_key?(definition.actions, "wait")
      assert map_size(definition.actions) == 1
    end

    test "wait action has correct configuration" do
      definition = Wait.definition()
      wait_action = definition.actions["wait"]

      assert wait_action.name == "wait.wait"
      assert wait_action.display_name == "Wait"
      assert wait_action.module == Prana.Integrations.Wait.WaitAction
      assert wait_action.input_ports == ["main"]
      assert wait_action.output_ports == ["main", "timeout", "error"]
    end
  end

  describe "unified wait/1 action" do
    test "returns error for missing mode" do
      input_map = %{"duration" => 1000}

      assert {:error, %Error{code: "action_error", message: "mode is required"}, "error"} =
               Wait.wait(input_map)
    end

    test "returns error for invalid mode" do
      input_map = %{"mode" => "invalid", "duration" => 1000}

      assert {:error, %Error{code: "action_error", message: "mode must be 'interval', 'schedule', or 'webhook'"}, "error"} =
               Wait.wait(input_map)
    end

    test "interval mode works correctly" do
      input_map = %{"mode" => "interval", "duration" => 500_000}

      assert {:suspend, :interval, suspension_data} = Wait.wait(input_map)
      assert suspension_data.mode == "interval"
      assert %DateTime{} = suspension_data.resume_at
    end

    test "interval mode supports different time units" do
      input_map = %{"mode" => "interval", "duration" => 2, "unit" => "minutes"}

      assert {:suspend, :interval, suspension_data} = Wait.wait(input_map)
      assert suspension_data.mode == "interval"
      assert %DateTime{} = suspension_data.resume_at
    end

    test "interval mode returns error for missing duration" do
      input_map = %{"mode" => "interval"}

      assert {:error, %Error{code: "action_error", message: "duration/timeout is required"}, "error"} =
               Wait.wait(input_map)
    end

    test "interval mode returns error for invalid duration" do
      input_map = %{"mode" => "interval", "duration" => -100}

      assert {:error, %Error{code: "action_error", message: "duration/timeout must be a positive number"}, "error"} =
               Wait.wait(input_map)
    end

    test "schedule mode works correctly" do
      future_time = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_iso8601()
      input_map = %{"mode" => "schedule", "schedule_at" => future_time}

      assert {:suspend, :schedule, suspension_data} = Wait.wait(input_map)
      assert suspension_data.mode == "schedule"
      assert suspension_data.timezone == "UTC"
      assert %DateTime{} = suspension_data.resume_at
    end

    test "schedule mode returns error for past time" do
      past_time = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.to_iso8601()
      input_map = %{"mode" => "schedule", "schedule_at" => past_time}

      assert {:error, %Error{code: "action_error", message: "schedule_at must be in the future"}, "error"} =
               Wait.wait(input_map)
    end

    test "schedule mode returns error for invalid datetime" do
      input_map = %{"mode" => "schedule", "schedule_at" => "invalid-datetime"}

      assert {:error, %Error{code: "action_error"}, "error"} =
               Wait.wait(input_map)
    end

    test "schedule mode returns error for missing schedule_at" do
      input_map = %{"mode" => "schedule"}

      assert {:error, %Error{code: "action_error", message: "schedule_at is required"}, "error"} =
               Wait.wait(input_map)
    end

    test "webhook mode works correctly" do
      input_map = %{"mode" => "webhook", "timeout_hours" => 48}

      assert {:suspend, :webhook, suspension_data} = Wait.wait(input_map)
      assert suspension_data.mode == "webhook"
      assert suspension_data.timeout_hours == 48
      assert %DateTime{} = suspension_data.expires_at
    end

    test "webhook mode defaults timeout_hours to 24" do
      input_map = %{"mode" => "webhook"}

      assert {:suspend, :webhook, suspension_data} = Wait.wait(input_map)
      assert suspension_data.timeout_hours == 24
      assert %DateTime{} = suspension_data.expires_at
    end

    test "webhook mode returns error for invalid timeout_hours" do
      input_map = %{"mode" => "webhook", "timeout_hours" => -1}

      assert {:error,
              %Error{
                code: "action_error",
                message: "timeout_hours must be a positive number between 1 and 8760 (1 year)"
              },
              "error"} =
               Wait.wait(input_map)
    end

    test "webhook mode returns error for too large timeout_hours" do
      input_map = %{"mode" => "webhook", "timeout_hours" => 10_000}

      assert {:error,
              %Error{
                code: "action_error",
                message: "timeout_hours must be a positive number between 1 and 8760 (1 year)"
              },
              "error"} =
               Wait.wait(input_map)
    end
  end

  describe "time unit conversions" do
    test "converts seconds to milliseconds correctly" do
      input_map = %{"mode" => "interval", "duration" => 1, "unit" => "seconds"}

      # 1 second is less than 60 seconds, so it should sleep and return {:ok, %{}, "main"}
      assert {:ok, %{}, "main"} = Wait.wait(input_map)
    end

    test "converts minutes to milliseconds correctly" do
      input_map = %{"mode" => "interval", "duration" => 1, "unit" => "minutes"}

      assert {:suspend, :interval, suspension_data} = Wait.wait(input_map)
      assert suspension_data.mode == "interval"
      assert %DateTime{} = suspension_data.resume_at
    end

    test "converts hours to milliseconds correctly" do
      input_map = %{"mode" => "interval", "duration" => 1, "unit" => "hours"}

      assert {:suspend, :interval, suspension_data} = Wait.wait(input_map)
      assert suspension_data.mode == "interval"
      assert %DateTime{} = suspension_data.resume_at
    end

    test "handles fractional conversions" do
      input_map = %{"mode" => "interval", "duration" => 0.1, "unit" => "minutes"}

      # 0.1 minutes = 6 seconds, which is less than 60 seconds, so it should sleep and return {:ok, %{}, "main"}
      assert {:ok, %{}, "main"} = Wait.wait(input_map)
    end

    test "defaults to milliseconds when unit not specified" do
      input_map = %{"mode" => "interval", "duration" => 3000}

      # 3000 ms = 3 seconds, which is less than 60 seconds, so it should sleep and return {:ok, %{}, "main"}
      assert {:ok, %{}, "main"} = Wait.wait(input_map)
    end

    test "returns error for invalid unit" do
      input_map = %{"mode" => "interval", "duration" => 1000, "unit" => "invalid"}

      assert {:error, %Error{code: "action_error", message: "unit must be 'ms', 'seconds', 'minutes', or 'hours'"},
              "error"} =
               Wait.wait(input_map)
    end

    test "still suspends for durations >= 60 seconds" do
      input_map = %{"mode" => "interval", "duration" => 60, "unit" => "seconds"}

      assert {:suspend, :interval, suspension_data} = Wait.wait(input_map)
      assert suspension_data.mode == "interval"
      assert %DateTime{} = suspension_data.resume_at
    end
  end

  describe "integration registration" do
    test "can be registered with IntegrationRegistry" do
      # Start registry
      {:ok, registry_pid} = IntegrationRegistry.start_link([])

      # Register the Wait integration
      assert :ok = IntegrationRegistry.register_integration(Wait)

      # Verify it's registered
      assert IntegrationRegistry.integration_registered?("wait")

      # Get the integration definition
      assert {:ok, integration} = IntegrationRegistry.get_integration("wait")
      assert integration.name == "wait"
      assert integration.display_name == "Wait"

      # Get wait action
      assert {:ok, wait_action} = IntegrationRegistry.get_action_by_type("wait.wait")
      assert wait_action.name == "wait.wait"

      # Cleanup
      GenServer.stop(registry_pid)
    end
  end
end
