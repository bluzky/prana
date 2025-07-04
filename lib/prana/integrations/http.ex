defmodule Prana.Integrations.HTTP do
  @moduledoc """
  HTTP Integration - Provides HTTP request actions and webhook triggers

  Supports:
  - HTTP requests with GET, POST, PUT, DELETE methods
  - Request configuration (headers, body, timeout, authentication)
  - Response handling with success/error/timeout port routing
  - Webhook triggers for incoming HTTP requests
  - Comprehensive error handling for network and HTTP errors

  This integration uses Req HTTP client for modern, performant HTTP operations.
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
      name: "http",
      display_name: "HTTP",
      description: "HTTP requests and webhook handling",
      version: "1.0.0",
      category: "network",
      actions: %{
        "request" => %Action{
          name: "request",
          display_name: "HTTP Request",
          description: "Make HTTP requests with configurable method, headers, and body",
          module: Prana.Integrations.HTTP.RequestAction,
          input_ports: ["input"],
          output_ports: ["success", "error", "timeout"],
          default_success_port: "success",
          default_error_port: "error"
        },
        "webhook" => %Action{
          name: "webhook",
          display_name: "Webhook Trigger",
          description: "Wait for incoming HTTP webhook requests",
          module: Prana.Integrations.HTTP.WebhookAction,
          input_ports: ["input"],
          output_ports: ["success", "error"],
          default_success_port: "success",
          default_error_port: "error"
        }
      }
    }
  end
end
