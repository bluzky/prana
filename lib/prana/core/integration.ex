defmodule Prana.Integration do
  @moduledoc """
  Represents an integration definition with its metadata and available actions.

  ## Example

      %Prana.Integration{
        name: "slack",
        display_name: "Slack",
        description: "Send messages and manage Slack channels",
        version: "1.0.0",
        category: "communication",
        actions: %{
          "send_message" => %Prana.Action{
            name: "send_message",
            display_name: "Send Message",
            description: "Send a message to a Slack channel",
            module: MyApp.SlackSendMessageAction,
            input_ports: ["input"],
            output_ports: ["success", "error"],
            default_success_port: "success",
            default_error_port: "error",
            input_schema: %{
              type: "object",
              required: ["channel", "message"],
              properties: %{
                channel: %{type: "string"},
                message: %{type: "string"}
              }
            },
            examples: [
              %{
                name: "Send to general channel",
                input: %{channel: "#general", message: "Hello world!"}
              }
            ]
          }
        },
        metadata: %{
          author: "MyApp Team",
          docs_url: "https://docs.myapp.com/integrations/slack"
        }
      }

  """

  @type t :: %__MODULE__{
          name: String.t(),
          display_name: String.t(),
          description: String.t(),
          version: String.t(),
          category: String.t(),
          actions: %{String.t() => Prana.Action.t()},
          metadata: map()
        }

  defstruct [
    :name,
    :display_name,
    :description,
    :version,
    :category,
    :actions,
    metadata: %{}
  ]
end
