defmodule Prana.IntegrationRegistry do
  @moduledoc """
  Registry for managing integrations and their available actions.
  Supports runtime registration and discovery of integrations.
  """

  use GenServer

  require Logger

  defstruct [:integrations, :config]

  @type integration_definition :: %{
          name: String.t(),
          display_name: String.t(),
          description: String.t(),
          version: String.t(),
          category: String.t(),
          actions: %{String.t() => action_definition()}
        }

  @type action_definition :: %{
          name: String.t(),
          display_name: String.t(),
          description: String.t(),
          module: atom(),
          function: atom(),
          input_ports: [String.t()],
          output_ports: [String.t()],
          default_success_port: String.t(),
          default_error_port: String.t(),
          input_schema: map() | nil,
          output_schema: map() | nil,
          examples: [map()],
          metadata: map()
        }

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
  Register an integration with explicit definition
  """
  def register_integration(integration_name, definition) when is_binary(integration_name) do
    GenServer.call(__MODULE__, {:register_integration_def, integration_name, definition})
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
  List all actions for a specific integration
  """
  def list_actions(integration_name) do
    GenServer.call(__MODULE__, {:list_actions, integration_name})
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
  def init(opts) do
    config = Keyword.get(opts, :config, %{})

    state = %__MODULE__{
      integrations: %{},
      config: config
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
  def handle_call({:register_integration_def, name, definition}, _from, state) do
    case register_integration_definition(name, definition, state) do
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
        integration -> {:ok, integration}
      end

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call(:list_integrations, _from, state) do
    integrations =
      Enum.map(state.integrations, fn {name, definition} ->
        %{
          name: name,
          display_name: definition.display_name,
          description: definition.description,
          category: definition.category,
          version: definition.version,
          action_count: map_size(definition.actions)
        }
      end)

    {:reply, integrations, state}
  end

  @impl GenServer
  def handle_call({:list_actions, integration_name}, _from, state) do
    actions =
      case Map.get(state.integrations, integration_name) do
        nil ->
          []

        integration ->
          Enum.map(integration.actions, fn {_name, action_def} ->
            %{
              name: action_def.name,
              display_name: action_def.display_name,
              description: action_def.description,
              input_ports: action_def.input_ports,
              output_ports: action_def.output_ports,
              default_success_port: action_def.default_success_port,
              default_error_port: action_def.default_error_port
            }
          end)
      end

    {:reply, actions, state}
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
        |> Enum.map(fn {_name, def} -> map_size(def.actions) end)
        |> Enum.sum(),
      integrations_by_category:
        state.integrations
        |> Enum.group_by(fn {_name, def} -> def.category end)
        |> Map.new(fn {category, integrations} -> {category, length(integrations)} end)

      # Private functions

      # Check if module implements the Integration behavior

      # Validate and normalize the definition
      # Initialize the integration if it supports init
      # Override name with the provided one
      # Convert list to map
      # Ensure all required fields are present with defaults

      # Validate required fields
      # Validate that module and function exist

      # Public helper functions
    }

    {:reply, {:ok, stats}, state}
  end

  @impl GenServer
  def handle_call(:health_check, _from, state) do
    results =
      Map.new(state.integrations, fn {name, definition} ->
        case check_integration_health(definition) do
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

  # Additional GenServer handlers

  @impl GenServer
  def handle_call({:reload_integration, integration_name}, _from, state) do
    case Map.get(state.integrations, integration_name) do
      nil ->
        {:reply, {:error, :not_found}, state}

      definition when is_map(definition) and not is_nil(definition.module) ->
        # Re-register the module
        case register_integration_module(definition.module, state) do
          {:ok, new_state} ->
            Logger.info("Reloaded integration: #{integration_name}")
            {:reply, :ok, new_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      _definition ->
        {:reply, {:error, "Integration was not registered from a module"}, state}
    end
  end

  @impl GenServer
  def handle_call(:get_all_actions, _from, state) do
    all_actions =
      Enum.flat_map(state.integrations, fn {integration_name, definition} ->
        Enum.map(definition.actions, fn {_action_name, action_def} ->
          Map.put(action_def, :integration_name, integration_name)
        end)
      end)

    {:reply, all_actions, state}
  end

  defp register_integration_module(module, state) do
    if function_exported?(module, :definition, 0) do
      definition = module.definition()

      case validate_and_normalize_definition(definition, module) do
        {:ok, normalized_def} ->
          case maybe_init_integration(module, state.config) do
            :ok ->
              new_integrations = Map.put(state.integrations, normalized_def.name, normalized_def)
              new_state = %{state | integrations: new_integrations}

              Logger.info(
                "Registered integration: #{normalized_def.name} (#{module}) with #{map_size(normalized_def.actions)} actions"
              )

              {:ok, new_state}

            {:error, reason} ->
              Logger.error("Failed to initialize integration #{module}: #{inspect(reason)}")
              {:error, "Integration initialization failed: #{reason}"}
          end

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, "Module #{module} does not implement Prana.Behaviour.Integration"}
    end
  rescue
    error ->
      Logger.error("Error registering integration #{module}: #{inspect(error)}")
      {:error, "Registration failed: #{inspect(error)}"}
  end

  defp register_integration_definition(name, definition, state) do
    case validate_and_normalize_definition(definition, nil) do
      {:ok, normalized_def} ->
        final_def = %{normalized_def | name: name}

        new_integrations = Map.put(state.integrations, name, final_def)
        new_state = %{state | integrations: new_integrations}

        Logger.info("Registered integration definition: #{name} with #{map_size(final_def.actions)} actions")
        {:ok, new_state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_and_normalize_definition(definition, module) do
    with :ok <- validate_required_fields(definition),
         {:ok, normalized_actions} <- validate_and_normalize_actions(definition.actions, module) do
      normalized_def = %{
        name: definition.name,
        display_name: Map.get(definition, :display_name, definition.name),
        description: Map.get(definition, :description, ""),
        version: Map.get(definition, :version, "1.0.0"),
        category: Map.get(definition, :category, "custom"),
        actions: normalized_actions,
        module: module,
        metadata: Map.get(definition, :metadata, %{})
      }

      {:ok, normalized_def}
    end
  end

  defp validate_required_fields(definition) do
    required_fields = [:name, :actions]

    missing_fields =
      Enum.reject(required_fields, fn field ->
        Map.has_key?(definition, field) && definition[field] != nil
      end)

    if Enum.empty?(missing_fields) do
      :ok
    else
      {:error, "Missing required fields: #{inspect(missing_fields)}"}
    end
  end

  defp validate_and_normalize_actions(actions, module) when is_list(actions) do
    action_map =
      Map.new(actions, fn action ->
        action_name = action[:name] || action["name"]
        {action_name, action}
      end)

    validate_and_normalize_actions(action_map, module)
  end

  defp validate_and_normalize_actions(actions, module) when is_map(actions) do
    normalized_actions =
      Map.new(actions, fn {action_name, action_def} ->
        case normalize_action_definition(action_def, module) do
          {:ok, normalized_action} -> {action_name, normalized_action}
          {:error, reason} -> throw({:error, "Invalid action #{action_name}: #{reason}"})
        end
      end)

    {:ok, normalized_actions}
  catch
    {:error, reason} -> {:error, reason}
  end

  defp normalize_action_definition(action_def, module) do
    normalized = %{
      name: get_field(action_def, :name),
      display_name: get_field(action_def, :display_name, get_field(action_def, :name)),
      description: get_field(action_def, :description, ""),
      module: get_field(action_def, :module, module),
      function: get_field(action_def, :function),
      input_ports: get_field(action_def, :input_ports, ["input"]),
      output_ports: get_field(action_def, :output_ports, ["success", "error"]),
      default_success_port: get_field(action_def, :default_success_port, "success"),
      default_error_port: get_field(action_def, :default_error_port, "error"),
      input_schema: get_field(action_def, :input_schema),
      output_schema: get_field(action_def, :output_schema),
      examples: get_field(action_def, :examples, []),
      metadata: get_field(action_def, :metadata, %{})
    }

    case validate_action_required_fields(normalized) do
      :ok -> {:ok, normalized}
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_field(map, key, default \\ nil) do
    Map.get(map, key) || Map.get(map, to_string(key)) || default
  end

  defp validate_action_required_fields(action) do
    required_fields = [:name, :module, :function]

    missing_fields =
      Enum.reject(required_fields, fn field ->
        value = Map.get(action, field)
        value && value != ""
      end)

    if Enum.empty?(missing_fields) do
      if function_exported?(action.module, action.function, 1) do
        :ok
      else
        {:error, "Function #{action.module}.#{action.function}/1 does not exist"}
      end
    else
      {:error, "Missing required fields: #{inspect(missing_fields)}"}
    end
  end

  defp maybe_init_integration(module, config) do
    if function_exported?(module, :init_integration, 1) do
      integration_config = Map.get(config, module, %{})

      case module.init_integration(integration_config) do
        {:ok, _state} -> :ok
        {:error, reason} -> {:error, reason}
        _ -> {:error, "Integration init returned unexpected value"}
      end
    else
      :ok
    end
  end

  defp get_action_from_state(state, integration_name, action_name) do
    case get_in(state.integrations, [integration_name, :actions, action_name]) do
      nil -> {:error, :not_found}
      action -> {:ok, action}
    end
  end

  defp check_integration_health(definition) do
    if definition.module && function_exported?(definition.module, :health_check, 0) do
      try do
        definition.module.health_check()
      rescue
        error -> {:error, "Health check failed: #{inspect(error)}"}
      end
    else
      :ok
    end
  end

  @doc """
  Reload an integration (useful for development)
  """
  def reload_integration(integration_name) do
    GenServer.call(__MODULE__, {:reload_integration, integration_name})
  end

  @doc """
  Validate an integration definition without registering it
  """
  def validate_integration_definition(definition) do
    case validate_and_normalize_definition(definition, nil) do
      {:ok, _normalized} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get all actions across all integrations (for UI/discovery)
  """
  def get_all_actions do
    GenServer.call(__MODULE__, :get_all_actions)
  end
end
