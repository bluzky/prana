defmodule Editor.IntegrationLoader do
  @moduledoc """
  Loads Prana integrations and actions for the workflow editor UI.
  """

  alias Prana.IntegrationRegistry

  @doc """
  Loads all available integrations from the Prana registry and formats them
  for the frontend UI.
  """
  def load_integrations do
    case IntegrationRegistry.list_integrations() do
      {:ok, integrations} when is_list(integrations) ->
        load_full_integrations(integrations)

      # Handle direct list return (actual case)
      integrations when is_list(integrations) ->
        load_full_integrations(integrations)

      # Handle empty list case
      [] ->
        []

      {:error, _reason} ->
        # Fallback to empty list if registry not available
        []
    end
  end

  defp load_full_integrations(integration_summaries) do
    integration_summaries
    |> Enum.map(fn summary ->
      case IntegrationRegistry.get_integration(summary.name) do
        {:ok, integration} -> format_integration(integration)
        _ -> format_integration_from_summary(summary)
      end
    end)
    |> Enum.sort_by(& &1.name)
  end

  @doc """
  Loads all available actions across all integrations for search functionality.
  """
  def load_all_actions do
    case IntegrationRegistry.list_integrations() do
      {:ok, integrations} when is_list(integrations) ->
        load_all_actions_from_summaries(integrations)

      # Handle direct list return (actual case)
      integrations when is_list(integrations) ->
        load_all_actions_from_summaries(integrations)

      # Handle empty list case
      [] ->
        []

      {:error, _reason} ->
        []
    end
  end

  defp load_all_actions_from_summaries(integration_summaries) do
    integration_summaries
    |> Enum.flat_map(fn summary ->
      case IntegrationRegistry.get_integration(summary.name) do
        {:ok, integration} ->
          integration.actions
          |> Enum.map(fn {_key, action} ->
            format_action(action, integration.display_name)
          end)
        _ ->
          # Fallback to empty list if can't get full integration
          []
      end
    end)
    |> Enum.sort()
  end

  @doc """
  Gets a specific integration by name.
  """
  def get_integration(name) do
    case IntegrationRegistry.get_integration(name) do
      {:ok, integration} -> format_integration(integration)
      {:error, _reason} -> nil
    end
  end

  # Private helper functions

  defp format_integration(integration) do
    %{
      name: integration.name,
      display_name: integration.display_name,
      description: Map.get(integration, :description, ""),
      selected: false,
      completed: false,
      actions: format_actions(integration.actions)
    }
  end

  defp format_integration_from_summary(summary) do
    %{
      name: summary.name,
      display_name: summary.display_name,
      description: Map.get(summary, :description, ""),
      selected: false,
      completed: false,
      actions: []  # No actions available from summary
    }
  end

  defp format_actions(actions) do
    actions
    |> Enum.map(fn {key, action} -> 
      %{
        key: key,
        name: action.name,
        display_name: action.display_name || action.name,
        description: Map.get(action, :description, ""),
        input_ports: action.input_ports || ["main"],
        output_ports: action.output_ports || ["main", "error"]
      }
    end)
    |> Enum.sort_by(& &1.display_name)
  end

  defp format_action(action, integration_name) do
    display_name = action.display_name || action.name
    "#{display_name} (#{integration_name})"
  end
end