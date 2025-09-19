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
  alias Prana.Core.Error
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
      actions: [Prana.Integrations.Wait.WaitAction]
    }
  end

  @doc """
  Unified wait action - supports multiple wait modes

  Expected params:
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
  - (none)

  Returns:
  - {:suspend, :interval | :schedule | :webhook, suspension_data} to suspend execution
  - {:error, reason, "error"} if configuration is invalid
  """
  def wait(params) do
    mode = Map.get(params, "mode")

    case mode do
      "interval" -> wait_interval(params)
      "schedule" -> wait_schedule(params)
      "webhook" -> wait_webhook(params)
      nil -> {:error, Error.action_error("config_error", "mode is required"), "error"}
      _ -> {:error, Error.action_error("config_error", "mode must be 'interval', 'schedule', or 'webhook'"), "error"}
    end
  end

  @doc """
  Wait interval mode - suspend execution for a specified duration
  """
  def wait_interval(params) do
    duration = Map.get(params, "duration")
    unit = Map.get(params, "unit", "ms")

    with :ok <- validate_duration(duration),
         :ok <- validate_unit(unit),
         {:ok, duration_ms} <- convert_to_milliseconds(duration, unit) do
      # if duration < 60 then sleep, otherwise return suspend
      now = DateTime.utc_now()

      if duration_ms < 60_000 do
        Process.sleep(duration_ms)
        {:ok, %{}, "main"}
      else
        interval_data = %{
          "mode" => "interval",
          "resume_at" => DateTime.add(now, duration_ms, :millisecond)
        }

        {:suspend, :interval, interval_data}
      end
    else
      {:error, reason} ->
        {:error, Error.action_error("interval_config_error", reason), "error"}
    end
  end

  @doc """
  Wait schedule mode - suspend execution until a specific datetime
  """
  def wait_schedule(params) do
    schedule_at = Map.get(params, "schedule_at")
    timezone = Map.get(params, "timezone", "UTC")

    with :ok <- validate_schedule_at(schedule_at),
         {:ok, schedule_datetime} <- parse_schedule_datetime(schedule_at, timezone),
         :ok <- validate_schedule_future(schedule_datetime) do
      schedule_data = %{
        "mode" => "schedule",
        "resume_at" => schedule_datetime,
        "timezone" => timezone
      }

      {:suspend, :schedule, schedule_data}
    else
      {:error, reason} ->
        {:error, Error.action_error("schedule_config_error", reason), "error"}
    end
  end

  @doc """
  Wait webhook mode - suspend execution until webhook is received
  """
  def wait_webhook(params) do
    timeout_hours = Map.get(params, "timeout_hours", 24)

    case validate_timeout_hours(timeout_hours) do
      :ok ->
        now = DateTime.utc_now()
        expires_at = DateTime.add(now, timeout_hours * 3600, :second)

        webhook_data = %{
          "mode" => "webhook",
          "expires_at" => expires_at,
          "timeout_hours" => timeout_hours
        }

        {:suspend, :webhook, webhook_data}

      {:error, reason} ->
        {:error, Error.action_error("webhook_config_error", reason), "error"}
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
  Wait action implementation using Action behavior with webhook prepare/resume support
  """

  @behaviour Prana.Behaviour.Action

  alias Prana.Action

  def definition do
    %Action{
      name: "wait.wait",
      display_name: "Wait",
      description: "Unified wait action supporting multiple modes: interval, schedule, webhook",
      type: :wait,
      input_ports: ["main"],
      output_ports: ["main", "timeout", "error"]
    }
  end

  @impl true
  def prepare(node) do
    case Map.get(node.params, "mode") do
      "webhook" -> prepare_webhook(node.params)
      _ -> {:ok, nil}
    end
  end

  @impl true
  def execute(params, _context) do
    case Prana.Integrations.Wait.wait(params) do
      {:suspend, suspension_type, suspension_data} ->
        {:suspend, suspension_type, suspension_data}

      {:error, reason, output_port} ->
        {:error, reason, output_port}

      {:ok, result, output_port} ->
        {:ok, result, output_port}

      {:ok, result} ->
        {:ok, result, "main"}
    end
  end

  @impl true
  def resume(_params, _context, resume_data) do
    {:ok, resume_data, "main"}
  end

  # Webhook mode preparation - generates resume URLs
  defp prepare_webhook(params) do
    timeout_hours = Map.get(params, "timeout_hours", 24)
    base_url = System.get_env("PRANA_BASE_URL")

    case validate_webhook_prepare_config(timeout_hours, base_url) do
      :ok ->
        execution_id = "# TODO"
        webhook_url = "#{base_url}/resume/#{execution_id}"

        preparation_data = %{
          webhook_url: webhook_url,
          timeout_hours: timeout_hours
        }

        {:ok, preparation_data}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Validation helpers
  defp validate_webhook_prepare_config(timeout_hours, _base_url) do
    if is_number(timeout_hours) and timeout_hours > 0 and timeout_hours <= 8760 do
      :ok
    else
      {:error, "timeout_hours must be a positive number between 1 and 8760 (1 year)"}
    end
  end
end
