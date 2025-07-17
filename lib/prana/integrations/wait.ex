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
        "wait" => Prana.Integrations.Wait.WaitAction.specification()
      }
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
  - {:suspend, :interval | :schedule | :webhook, suspend_data} to suspend execution
  - {:error, reason, "error"} if configuration is invalid
  """
  def wait(params) do
    mode = Map.get(params, "mode")

    case mode do
      "interval" -> wait_interval(params)
      "schedule" -> wait_schedule(params)
      "webhook" -> wait_webhook(params)
      nil -> {:error, %{type: "config_error", message: "mode is required"}, "error"}
      _ -> {:error, %{type: "config_error", message: "mode must be 'interval', 'schedule', or 'webhook'"}, "error"}
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
      if duration_ms < 60_000 do
        # If duration is less than 60 seconds, we can just sleep
        Process.sleep(duration_ms)
        {:ok, %{}}
      else
        interval_data = %{
          mode: "interval",
          duration_ms: duration_ms,
          started_at: DateTime.utc_now(),
          resume_at: DateTime.add(DateTime.utc_now(), duration_ms, :millisecond)
        }

        {:suspend, :interval, interval_data}
      end
    else
      {:error, reason} ->
        {:error, %{type: "interval_config_error", message: reason}, "error"}
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
      now = DateTime.utc_now()
      duration_ms = DateTime.diff(schedule_datetime, now, :millisecond)

      schedule_data = %{
        mode: "schedule",
        schedule_at: schedule_datetime,
        timezone: timezone,
        duration_ms: duration_ms,
        started_at: now
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
  def wait_webhook(params) do
    timeout_hours = Map.get(params, "timeout_hours", 24)
    webhook_config = Map.get(params, "webhook_config", %{})

    case validate_timeout_hours(timeout_hours) do
      :ok ->
        now = DateTime.utc_now()
        expires_at = DateTime.add(now, timeout_hours * 3600, :second)

        # Try to get preparation data for webhook URLs
        preparation_data = Map.get(params, "$preparation", %{})
        current_node_preparation = get_current_node_preparation(params, preparation_data)

        webhook_data = %{
          mode: "webhook",
          timeout_hours: timeout_hours,
          webhook_config: webhook_config,
          started_at: now,
          expires_at: expires_at,
          resume_id: Map.get(current_node_preparation, :resume_id),
          webhook_url: Map.get(current_node_preparation, :webhook_url)
        }

        {:suspend, :webhook, webhook_data}

      {:error, reason} ->
        {:error, %{type: "webhook_config_error", message: reason}, "error"}
    end
  end

  # ============================================================================
  # Private Helper Functions
  # ============================================================================

  # Get preparation data for current node
  defp get_current_node_preparation(params, preparation_data) do
    # Try to determine current node ID from context
    # This could be from a custom_id field or node_id in the input
    node_id = Map.get(params, "node_id") || Map.get(params, "custom_id") || "current_node"

    case Map.get(preparation_data, node_id) do
      nil -> %{}
      prep_data when is_map(prep_data) -> prep_data
      _ -> %{}
    end
  end

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

  def specification do
    %Action{
      name: "wait",
      display_name: "Wait",
      description: "Unified wait action supporting multiple modes: interval, schedule, webhook",
      type: :wait,
      module: __MODULE__,
      input_ports: ["main"],
      output_ports: ["main", "timeout", "error"]
    }
  end

  @impl true
  def prepare(node) do
    mode = Map.get(node.params, "mode")

    case mode do
      "webhook" -> prepare_webhook(node.params)
      "interval" -> prepare_interval(node.params)
      "schedule" -> prepare_schedule(node.params)
      nil -> {:error, "mode is required"}
      _ -> {:error, "mode must be 'interval', 'schedule', or 'webhook'"}
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
  def resume(params, _context, resume_data) do
    mode = Map.get(params, "mode")

    case mode do
      "webhook" -> resume_webhook(params, resume_data)
      "interval" -> resume_interval(params, resume_data)
      "schedule" -> resume_schedule(params, resume_data)
      _ -> {:error, "Unknown suspension mode: #{inspect(mode)}"}
    end
  end

  # Webhook mode preparation - generates resume URLs
  defp prepare_webhook(params) do
    timeout_hours = Map.get(params, "timeout_hours", 24)
    webhook_config = Map.get(params, "webhook_config", %{})
    base_url = Map.get(params, "base_url")

    case validate_webhook_prepare_config(timeout_hours, base_url) do
      :ok ->
        # Access execution context through the enriched input
        execution_id = get_context_value(params, "$execution.id", "unknown_execution")

        # Generate unique resume ID for this webhook
        resume_id = Prana.Webhook.generate_resume_id(execution_id)

        # Build webhook URL if base_url provided
        webhook_url =
          if base_url do
            Prana.Webhook.build_webhook_url(base_url, :resume, resume_id)
          end

        preparation_data = %{
          resume_id: resume_id,
          webhook_url: webhook_url,
          timeout_hours: timeout_hours,
          webhook_config: webhook_config,
          execution_id: execution_id,
          prepared_at: DateTime.utc_now()
        }

        {:ok, preparation_data}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Interval mode preparation - calculates timing
  defp prepare_interval(params) do
    duration = Map.get(params, "duration")
    unit = Map.get(params, "unit", "ms")

    case validate_interval_config(duration, unit) do
      {:ok, duration_ms} ->
        now = DateTime.utc_now()
        resume_at = DateTime.add(now, duration_ms, :millisecond)

        preparation_data = %{
          mode: "interval",
          duration_ms: duration_ms,
          resume_at: resume_at,
          prepared_at: now
        }

        {:ok, preparation_data}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Schedule mode preparation - validates and parses schedule
  defp prepare_schedule(params) do
    schedule_at = Map.get(params, "schedule_at")
    timezone = Map.get(params, "timezone", "UTC")

    case validate_schedule_config(schedule_at, timezone) do
      {:ok, schedule_datetime} ->
        now = DateTime.utc_now()
        duration_ms = DateTime.diff(schedule_datetime, now, :millisecond)

        preparation_data = %{
          mode: "schedule",
          schedule_at: schedule_datetime,
          timezone: timezone,
          duration_ms: duration_ms,
          prepared_at: now
        }

        {:ok, preparation_data}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Resume webhook mode - process webhook data
  defp resume_webhook(_params, resume_data) do
    # For webhook mode, we'd need to check expiration based on original start time
    # For now, just return the resume data
    {:ok, resume_data}
  end

  # Resume interval mode - validate timing
  defp resume_interval(_params, _resume_data) do
    # For interval mode, timing is handled by the scheduler
    # Just return success when resumed
    {:ok, %{}}
  end

  # Resume schedule mode - validate timing
  defp resume_schedule(_params, _resume_data) do
    # For schedule mode, timing is handled by the scheduler
    # Just return success when resumed
    {:ok, %{}}
  end

  # Helper to safely get context values from enriched input
  defp get_context_value(params, path, default) do
    case String.split(path, ".", parts: 2) do
      ["$execution", field] ->
        case Map.get(params, "$execution") do
          nil -> default
          execution_context -> Map.get(execution_context, field, default)
        end

      _ ->
        Map.get(params, path, default)
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

  defp validate_interval_config(duration, unit) do
    with :ok <- validate_duration(duration),
         :ok <- validate_unit(unit) do
      convert_to_milliseconds(duration, unit)
    end
  end

  defp validate_schedule_config(schedule_at, timezone) do
    with :ok <- validate_schedule_at(schedule_at),
         {:ok, schedule_datetime} <- parse_schedule_datetime(schedule_at, timezone),
         :ok <- validate_schedule_future(schedule_datetime) do
      {:ok, schedule_datetime}
    end
  end

  # Reuse existing validation functions from main module
  defp validate_duration(nil), do: {:error, "duration is required"}
  defp validate_duration(duration) when is_integer(duration) and duration > 0, do: :ok
  defp validate_duration(duration) when is_float(duration) and duration > 0, do: :ok
  defp validate_duration(_), do: {:error, "duration must be a positive number"}

  defp validate_unit(unit) when unit in ["ms", "seconds", "minutes", "hours"], do: :ok
  defp validate_unit(_), do: {:error, "unit must be 'ms', 'seconds', 'minutes', or 'hours'"}

  defp convert_to_milliseconds(duration, "ms"), do: {:ok, trunc(duration)}
  defp convert_to_milliseconds(duration, "seconds"), do: {:ok, trunc(duration * 1000)}
  defp convert_to_milliseconds(duration, "minutes"), do: {:ok, trunc(duration * 60 * 1000)}
  defp convert_to_milliseconds(duration, "hours"), do: {:ok, trunc(duration * 60 * 60 * 1000)}

  defp validate_schedule_at(nil), do: {:error, "schedule_at is required"}
  defp validate_schedule_at(schedule_at) when is_binary(schedule_at), do: :ok
  defp validate_schedule_at(_), do: {:error, "schedule_at must be an ISO8601 datetime string"}

  defp parse_schedule_datetime(schedule_at, timezone) do
    case DateTime.from_iso8601(schedule_at) do
      {:ok, datetime, _offset} ->
        case timezone do
          "UTC" -> {:ok, datetime}
          # For now, just use UTC
          tz when is_binary(tz) -> {:ok, datetime}
        end

      {:error, reason} ->
        {:error, "Invalid datetime format: #{inspect(reason)}"}
    end
  end

  defp validate_schedule_future(schedule_datetime) do
    if DateTime.after?(schedule_datetime, DateTime.utc_now()) do
      :ok
    else
      {:error, "schedule_at must be in the future"}
    end
  end
end
