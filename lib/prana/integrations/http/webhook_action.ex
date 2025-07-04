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
      webhook_path: Map.get(config, "webhook_path", "/webhook"),
      prepared_at: DateTime.utc_now()
    }

    {:ok, preparation_data}
  end

  @impl true
  def execute(input_map) do
    webhook_config = Map.get(input_map, "webhook_config", %{})

    now = DateTime.utc_now()

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
      webhook_config: webhook_config,
      started_at: now,
      webhook_url: webhook_url,
      input_data: input_map
    }

    {:suspend, :webhook, suspend_data}
  end

  @impl true
  def resume(suspend_data, resume_input) do
    # Return webhook payload
    {:ok,
     %{
       webhook_payload: resume_input,
       received_at: DateTime.utc_now(),
       original_input: Map.get(suspend_data, :input_data, %{})
     }}
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

end
