defmodule Prana.Integrations.Wait do
  @moduledoc """
  Wait Integration - Provides delay and timeout actions for time-based workflows

  Supports:
  - Delay actions with configurable duration
  - Timeout actions with deadline-based suspension
  - Flexible time units (milliseconds, seconds, minutes, hours)
  - Suspension/resume patterns for non-blocking delays

  This integration implements time-based workflow control using the
  suspension/resume mechanism for efficient resource usage.
  """

  @behaviour Prana.Behaviour.Integration

  alias Prana.Action
  alias Prana.Integration

  @doc """
  Returns the integration definition with all available actions
  """
  @impl true
  def definition do
    %Integration{
      name: "wait",
      display_name: "Wait",
      description: "Time-based workflow control with delays and timeouts",
      version: "1.0.0",
      category: "control",
      actions: %{
        "wait" => %Action{
          name: "wait",
          display_name: "Wait",
          description: "Unified wait action supporting multiple modes: interval, schedule, webhook",
          module: Prana.Integrations.Wait.WaitAction,
          input_ports: ["input"],
          output_ports: ["success", "timeout", "error"],
          default_success_port: "success",
          default_error_port: "error"
        }
      }
    }
  end

  @doc """
  Unified wait action - supports multiple wait modes

  Expected input_map:
  - mode: Wait mode - "interval" | "schedule" | "webhook" (required)

  Mode-specific parameters:

  Interval mode:
  - duration: Time to wait (required)
  - unit: Time unit - "ms" | "seconds" | "minutes" | "hours" (optional, defaults to "ms")

  Schedule mode:
  - schedule_at: ISO8601 datetime string when to resume (required)
  - timezone: Timezone for schedule_at (optional, defaults to "UTC")

  Webhook mode:
  - timeout_hours: Hours until webhook expires (optional, defaults to 24)
  - webhook_config: Additional webhook configuration (optional)

  Common parameters:
  - pass_through: Whether to pass input data to output (optional, defaults to true)

  Returns:
  - {:suspend, :interval | :schedule | :webhook, suspend_data} to suspend execution
  - {:error, reason, "error"} if configuration is invalid
  """
  def wait(input_map) do
    mode = Map.get(input_map, "mode")

    case mode do
      "interval" -> wait_interval(input_map)
      "schedule" -> wait_schedule(input_map)
      "webhook" -> wait_webhook(input_map)
      nil -> {:error, %{type: "config_error", message: "mode is required"}, "error"}
      _ -> {:error, %{type: "config_error", message: "mode must be 'interval', 'schedule', or 'webhook'"}, "error"}
    end
  end

  @doc """
  Wait interval mode - suspend execution for a specified duration
  """
  def wait_interval(input_map) do
    duration = Map.get(input_map, "duration")
    unit = Map.get(input_map, "unit", "ms")
    pass_through = Map.get(input_map, "pass_through", true)

    with :ok <- validate_duration(duration),
         :ok <- validate_unit(unit),
         {:ok, duration_ms} <- convert_to_milliseconds(duration, unit) do
      interval_data = %{
        mode: "interval",
        duration_ms: duration_ms,
        started_at: DateTime.utc_now(),
        resume_at: DateTime.add(DateTime.utc_now(), duration_ms, :millisecond),
        input_data: if(pass_through, do: input_map, else: %{}),
        pass_through: pass_through
      }

      {:suspend, :interval, interval_data}
    else
      {:error, reason} ->
        {:error, %{type: "interval_config_error", message: reason}, "error"}
    end
  end

  @doc """
  Wait schedule mode - suspend execution until a specific datetime
  """
  def wait_schedule(input_map) do
    schedule_at = Map.get(input_map, "schedule_at")
    timezone = Map.get(input_map, "timezone", "UTC")
    pass_through = Map.get(input_map, "pass_through", true)

    with :ok <- validate_schedule_at(schedule_at),
         {:ok, schedule_datetime} <- parse_schedule_datetime(schedule_at, timezone),
         :ok <- validate_schedule_future(schedule_datetime) do
      now = DateTime.utc_now()
      duration_ms = DateTime.diff(schedule_datetime, now, :millisecond)

      schedule_data = %{
        mode: "schedule",
        schedule_at: schedule_datetime,
        timezone: timezone,
        duration_ms: duration_ms,
        started_at: now,
        input_data: if(pass_through, do: input_map, else: %{}),
        pass_through: pass_through
      }

      {:suspend, :schedule, schedule_data}
    else
      {:error, reason} ->
        {:error, %{type: "schedule_config_error", message: reason}, "error"}
    end
  end

  @doc """
  Wait webhook mode - suspend execution until webhook is received
  """
  def wait_webhook(input_map) do
    timeout_hours = Map.get(input_map, "timeout_hours", 24)
    webhook_config = Map.get(input_map, "webhook_config", %{})
    pass_through = Map.get(input_map, "pass_through", true)

    case validate_timeout_hours(timeout_hours) do
      :ok ->
        now = DateTime.utc_now()
        expires_at = DateTime.add(now, timeout_hours * 3600, :second)

        webhook_data = %{
          mode: "webhook",
          timeout_hours: timeout_hours,
          webhook_config: webhook_config,
          started_at: now,
          expires_at: expires_at,
          input_data: if(pass_through, do: input_map, else: %{}),
          pass_through: pass_through
        }

        {:suspend, :webhook, webhook_data}

      {:error, reason} ->
        {:error, %{type: "webhook_config_error", message: reason}, "error"}
    end
  end

  # ============================================================================
  # Private Helper Functions
  # ============================================================================

  # Validate duration parameter
  defp validate_duration(nil), do: {:error, "duration/timeout is required"}
  defp validate_duration(duration) when is_integer(duration) and duration > 0, do: :ok
  defp validate_duration(duration) when is_float(duration) and duration > 0, do: :ok
  defp validate_duration(_), do: {:error, "duration/timeout must be a positive number"}

  # Validate unit parameter
  defp validate_unit(unit) when unit in ["ms", "seconds", "minutes", "hours"], do: :ok
  defp validate_unit(_), do: {:error, "unit must be 'ms', 'seconds', 'minutes', or 'hours'"}

  # Convert duration to milliseconds
  defp convert_to_milliseconds(duration, "ms"), do: {:ok, trunc(duration)}
  defp convert_to_milliseconds(duration, "seconds"), do: {:ok, trunc(duration * 1000)}
  defp convert_to_milliseconds(duration, "minutes"), do: {:ok, trunc(duration * 60 * 1000)}
  defp convert_to_milliseconds(duration, "hours"), do: {:ok, trunc(duration * 60 * 60 * 1000)}

  # Validate schedule_at parameter
  defp validate_schedule_at(nil), do: {:error, "schedule_at is required"}
  defp validate_schedule_at(schedule_at) when is_binary(schedule_at), do: :ok
  defp validate_schedule_at(_), do: {:error, "schedule_at must be an ISO8601 datetime string"}

  # Parse schedule datetime with timezone support
  defp parse_schedule_datetime(schedule_at, timezone) do
    case DateTime.from_iso8601(schedule_at) do
      {:ok, datetime, _offset} ->
        # Convert to UTC if needed
        case timezone do
          "UTC" ->
            {:ok, datetime}

          tz when is_binary(tz) ->
            # For now, just use UTC. In production, you'd use a timezone library
            {:ok, datetime}
        end

      {:error, reason} ->
        {:error, "Invalid datetime format: #{inspect(reason)}"}
    end
  end

  # Validate schedule is in the future
  defp validate_schedule_future(schedule_datetime) do
    now = DateTime.utc_now()

    if DateTime.after?(schedule_datetime, now) do
      :ok
    else
      {:error, "schedule_at must be in the future"}
    end
  end

  # Validate timeout_hours parameter
  defp validate_timeout_hours(timeout_hours)
       when is_number(timeout_hours) and timeout_hours > 0 and timeout_hours <= 8760 do
    :ok
  end

  defp validate_timeout_hours(_) do
    {:error, "timeout_hours must be a positive number between 1 and 8760 (1 year)"}
  end
end

defmodule Prana.Integrations.Wait.WaitAction do
  @moduledoc """
  Wait action implementation using Action behavior
  """
  
  use Prana.Actions.SimpleAction

  @impl true
  def execute(input_map) do
    case Prana.Integrations.Wait.wait(input_map) do
      {:suspend, suspension_type, suspension_data} ->
        {:suspend, suspension_type, suspension_data}
      {:error, reason, output_port} ->
        {:error, reason, output_port}
      {:ok, result, output_port} ->
        {:ok, result, output_port}
      {:ok, result} ->
        {:ok, result, "success"}
    end
  end
end
