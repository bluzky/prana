defmodule Prana.Behaviour.Integration do
  @moduledoc """
  Behavior for integrations. Each integration provides multiple actions
  and defines their capabilities.

  ## Example Implementation

      defmodule MyApp.SlackIntegration do
        @behaviour Prana.Behaviour.Integration

        @impl Prana.Behaviour.Integration
        def definition do
          %Prana.Integration{
            name: "slack",
            display_name: "Slack",
            description: "Send messages to Slack channels",
            version: "1.0.0",
            category: "communication",
            actions: %{
              "send_message" => %Prana.Action{
                name: "send_message",
                display_name: "Send Message",
                description: "Send a message to a Slack channel",
                module: __MODULE__,
                function: :send_message,
                input_ports: ["input"],
                output_ports: ["success", "error"],
                
     
              }
            }
          }
        end

        # Action implementation
        def send_message(input) do
          # Implementation here...
          {:ok, %{message_id: "123", timestamp: DateTime.utc_now()}}
        end
      end

  ## Registration

      Prana.IntegrationRegistry.register_integration(MyApp.SlackIntegration)

  """

  @doc """
  Returns the complete integration definition.

  Action functions should return:
  - `{:ok, output}` - Success with default success port
  - `{:ok, output, port}` - Success with explicit port
  - `{:error, error}` - Error with default error port
  - `{:error, error, port}` - Error with explicit port
  """
  @callback definition() :: Prana.Integration.t()
end
