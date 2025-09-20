defmodule Prana.Integrations.ScheduleTest do
  use ExUnit.Case, async: true

  alias Prana.Integrations.Schedule
  alias Prana.Integrations.Schedule.CronTriggerAction

  describe "Schedule Integration definition" do
    test "returns correct integration definition" do
      definition = Schedule.definition()

      assert definition.name == "schedule"
      assert definition.display_name == "Schedule"
      assert definition.description == "Cron-based scheduling and timing actions"
      assert definition.version == "1.0.0"
      assert definition.category == "scheduling"

      # Check cron_trigger action
      assert length(definition.actions) == 1
      cron_action_module = List.first(definition.actions)
      cron_action = cron_action_module.definition()
      assert cron_action.name == "schedule.cron_trigger"
      assert cron_action.display_name == "Cron Trigger"
      assert cron_action.input_ports == []
      assert cron_action.output_ports == ["main"]
      assert cron_action.type == :trigger
    end
  end

  describe "CronTriggerAction" do
    test "definition/0 returns correct action definition" do
      spec = CronTriggerAction.definition()

      assert spec.name == "schedule.cron_trigger"
      assert spec.display_name == "Cron Trigger"
      assert spec.type == :trigger
      assert spec.input_ports == []
      assert spec.output_ports == ["main"]

      # Check params schema
      assert spec.params_schema.type == "object"
      assert "cron_pattern" in spec.params_schema.required
      assert Map.has_key?(spec.params_schema.properties, :cron_pattern)
      assert Map.has_key?(spec.params_schema.properties, :timezone)
    end

    test "prepare/1 returns empty preparation data" do
      node = %{}
      assert {:ok, nil} = CronTriggerAction.prepare(node)
    end

    test "execute/2 returns ok with nil" do
      params = %{
        "cron_pattern" => "0 9 * * 1-5",
        "timezone" => "UTC"
      }

      context = %{}

      assert {:ok, nil} = CronTriggerAction.execute(params, context)
    end

    test "execute/2 with various cron patterns returns ok with nil" do
      valid_patterns = [
        # Every weekday at 9 AM
        "0 9 * * 1-5",
        # Every 15 minutes
        "*/15 * * * *",
        # First day of month at midnight
        "0 0 1 * *",
        # Every Sunday at 2:30 PM
        "30 14 * * 0",
        # Every 2 hours
        "0 */2 * * *",
        # At 15 and 45 minutes past hour
        "15,45 * * * *",
        # Monday, Wednesday, Friday at midnight
        "0 0 * * 1,3,5"
      ]

      context = %{}

      for pattern <- valid_patterns do
        params = %{"cron_pattern" => pattern}
        assert {:ok, nil} = CronTriggerAction.execute(params, context)
      end
    end

    test "execute/2 with different timezones returns ok with nil" do
      valid_timezones = [
        "UTC",
        "America/New_York",
        "Europe/London",
        "Asia/Tokyo"
      ]

      context = %{}

      for timezone <- valid_timezones do
        params = %{
          "cron_pattern" => "0 12 * * *",
          "timezone" => timezone
        }

        assert {:ok, nil} = CronTriggerAction.execute(params, context)
      end
    end

    test "suspendable?/0 returns false" do
      refute CronTriggerAction.suspendable?()
    end

    test "resume/3 returns error" do
      params = %{}
      context = %{}
      resume_data = %{}

      assert {:error, "Resume not supported"} = CronTriggerAction.resume(params, context, resume_data)
    end
  end

  describe "Real-world cron pattern usage" do
    test "common scheduling patterns return ok with nil" do
      test_cases = [
        %{
          pattern: "0 8 * * 1-5",
          description: "Daily at 8 AM on weekdays"
        },
        %{
          pattern: "30 */2 * * *",
          description: "Every 2 hours at 30 minutes past"
        },
        %{
          pattern: "0 0 1,15 * *",
          description: "Twice monthly on 1st and 15th"
        },
        %{
          pattern: "*/10 9-17 * * 1-5",
          description: "Every 10 minutes during business hours"
        }
      ]

      context = %{}

      for test_case <- test_cases do
        params = %{"cron_pattern" => test_case.pattern}
        assert {:ok, nil} = CronTriggerAction.execute(params, context)
      end
    end
  end
end
