defmodule PranaDemo.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      PranaDemo.ETSStorage,
      Prana.IntegrationRegistry
    ]

    # Start the supervisor
    result = Supervisor.start_link(children, strategy: :one_for_one, name: PranaDemo.Supervisor)
    
    # Register integrations after the registry is started
    register_integrations()
    
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
      Prana.Integrations.Workflow,
      Prana.Integrations.Wait,
      Prana.Integrations.HTTP
    ]

    Enum.each(integrations, fn integration_module ->
      # Ensure the module is loaded
      case Code.ensure_loaded(integration_module) do
        {:module, ^integration_module} ->
          case Prana.IntegrationRegistry.register_integration(integration_module) do
            :ok ->
              Logger.debug("Registered integration: #{integration_module}")

            {:error, reason} ->
              Logger.warning(
                "Failed to register integration #{integration_module}: #{inspect(reason)}"
              )
          end

        {:error, reason} ->
          Logger.warning(
            "Failed to load integration module #{integration_module}: #{inspect(reason)}"
          )
      end
    end)

    :ok
  end
end
