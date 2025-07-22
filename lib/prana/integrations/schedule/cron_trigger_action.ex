defmodule Prana.Integrations.Schedule.CronTriggerAction do
  @moduledoc """
  Cron Trigger Action - Simple trigger with crontab pattern configuration

  This action accepts crontab patterns as configuration parameters.
  The actual scheduling is handled by the application layer.

  ## Crontab Pattern Format

  Standard 5-field crontab format:
  ```
  * * * * *
  │ │ │ │ │
  │ │ │ │ └─── Day of Week   (0-7, both 0 and 7 are Sunday)
  │ │ │ └──── Month         (1-12)
  │ │ └───── Day of Month   (1-31)
  │ └────── Hour            (0-23)
  └─────── Minute           (0-59)
  ```

  ## Examples

  - `0 9 * * 1-5` - Every weekday at 9:00 AM
  - `*/15 * * * *` - Every 15 minutes
  - `0 0 1 * *` - First day of every month at midnight
  - `30 14 * * 0` - Every Sunday at 2:30 PM
  """

  use Prana.Actions.SimpleAction

  alias Prana.Action

  def specification do
    %Action{
      name: "schedule.cron_trigger",
      display_name: "Cron Trigger",
      description: "Trigger with crontab pattern configuration",
      type: :trigger,
      module: __MODULE__,
      input_ports: [],
      output_ports: ["main"],
      params_schema: %{
        type: "object",
        required: ["cron_pattern"],
        properties: %{
          cron_pattern: %{
            type: "string",
            description: "Crontab pattern (5-field format: minute hour day_of_month month day_of_week)"
          },
          timezone: %{
            type: "string",
            description: "Timezone for the schedule (default: UTC)",
            default: "UTC"
          }
        }
      },
      metadata: %{
        category: "scheduling",
        tags: ["trigger", "cron", "schedule", "time"]
      }
    }
  end

  @impl true
  def execute(_params, _context) do
    {:ok, nil}
  end
end
