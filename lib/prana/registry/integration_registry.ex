defmodule Prana.IntegrationRegistry do
  @moduledoc """
  Registry for managing integrations and their available actions.
  Supports runtime registration and discovery of integrations.
  """

  use GenServer

  require Logger

  defstruct [:integrations]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register an integration module
  """
  def register_integration(integration_module) when is_atom(integration_module) do
    GenServer.call(__MODULE__, {:register_integration, integration_module})
  end

  @doc """
  Get an action definition by integration and action name
  """
  def get_action(integration_name, action_name) do
    GenServer.call(__MODULE__, {:get_action, integration_name, action_name})
  end

  @doc """
  List all registered integrations
  """
  def list_integrations do
    GenServer.call(__MODULE__, :list_integrations)
  end

  @doc """
  Get complete integration definition
  """
  def get_integration(integration_name) do
    GenServer.call(__MODULE__, {:get_integration, integration_name})
  end

  @doc """
  Unregister an integration
  """
  def unregister_integration(integration_name) do
    GenServer.call(__MODULE__, {:unregister_integration, integration_name})
  end

  @doc """
  Check if an integration is registered
  """
  def integration_registered?(integration_name) do
    GenServer.call(__MODULE__, {:integration_registered?, integration_name})
  end

  @doc """
  Get registry statistics
  """
  def get_statistics do
    GenServer.call(__MODULE__, :get_statistics)
  end

  @doc """
  Health check for all registered integrations
  """
  def health_check do
    GenServer.call(__MODULE__, :health_check, 10_000)
  end

  # GenServer callbacks

  @impl GenServer
  def init(_opts) do
    state = %__MODULE__{
      integrations: %{}
    }

    Logger.info("Started Prana Integration Registry")
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:register_integration, module}, _from, state) do
    case register_integration_module(module, state) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:get_action, integration_name, action_name}, _from, state) do
    result = get_action_from_state(state, integration_name, action_name)
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:get_integration, integration_name}, _from, state) do
    result =
      case Map.get(state.integrations, integration_name) do
        nil -> {:error, :not_found}
        %Prana.Integration{} = integration -> {:ok, integration}
      end

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call(:list_integrations, _from, state) do
    integrations =
      Enum.map(state.integrations, fn {_name, %Prana.Integration{} = integration} ->
        %{
          name: integration.name,
          display_name: integration.display_name,
          description: integration.description,
          category: integration.category,
          version: integration.version,
          action_count: map_size(integration.actions)
        }
      end)

    {:reply, integrations, state}
  end

  @impl GenServer
  def handle_call({:unregister_integration, integration_name}, _from, state) do
    new_integrations = Map.delete(state.integrations, integration_name)
    new_state = %{state | integrations: new_integrations}

    Logger.info("Unregistered integration: #{integration_name}")
    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_call({:integration_registered?, integration_name}, _from, state) do
    result = Map.has_key?(state.integrations, integration_name)
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call(:get_statistics, _from, state) do
    stats = %{
      total_integrations: map_size(state.integrations),
      total_actions:
        state.integrations
        |> Enum.map(fn {_name, %Prana.Integration{actions: actions}} -> map_size(actions) end)
        |> Enum.sum(),
      integrations_by_category:
        state.integrations
        |> Enum.group_by(fn {_name, %Prana.Integration{category: category}} -> category end)
        |> Map.new(fn {category, integrations} -> {category, length(integrations)} end)
    }

    {:reply, {:ok, stats}, state}
  end

  @impl GenServer
  def handle_call(:health_check, _from, state) do
    results =
      Map.new(state.integrations, fn {name, %Prana.Integration{} = integration} ->
        case check_integration_health(integration) do
          :ok -> {name, :ok}
          {:error, reason} -> {name, {:error, reason}}
        end
      end)

    overall_health =
      if Enum.all?(results, fn {_name, status} -> status == :ok end) do
        :ok
      else
        {:error, "Some integrations are unhealthy"}
      end

    {:reply, {overall_health, results}, state}
  end

  # Private functions

  defp register_integration_module(module, state) do
    if function_exported?(module, :definition, 0) do
      integration = module.definition()

      case integration do
        %Prana.Integration{} = integration ->
          new_integrations = Map.put(state.integrations, integration.name, integration)
          new_state = %{state | integrations: new_integrations}

          Logger.info(
            "Registered integration: #{integration.name} (#{module}) with #{map_size(integration.actions)} actions"
          )

          {:ok, new_state}

        _ ->
          {:error, "Module #{module} definition/0 must return %Prana.Integration{} struct"}
      end
    else
      {:error, "Module #{module} does not implement Prana.Behaviour.Integration"}
    end
  rescue
    error ->
      Logger.error("Error registering integration #{module}: #{inspect(error)}")
      {:error, "Registration failed: #{inspect(error)}"}
  end

  defp get_action_from_state(state, integration_name, action_name) do
    case get_in(state.integrations, [integration_name, Access.key(:actions), action_name]) do
      %Prana.Action{} = action -> {:ok, action}
      nil -> {:error, :not_found}
    end
  end

  defp check_integration_health(%Prana.Integration{actions: actions}) do
    # Check if all action modules implement the Action behavior
    invalid_actions =
      Enum.reject(actions, fn {_name, %Prana.Action{module: module}} ->
        function_exported?(module, :execute, 1)
      end)

    if Enum.empty?(invalid_actions) do
      :ok
    else
      action_names = Enum.map(invalid_actions, fn {name, _action} -> name end)
      {:error, "Actions with missing execute/1 function: #{inspect(action_names)}"}
    end
  end
end
