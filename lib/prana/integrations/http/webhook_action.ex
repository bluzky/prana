defmodule Prana.Integrations.HTTP.WebhookAction do
  @moduledoc """
  Webhook action implementation using Action behavior with suspend/resume pattern

  Suspends execution and waits for incoming HTTP webhook requests.
  """

  @behaviour Prana.Behaviour.Action

  use Skema

  defschema WebhookConfigSchema do
    field(:path, :string, default: "/webhook")
    field(:secret, :string)
    field(:headers, :map, default: %{})
  end

  defschema WebhookSchema do
    field(:timeout_hours, :float,
      default: 24.0,
      number: [min: 0.1, max: 8760.0]
    )

    field(:base_url, :string, format: ~r/^https?:\/\/.+/)

    field(:webhook_config, WebhookConfigSchema, default: %{})
  end

  @impl true
  def input_schema, do: WebhookSchema

  @impl true
  def validate_input(input_map) do
    case Skema.cast_and_validate(input_map, WebhookSchema) do
      {:ok, validated_data} -> {:ok, validated_data}
      {:error, errors} -> {:error, format_errors(errors)}
    end
  end

  @impl true
  def prepare(node) do
    # Webhook preparation could include URL generation
    config = Map.get(node, :config, %{})

    preparation_data = %{
      timeout_hours: Map.get(config, "timeout_hours", 24),
      webhook_path: Map.get(config, "webhook_path", "/webhook"),
      prepared_at: DateTime.utc_now()
    }

    {:ok, preparation_data}
  end

  @impl true
  def execute(input_map) do
    timeout_hours = Map.get(input_map, "timeout_hours", 24)
    webhook_config = Map.get(input_map, "webhook_config", %{})

    case validate_webhook_config(timeout_hours, webhook_config) do
      :ok ->
        now = DateTime.utc_now()
        expires_at = DateTime.add(now, timeout_hours * 3600, :second)

        # Build webhook URL if base_url provided
        webhook_url =
          case Map.get(input_map, "base_url") do
            nil ->
              nil

            base_url ->
              webhook_path = Map.get(webhook_config, "path", "/webhook")
              "#{base_url}#{webhook_path}"
          end

        suspend_data = %{
          mode: "webhook",
          timeout_hours: timeout_hours,
          webhook_config: webhook_config,
          started_at: now,
          expires_at: expires_at,
          webhook_url: webhook_url,
          input_data: input_map
        }

        {:suspend, :webhook, suspend_data}

      {:error, reason} ->
        {:error, %{type: "webhook_config_error", message: reason}, "error"}
    end
  end

  @impl true
  def resume(suspend_data, resume_input) do
    expires_at = Map.get(suspend_data, :expires_at)

    # Check if webhook has expired
    if expires_at && DateTime.after?(DateTime.utc_now(), expires_at) do
      {:error, %{type: "webhook_timeout", message: "Webhook has expired"}}
    else
      # Return webhook payload
      {:ok,
       %{
         webhook_payload: resume_input,
         received_at: DateTime.utc_now(),
         original_input: Map.get(suspend_data, :input_data, %{})
       }}
    end
  end

  @impl true
  def suspendable?, do: true

  # Format validation errors
  defp format_errors(errors) do
    Enum.map(errors, fn
      {field, messages} when is_list(messages) ->
        "#{field}: #{Enum.join(messages, ", ")}"

      {field, message} when is_binary(message) ->
        "#{field}: #{message}"

      {field, message} ->
        "#{field}: #{inspect(message)}"
    end)
  end

  # Validate webhook configuration
  defp validate_webhook_config(timeout_hours, _webhook_config) do
    if is_number(timeout_hours) and timeout_hours > 0 and timeout_hours <= 8760 do
      :ok
    else
      {:error, "timeout_hours must be a positive number between 1 and 8760 (1 year)"}
    end
  end
end
