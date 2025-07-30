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
     |> assign(:integrations, IntegrationLoader.load_integrations())
     |> assign(:all_actions, IntegrationLoader.load_all_actions())}
  end

  @impl true
  def handle_event("workflow_update", %{"workflow" => clean_workflow}, socket) do
    # Client sends the complete updated workflow data
    updated_workflow = Map.put(clean_workflow, "name", socket.assigns.workflow_title)
    {:noreply, assign(socket, :workflow_data, updated_workflow)}
  end

  @impl true
  def handle_event("workflow_changed", %{"workflow" => clean_workflow, "title" => title}, socket) do
    # Client sends workflow data and title changes
    {:noreply, 
     socket
     |> assign(:workflow_data, clean_workflow)
     |> assign(:workflow_title, title)}
  end


  @impl true
  def render(assigns) do
    ~H"""
    <div 
      id="react-workflow-container"
      phx-hook="ReactFlow"
      phx-update="ignore"
      data-workflow={Jason.encode!(@workflow_data)}
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
          "params" => %{},
          "x" => 250,
          "y" => 50
        },
        %{
          "key" => "http_call",
          "name" => "API Call",
          "type" => "http.request",
          "params" => %{
            "method" => "GET",
            "url" => "https://api.example.com/data"
          },
          "x" => 250,
          "y" => 150
        },
        %{
          "key" => "check_status",
          "name" => "Check Status",
          "type" => "logic.if_condition",
          "params" => %{
            "condition" => "$nodes.http_call.response.status == 'success'"
          },
          "x" => 250,
          "y" => 250
        },
        %{
          "key" => "success_action",
          "name" => "Success",
          "type" => "data.set_data",
          "params" => %{
            "message" => "API call successful"
          },
          "x" => 100,
          "y" => 350
        },
        %{
          "key" => "error_action",
          "name" => "Error",
          "type" => "data.set_data",
          "params" => %{
            "message" => "API call failed"
          },
          "x" => 400,
          "y" => 350
        },
        %{
          "key" => "merge_results",
          "name" => "Merge Results",
          "type" => "data.merge",
          "params" => %{
            "strategy" => "append"
          },
          "x" => 250,
          "y" => 450
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
        },
        "success_action" => %{
          "main" => [
            %{
              "to" => "merge_results",
              "from" => "success_action",
              "to_port" => "input_a",
              "from_port" => "main"
            }
          ]
        },
        "error_action" => %{
          "main" => [
            %{
              "to" => "merge_results",
              "from" => "error_action",
              "to_port" => "input_b",
              "from_port" => "main"
            }
          ]
        }
      }
    }
  end



end
