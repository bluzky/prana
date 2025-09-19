defmodule Prana.Integrations.Schedule do
  @moduledoc """
  Schedule Integration - Cron-based scheduling actions for workflow automation
  """

  @behaviour Prana.Behaviour.Integration

  alias Prana.Integration
  alias Prana.Integrations.Schedule.CronTriggerAction

  @impl true
  def definition do
    %Integration{
      name: "schedule",
      display_name: "Schedule",
      description: "Cron-based scheduling and timing actions",
      version: "1.0.0",
      category: "scheduling",
      actions: [
        CronTriggerAction
      ]
    }
  end
end
