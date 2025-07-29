defmodule EditorWeb.WorkflowLive do
  use EditorWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:workflow_data, initial_workflow_data())
     |> assign(:workflow_title, "React Flow Playground")
     |> assign(:page_title, "Workflow Editor")
     |> assign(:search_query, "")
     |> assign(:selected_integration, nil)
     |> assign(:selected_node, nil)
     |> assign(:integrations, initial_integrations())
     |> assign(:all_actions, initial_all_actions())
     |> assign(:show_workflow_json, false)}
  end

  @impl true
  def handle_event("workflow_changed", %{"nodes" => nodes, "edges" => edges}, socket) do
    workflow_data = %{
      "nodes" => nodes,
      "edges" => edges
    }

    {:noreply, assign(socket, :workflow_data, workflow_data)}
  end

  @impl true
  def handle_event("title_changed", %{"title" => title}, socket) do
    {:noreply, assign(socket, :workflow_title, title)}
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
  def handle_event("node_selected", %{"node" => node_data}, socket) do
    {:noreply, assign(socket, :selected_node, node_data)}
  end

  @impl true
  def handle_event("update_node_key", %{"node_key" => node_key}, socket) do
    if socket.assigns.selected_node do
      updated_node = Map.put(socket.assigns.selected_node, "node_key", node_key)
      updated_workflow = update_node_in_workflow(socket.assigns.workflow_data, updated_node)
      
      {:noreply, 
       socket
       |> assign(:selected_node, updated_node)
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
          updated_node = Map.put(socket.assigns.selected_node, "params", params)
          updated_workflow = update_node_in_workflow(socket.assigns.workflow_data, updated_node)
          
          {:noreply, 
           socket
           |> assign(:selected_node, updated_node)
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
      data-workflow={Jason.encode!(@workflow_data)}
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
      "nodes" => [
        %{
          "id" => "1",
          "type" => "custom",
          "position" => %{"x" => 250, "y" => 25},
          "data" => %{
            "type" => "start",
            "label" => "Start Flow",
            "action_name" => "Start Flow",
            "node_key" => "start_node"
          },
          "node_key" => "start_node",
          "params" => %{"timeout" => 30, "retry" => true}
        },
        %{
          "id" => "2",
          "type" => "custom",
          "position" => %{"x" => 250, "y" => 150},
          "data" => %{
            "type" => "action",
            "label" => "Instance",
            "action_name" => "Instance",
            "node_key" => "AB2 Instance"
          },
          "node_key" => "AB2 Instance",
          "params" => %{"method" => "POST", "url" => "https://api.example.com", "headers" => %{"Content-Type" => "application/json"}}
        },
        %{
          "id" => "3",
          "type" => "custom",
          "position" => %{"x" => 250, "y" => 300},
          "data" => %{
            "type" => "review",
            "label" => "Review Case",
            "action_name" => "Review Case",
            "node_key" => "Assigned to Requester's m..."
          },
          "node_key" => "Assigned to Requester's m...",
          "params" => %{"reviewType" => "manual", "assignee" => "requester_manager"}
        },
        %{
          "id" => "4",
          "type" => "custom",
          "position" => %{"x" => 100, "y" => 500},
          "data" => %{
            "type" => "end",
            "label" => "Step",
            "action_name" => "Step",
            "node_key" => "An email with the reque..."
          },
          "node_key" => "An email with the reque...",
          "params" => %{"action" => "send_email", "template" => "approval"}
        },
        %{
          "id" => "5",
          "type" => "custom",
          "position" => %{"x" => 400, "y" => 500},
          "data" => %{
            "type" => "end",
            "label" => "Approved Status",
            "action_name" => "Approved Status",
            "node_key" => "Email Requesters"
          },
          "node_key" => "Email Requesters",
          "params" => %{"status" => "approved", "notify" => true}
        }
      ],
      "edges" => [
        %{
          "id" => "e1-2",
          "source" => "1",
          "target" => "2"
        },
        %{
          "id" => "e2-3",
          "source" => "2",
          "target" => "3"
        },
        %{
          "id" => "e3-4",
          "source" => "3",
          "target" => "4",
          "label" => "Path 1"
        },
        %{
          "id" => "e3-5",
          "source" => "3",
          "target" => "5",
          "label" => "Path 2"
        }
      ]
    }
  end

  defp initial_integrations do
    [
      %{name: "Slack", selected: true, completed: false, actions: [
        "Send Message", "Send Direct Message", "Create Channel", "Archive Channel", 
        "Invite User to Channel", "Set Channel Topic", "Upload File", "Pin Message",
        "Set Status", "Get User Info", "List Channels", "Get Channel History"
      ]},
      %{name: "Gmail", selected: false, completed: true, actions: [
        "Send Email", "Reply to Email", "Forward Email", "Create Draft", "Delete Email",
        "Mark as Read", "Mark as Unread", "Add Label", "Remove Label", "Search Emails",
        "Get Email Content", "Download Attachment"
      ]},
      %{name: "Google Sheets", selected: false, completed: false, actions: [
        "Create Spreadsheet", "Add Row", "Update Cell", "Delete Row", "Create Sheet",
        "Delete Sheet", "Format Cells", "Sort Data", "Filter Data", "Get Cell Value",
        "Bulk Update", "Clear Range"
      ]},
      %{name: "Trello", selected: false, completed: false, actions: [
        "Create Board", "Create List", "Create Card", "Move Card", "Update Card",
        "Add Comment", "Add Checklist", "Set Due Date", "Assign Member", "Add Label",
        "Archive Card", "Delete Card"
      ]},
      %{name: "GitHub", selected: false, completed: false, actions: [
        "Create Repository", "Create Issue", "Close Issue", "Create Pull Request", "Merge PR",
        "Add Comment", "Create Branch", "Delete Branch", "Create Release", "Upload File",
        "Get Repository Info", "List Commits"
      ]},
      %{name: "Salesforce", selected: false, completed: false, actions: [
        "Create Lead", "Update Lead", "Create Contact", "Update Contact", "Create Account",
        "Create Opportunity", "Update Opportunity", "Create Task", "Send Email", "Log Activity",
        "Get Record", "Delete Record"
      ]},
      %{name: "HubSpot", selected: false, completed: false, actions: [
        "Create Contact", "Update Contact", "Create Deal", "Update Deal", "Create Company",
        "Send Email", "Create Task", "Log Call", "Add Note", "Create Ticket",
        "Update Ticket", "Get Contact Properties"
      ]},
      %{name: "Zapier Webhooks", selected: false, completed: false, actions: [
        "Send POST Request", "Send GET Request", "Send PUT Request", "Send DELETE Request",
        "Parse JSON Response", "Handle Response", "Set Headers", "Add Authentication"
      ]},
      %{name: "Dropbox", selected: false, completed: false, actions: [
        "Upload File", "Download File", "Delete File", "Create Folder", "Move File",
        "Copy File", "Share File", "Get File Info", "List Files", "Search Files"
      ]},
      %{name: "Twitter", selected: false, completed: false, actions: [
        "Post Tweet", "Reply to Tweet", "Retweet", "Like Tweet", "Send Direct Message",
        "Follow User", "Unfollow User", "Get User Info", "Search Tweets", "Upload Media"
      ]}
    ]
  end

  defp initial_all_actions do
    [
      # Communication
      "Send Email", "Reply to Email", "Forward Email", "Send Message", "Send Direct Message",
      "Send SMS", "Make Phone Call", "Send Notification", "Post Tweet", "Send Slack Message",
      
      # File Management
      "Upload File", "Download File", "Delete File", "Move File", "Copy File", "Rename File",
      "Create Folder", "Share File", "Compress File", "Extract Archive", "Convert File Format",
      
      # Data Management
      "Create Record", "Update Record", "Delete Record", "Get Record", "Search Records",
      "Import Data", "Export Data", "Backup Data", "Sync Data", "Validate Data",
      
      # Spreadsheet Operations
      "Add Row", "Update Cell", "Delete Row", "Create Sheet", "Format Cells", "Sort Data",
      "Filter Data", "Calculate Sum", "Create Chart", "Pivot Table", "Bulk Update",
      
      # Project Management
      "Create Task", "Update Task", "Complete Task", "Assign Task", "Set Due Date",
      "Create Project", "Update Status", "Add Comment", "Create Milestone", "Track Time",
      
      # CRM Operations
      "Create Lead", "Update Lead", "Create Contact", "Update Contact", "Create Deal",
      "Update Deal", "Log Activity", "Schedule Meeting", "Send Quote", "Track Opportunity",
      
      # Social Media
      "Post to Facebook", "Post to Instagram", "Post to LinkedIn", "Schedule Post",
      "Like Post", "Share Post", "Follow User", "Unfollow User", "Get Analytics",
      
      # E-commerce
      "Create Product", "Update Inventory", "Process Order", "Send Invoice", "Track Shipment",
      "Handle Return", "Apply Discount", "Send Receipt", "Update Price", "Manage Stock",
      
      # Analytics & Reporting
      "Generate Report", "Create Dashboard", "Track Event", "Monitor Performance",
      "Send Analytics", "Export Metrics", "Schedule Report", "Alert on Threshold",
      
      # Automation
      "If/Then Logic", "Delay Action", "Loop Through Items", "Filter Items", "Transform Data",
      "Parse JSON", "Format Date", "Generate Random", "Count Items", "Math Operations",
      
      # Development
      "API Call", "Database Query", "Run Script", "Deploy Code", "Create Branch",
      "Merge Code", "Run Tests", "Build Application", "Send Webhook", "Parse Response",
      
      # Utilities
      "Generate UUID", "Hash Password", "Encrypt Data", "Decrypt Data", "Validate Email",
      "Format Phone", "Get Current Time", "Calculate Duration", "Random Number", "URL Encode"
    ]
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
      if node["id"] == updated_node["id"] do
        updated_node
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

end
