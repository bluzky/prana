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

  alias Prana.Integration
  alias Prana.Integrations.HTTP.RequestAction
  alias Prana.Integrations.HTTP.WebhookAction

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
        "request" => RequestAction.specification(),
        "webhook" => WebhookAction.specification()
      }
    }
  end
end
