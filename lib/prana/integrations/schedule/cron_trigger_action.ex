defmodule Prana.Integrations.Schedule.CronTriggerAction do
  @moduledoc """
  Cron Trigger Action - Simple trigger with crontab pattern configuration

  Creates a scheduled trigger that fires based on crontab patterns. The action configures
  the schedule pattern and timezone, while the actual scheduling is handled by the application layer.

  ## Parameters
  - `cron_pattern` (required): Crontab pattern in 5-field format
  - `timezone` (optional): Timezone for the schedule (default: "UTC")

  ### Crontab Pattern Format
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

  ## Example Params JSON

  ### Weekday Schedule
  ```json
  {
    "cron_pattern": "0 9 * * 1-5",
    "timezone": "America/New_York"
  }
  ```

  ### Periodic Schedule
  ```json
  {
    "cron_pattern": "*/15 * * * *",
    "timezone": "UTC"
  }
  ```

  ### Monthly Schedule
  ```json
  {
    "cron_pattern": "0 0 1 * *",
    "timezone": "Europe/London"
  }
  ```

  ## Output Ports
  - `main`: Scheduled trigger fired

  ## Common Cron Pattern Examples
  - `0 9 * * 1-5` - Every weekday at 9:00 AM
  - `*/15 * * * *` - Every 15 minutes
  - `0 0 1 * *` - First day of every month at midnight
  - `30 14 * * 0` - Every Sunday at 2:30 PM
  - `0 */6 * * *` - Every 6 hours
  - `0 0 * * MON` - Every Monday at midnight

  ## Behavior
  This trigger action configures scheduling parameters. The application layer is responsible
  for interpreting the cron pattern and triggering workflow execution at the specified times.
  """

  use Prana.Actions.SimpleAction

  alias Prana.Action

  def definition do
    %Action{
      name: "schedule.cron_trigger",
      display_name: "Cron Trigger",
      description: @moduledoc,
      type: :trigger,
      input_ports: [],
      output_ports: ["main"],
      params_schema: %{
        cron_pattern: [
          type: :string,
          description: "Crontab pattern (5-field format: minute hour day_of_month month day_of_week)",
          required: true
        ],
        timezone: [
          type: :string,
          description: "Timezone for the schedule (default: UTC)",
          default: "UTC"
        ]
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
