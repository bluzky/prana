defmodule EditorWeb.WorkflowLive do
  use EditorWeb, :live_view

  alias Editor.IntegrationLoader

  @impl true
  def mount(_params, _session, socket) do
    workflow_data = initial_workflow_data()
    {:ok,
     socket
     |> assign(:workflow_data, workflow_data)
     |> assign(:workflow_title, workflow_data["name"])
     |> assign(:page_title, "Workflow Editor")
     |> assign(:search_query, "")
     |> assign(:selected_integration, nil)
     |> assign(:selected_node, nil)
     |> assign(:integrations, IntegrationLoader.load_integrations())
     |> assign(:all_actions, IntegrationLoader.load_all_actions())
     |> assign(:show_workflow_json, false)}
  end

  @impl true
  def handle_event("workflow_changed", %{"nodes" => react_nodes, "edges" => react_edges}, socket) do
    # Convert React Flow format to Prana workflow format
    workflow_data = convert_react_flow_to_prana(socket.assigns.workflow_data, react_nodes, react_edges)
    {:noreply, assign(socket, :workflow_data, workflow_data)}
  end

  @impl true
  def handle_event("title_changed", %{"title" => title}, socket) do
    updated_workflow = Map.put(socket.assigns.workflow_data, "name", title)
    {:noreply, 
     socket
     |> assign(:workflow_title, title)
     |> assign(:workflow_data, updated_workflow)}
  end

  @impl true
  def handle_event("search_changed", %{"search" => query}, socket) do
    {:noreply, assign(socket, :search_query, query)}
  end

  @impl true
  def handle_event("select_integration", %{"integration" => integration_name}, socket) do
    selected_integration = if integration_name == "", do: nil, else: integration_name
    {:noreply, assign(socket, :selected_integration, selected_integration)}
  end

  @impl true
  def handle_event("add_node", %{"action" => action_name, "integration" => integration_name}, socket) do
    case IntegrationLoader.get_integration(integration_name) do
      nil ->
        {:noreply, socket}

      integration ->
        new_node = create_node_from_action(action_name, integration)
        updated_workflow = add_node_to_workflow(socket.assigns.workflow_data, new_node)
        
        {:noreply, assign(socket, :workflow_data, updated_workflow)}
    end
  end

  @impl true
  def handle_event("node_selected", %{"node" => node_data}, socket) do
    # Find the corresponding Prana node by key
    prana_node = Enum.find(socket.assigns.workflow_data["nodes"], fn node ->
      node["key"] == node_data["node_key"] || node["key"] == node_data["id"]
    end)
    
    selected_node = if prana_node do
      Map.merge(node_data, %{
        "key" => prana_node["key"],
        "name" => prana_node["name"],
        "type" => prana_node["type"],
        "params" => prana_node["params"]
      })
    else
      node_data
    end
    
    {:noreply, assign(socket, :selected_node, selected_node)}
  end

  @impl true
  def handle_event("update_node_key", %{"node_key" => node_key}, socket) do
    if socket.assigns.selected_node do
      # Update both the React Flow node and Prana node
      updated_selected = Map.put(socket.assigns.selected_node, "node_key", node_key)
      
      # Find and update the Prana node
      updated_workflow = update_prana_node_by_key(
        socket.assigns.workflow_data, 
        socket.assigns.selected_node["key"] || socket.assigns.selected_node["node_key"],
        %{"key" => node_key}
      )
      
      {:noreply, 
       socket
       |> assign(:selected_node, updated_selected)
       |> assign(:workflow_data, updated_workflow)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_node_params", %{"params" => params_json}, socket) do
    if socket.assigns.selected_node do
      case Jason.decode(params_json) do
        {:ok, params} ->
          # Update the Prana node
          updated_workflow = update_prana_node_by_key(
            socket.assigns.workflow_data,
            socket.assigns.selected_node["key"] || socket.assigns.selected_node["node_key"],
            %{"params" => params}
          )
          
          updated_selected = Map.put(socket.assigns.selected_node, "params", params)
          
          {:noreply, 
           socket
           |> assign(:selected_node, updated_selected)
           |> assign(:workflow_data, updated_workflow)}
        {:error, _} ->
          # Keep the JSON string for editing, don't update workflow
          updated_node = Map.put(socket.assigns.selected_node, "params_json", params_json)
          {:noreply, assign(socket, :selected_node, updated_node)}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("export_json", _params, socket) do
    json_data = Jason.encode!(socket.assigns.workflow_data, pretty: true)

    {:noreply,
     socket
     |> push_event("download_file", %{
       content: json_data,
       filename: "workflow.json",
       mime_type: "application/json"
     })}
  end

  @impl true  
  def handle_event("toggle_workflow_json", _params, socket) do
    # This event is no longer needed as JSON editor is managed by React
    {:noreply, socket}
  end


  @impl true
  def handle_event("update_workflow_json", %{"json" => json_string}, socket) do
    case Jason.decode(json_string) do
      {:ok, workflow_data} ->
        {:noreply, assign(socket, :workflow_data, workflow_data)}
      {:error, _} ->
        # Keep the invalid JSON for editing
        {:noreply, socket}
    end
  end


  @impl true
  def render(assigns) do
    ~H"""
    <div 
      id="react-workflow-container"
      phx-hook="ReactFlow"
      phx-update="ignore"
      data-workflow={Jason.encode!(convert_prana_to_react_flow(@workflow_data))}
      data-workflow-title={@workflow_title}
      data-search-query={@search_query}
      data-selected-integration={@selected_integration}
      data-integrations={Jason.encode!(@integrations)}
      data-all-actions={Jason.encode!(@all_actions)}
      class="h-screen w-screen"
    >
    </div>
    
    """
  end

  defp initial_workflow_data do
    %{
      "id" => "simple-workflow",
      "name" => "Simple Workflow",
      "version" => 1,
      "variables" => %{},
      "nodes" => [
        %{
          "key" => "start",
          "name" => "Start",
          "type" => "manual.trigger",
          "params" => %{}
        },
        %{
          "key" => "http_call",
          "name" => "API Call",
          "type" => "http.request",
          "params" => %{
            "method" => "GET",
            "url" => "https://api.example.com/data"
          }
        },
        %{
          "key" => "check_status",
          "name" => "Check Status",
          "type" => "logic.if_condition",
          "params" => %{
            "condition" => "$nodes.http_call.response.status == 'success'"
          }
        },
        %{
          "key" => "success_action",
          "name" => "Success",
          "type" => "data.set_data",
          "params" => %{
            "message" => "API call successful"
          }
        },
        %{
          "key" => "error_action",
          "name" => "Error",
          "type" => "data.set_data",
          "params" => %{
            "message" => "API call failed"
          }
        }
      ],
      "connections" => %{
        "start" => %{
          "main" => [
            %{
              "to" => "http_call",
              "from" => "start",
              "to_port" => "main",
              "from_port" => "main"
            }
          ]
        },
        "http_call" => %{
          "main" => [
            %{
              "to" => "check_status",
              "from" => "http_call",
              "to_port" => "main",
              "from_port" => "main"
            }
          ]
        },
        "check_status" => %{
          "true" => [
            %{
              "to" => "success_action",
              "from" => "check_status",
              "to_port" => "main",
              "from_port" => "true"
            }
          ],
          "false" => [
            %{
              "to" => "error_action",
              "from" => "check_status",
              "to_port" => "main",
              "from_port" => "false"
            }
          ]
        }
      }
    }
  end

  defp create_node_from_action(action_name, integration) do
    node_key = generate_node_key(action_name)
    
    %{
      "key" => node_key,
      "name" => action_name,
      "type" => "#{integration.name}.#{action_name}",
      "params" => %{}
    }
  end

  defp add_node_to_workflow(workflow_data, node) do
    updated_nodes = [node | workflow_data["nodes"]]
    Map.put(workflow_data, "nodes", updated_nodes)
  end

  defp generate_node_key(action_name) do
    timestamp = System.system_time(:millisecond)
    "#{String.downcase(String.replace(action_name, " ", "_"))}_#{timestamp}"
  end

  defp filter_items(items, query) when query == "" or is_nil(query), do: items
  defp filter_items(items, query) do
    query_lower = String.downcase(query)
    Enum.filter(items, fn item ->
      case item do
        %{name: name} -> String.contains?(String.downcase(name), query_lower)
        action when is_binary(action) -> String.contains?(String.downcase(action), query_lower)
      end
    end)
  end

  defp update_node_in_workflow(workflow_data, updated_node) do
    updated_nodes = Enum.map(workflow_data["nodes"], fn node ->
      if node["key"] == updated_node["key"] do
        updated_node
      else
        node
      end
    end)
    
    Map.put(workflow_data, "nodes", updated_nodes)
  end

  defp update_prana_node_by_key(workflow_data, node_key, updates) do
    updated_nodes = Enum.map(workflow_data["nodes"], fn node ->
      if node["key"] == node_key do
        Map.merge(node, updates)
      else
        node
      end
    end)
    
    Map.put(workflow_data, "nodes", updated_nodes)
  end

  defp get_node_params_json(node) do
    cond do
      Map.has_key?(node, "params_json") -> 
        node["params_json"]
      Map.has_key?(node, "params") -> 
        Jason.encode!(node["params"], pretty: true)
      true -> 
        "{}"
    end
  end

  # Convert Prana workflow format to React Flow format for UI
  defp convert_prana_to_react_flow(prana_workflow) do
    nodes = Enum.map(prana_workflow["nodes"] || [], fn node ->
      %{
        "id" => node["key"],
        "type" => "custom",
        "position" => %{"x" => 0, "y" => 0}, # Will be auto-positioned by React Flow
        "data" => %{
          "type" => "action",
          "label" => node["name"],
          "action_name" => node["name"],
          "node_key" => node["key"],
          "integration_type" => node["type"]
        },
        "node_key" => node["key"],
        "params" => node["params"] || %{}
      }
    end)

    edges = convert_connections_to_edges(prana_workflow["connections"] || %{})

    %{
      "nodes" => nodes,
      "edges" => edges
    }
  end

  # Convert React Flow format back to Prana workflow format
  defp convert_react_flow_to_prana(current_prana, react_nodes, react_edges) do
    nodes = Enum.map(react_nodes, fn react_node ->
      %{
        "key" => react_node["node_key"] || react_node["id"],
        "name" => get_in(react_node, ["data", "label"]) || get_in(react_node, ["data", "action_name"]) || "Untitled",
        "type" => get_in(react_node, ["data", "integration_type"]) || "manual.test_action",
        "params" => react_node["params"] || %{}
      }
    end)

    connections = convert_edges_to_connections(react_edges)

    current_prana
    |> Map.put("nodes", nodes)
    |> Map.put("connections", connections)
  end

  defp convert_connections_to_edges(connections) do
    connections
    |> Enum.flat_map(fn {from_node, ports} ->
      Enum.flat_map(ports, fn {port, connections_list} ->
        Enum.map(connections_list, fn conn ->
          %{
            "id" => "e#{from_node}-#{conn["to"]}",
            "source" => from_node,
            "target" => conn["to"]
          }
          # Omit sourceHandle and targetHandle entirely for default connections
          # React Flow will use the default handles when these are not specified
        end)
      end)
    end)
  end

  defp convert_edges_to_connections(edges) do
    edges
    |> Enum.group_by(& &1["source"])
    |> Enum.into(%{}, fn {source, source_edges} ->
      port_connections = Enum.group_by(source_edges, & &1["sourceHandle"] || "main")
      
      port_map = Enum.into(port_connections, %{}, fn {port, port_edges} ->
        connections = Enum.map(port_edges, fn edge ->
          %{
            "to" => edge["target"],
            "from" => edge["source"],
            "to_port" => edge["targetHandle"] || "main",
            "from_port" => edge["sourceHandle"] || "main"
          }
        end)
        {port, connections}
      end)
      
      {source, port_map}
    end)
  end

end
