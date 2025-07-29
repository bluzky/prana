defmodule Editor.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      EditorWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:editor, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Editor.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: Editor.Finch},
      # Start Prana IntegrationRegistry
      Prana.IntegrationRegistry,
      # Start a worker by calling: Editor.Worker.start_link(arg)
      # {Editor.Worker, arg},
      # Start to serve requests, typically the last entry
      EditorWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Editor.Supervisor]
    result = Supervisor.start_link(children, opts)
    
    # Register integrations after supervisor starts
    Task.start(fn -> 
      Process.sleep(100)  # Give registry time to start
      register_integrations()
    end)
    
    result
  end

  defp register_integrations do
    require Logger

    Logger.info("Registering built-in integrations")

    # Register all the built-in integrations
    integrations = [
      Prana.Integrations.Manual,
      Prana.Integrations.Logic,
      Prana.Integrations.Data,
      Prana.Integrations.Workflow
    ]

    Enum.each(integrations, fn integration_module ->
      # Ensure the module is loaded
      case Code.ensure_loaded(integration_module) do
        {:module, ^integration_module} ->
          case Prana.IntegrationRegistry.register_integration(integration_module) do
            :ok ->
              Logger.debug("Registered integration: #{integration_module}")

            {:error, reason} ->
              Logger.warning("Failed to register integration #{integration_module}: #{inspect(reason)}")
          end

        {:error, reason} ->
          Logger.warning("Failed to load integration module #{integration_module}: #{inspect(reason)}")
      end
    end)

    :ok
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    EditorWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
