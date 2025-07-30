# LiveView + React Workflow Editor Integration Architecture

## Overview

This document outlines the architecture for integrating a React-based visual workflow editor with Phoenix LiveView, enabling real-time collaborative editing of Prana workflows.

## Architecture Components

### 1. Phoenix LiveView (Server-Side)
**Purpose**: State management, validation, persistence, and real-time synchronization

```elixir
defmodule MyAppWeb.WorkflowEditorLive do
  use MyAppWeb, :live_view
  
  # Server-side workflow state
  @impl true
  def mount(%{"workflow_id" => workflow_id}, _session, socket) do
    workflow = load_workflow(workflow_id)
    integrations = Prana.IntegrationRegistry.list_integrations()
    
    socket = 
      socket
      |> assign(:workflow, workflow)
      |> assign(:integrations, integrations)
      |> assign(:validation_errors, [])
      |> assign(:selected_node, nil)
    
    {:ok, socket}
  end
  
  # Handle React component events
  @impl true
  def handle_event("workflow_updated", %{"workflow" => workflow_data}, socket) do
    case validate_and_update_workflow(workflow_data) do
      {:ok, workflow} ->
        # Broadcast to other users
        broadcast_workflow_update(workflow)
        {:noreply, assign(socket, :workflow, workflow)}
      {:error, errors} ->
        {:noreply, assign(socket, :validation_errors, errors)}
    end
  end
end
```

### 2. LiveView Hook (Client-Side Bridge)
**Purpose**: Communication bridge between LiveView and React component

```javascript
// assets/js/hooks/workflow_editor_hook.js
const WorkflowEditorHook = {
  mounted() {
    // Mount React component
    this.reactComponent = ReactDOM.render(
      React.createElement(WorkflowEditor, {
        workflow: this.el.dataset.workflow ? JSON.parse(this.el.dataset.workflow) : null,
        integrations: JSON.parse(this.el.dataset.integrations),
        onWorkflowChange: (workflow) => this.handleWorkflowChange(workflow),
        onNodeSelect: (nodeId) => this.handleNodeSelect(nodeId),
        onValidationRequest: (data) => this.handleValidationRequest(data)
      }),
      this.el
    );
  },
  
  updated() {
    // Update React component props when LiveView state changes
    if (this.reactComponent) {
      this.reactComponent.updateProps({
        workflow: this.el.dataset.workflow ? JSON.parse(this.el.dataset.workflow) : null,
        validationErrors: this.el.dataset.validationErrors ? JSON.parse(this.el.dataset.validationErrors) : []
      });
    }
  },
  
  destroyed() {
    // Cleanup React component
    if (this.reactComponent) {
      ReactDOM.unmountComponentAtNode(this.el);
    }
  },
  
  // Send workflow changes to LiveView
  handleWorkflowChange(workflow) {
    this.pushEvent("workflow_updated", { workflow });
  },
  
  // Send node selection to LiveView
  handleNodeSelect(nodeId) {
    this.pushEvent("node_selected", { node_id: nodeId });
  },
  
  // Request server-side validation
  handleValidationRequest(data) {
    this.pushEvent("validate_workflow", data);
  }
};

export default WorkflowEditorHook;
```

### 3. React Component (Visual Editor)
**Purpose**: Interactive workflow graph editor

```typescript
// assets/js/components/WorkflowEditor.tsx
interface WorkflowEditorProps {
  workflow: PranaWorkflow | null;
  integrations: Integration[];
  validationErrors?: ValidationError[];
  onWorkflowChange: (workflow: PranaWorkflow) => void;
  onNodeSelect: (nodeId: string) => void;
  onValidationRequest: (data: any) => void;
}

export const WorkflowEditor: React.FC<WorkflowEditorProps> = ({
  workflow,
  integrations,
  validationErrors = [],
  onWorkflowChange,
  onNodeSelect,
  onValidationRequest
}) => {
  const [nodes, setNodes] = useState<Node[]>([]);
  const [edges, setEdges] = useState<Edge[]>([]);
  
  // Convert Prana workflow to React Flow format
  useEffect(() => {
    if (workflow) {
      const { nodes: flowNodes, edges: flowEdges } = convertPranaToReactFlow(workflow);
      setNodes(flowNodes);
      setEdges(flowEdges);
    }
  }, [workflow]);
  
  // Handle node changes
  const handleNodesChange = useCallback((changes: NodeChange[]) => {
    setNodes(nds => applyNodeChanges(changes, nds));
    
    // Convert back to Prana format and notify LiveView
    const updatedWorkflow = convertReactFlowToPrana(nodes, edges);
    onWorkflowChange(updatedWorkflow);
  }, [nodes, edges, onWorkflowChange]);
  
  return (
    <div className="workflow-editor">
      <div className="editor-sidebar">
        <ActionCatalog integrations={integrations} onActionAdd={handleActionAdd} />
        <PropertyPanel selectedNode={selectedNode} onNodeUpdate={handleNodeUpdate} />
      </div>
      
      <div className="editor-canvas">
        <ReactFlow
          nodes={nodes}
          edges={edges}
          onNodesChange={handleNodesChange}
          onEdgesChange={handleEdgesChange}
          onConnect={handleConnect}
          nodeTypes={nodeTypes}
          edgeTypes={edgeTypes}
        >
          <Background />
          <Controls />
          <MiniMap />
        </ReactFlow>
      </div>
      
      {validationErrors.length > 0 && (
        <ValidationErrorPanel errors={validationErrors} />
      )}
    </div>
  );
};
```

## Message Protocol

### LiveView → React (via data attributes)
```json
{
  "workflow": {
    "id": "workflow_123",
    "name": "User Registration",
    "nodes": [...],
    "connections": {...}
  },
  "integrations": {
    "manual": {...},
    "logic": {...}
  },
  "validation_errors": [
    {
      "node_id": "validate_email",
      "field": "params.email_field",
      "message": "Field is required"
    }
  ],
  "selected_node": "validate_email"
}
```

### React → LiveView (via pushEvent)
```json
{
  "event": "workflow_updated",
  "data": {
    "workflow": {
      "id": "workflow_123",
      "nodes": [...],
      "connections": {...}
    }
  }
}

{
  "event": "node_selected", 
  "data": {
    "node_id": "validate_email"
  }
}

{
  "event": "validate_workflow",
  "data": {
    "workflow": {...},
    "validation_type": "real_time"
  }
}
```

## Real-time Synchronization

### Phoenix Channel Integration
```elixir
defmodule MyAppWeb.WorkflowChannel do
  use MyAppWeb, :channel
  
  def join("workflow:" <> workflow_id, _params, socket) do
    # Authorize user access to workflow
    if authorized?(socket.assigns.user, workflow_id) do
      {:ok, assign(socket, :workflow_id, workflow_id)}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end
  
  def handle_in("workflow_updated", %{"workflow" => workflow_data}, socket) do
    # Validate and broadcast to other users
    case validate_workflow(workflow_data) do
      {:ok, workflow} ->
        broadcast_from!(socket, "workflow_updated", %{
          workflow: workflow,
          updated_by: socket.assigns.user.id
        })
        {:noreply, socket}
      {:error, errors} ->
        {:reply, {:error, %{errors: errors}}, socket}
    end
  end
end
```

### Real-time Updates in React
```typescript
// Real-time updates via Phoenix channels
useEffect(() => {
  const channel = socket.channel(`workflow:${workflowId}`, {});
  
  channel.on("workflow_updated", (payload) => {
    if (payload.updated_by !== currentUserId) {
      // Update from another user
      setWorkflow(payload.workflow);
      showUpdateNotification(payload.updated_by);
    }
  });
  
  channel.join()
    .receive("ok", () => console.log("Joined workflow channel"))
    .receive("error", (resp) => console.log("Unable to join", resp));
    
  return () => channel.leave();
}, [workflowId]);
```

## File Structure

```
lib/
├── my_app_web/
│   ├── live/
│   │   └── workflow_editor_live.ex          # Main LiveView module
│   ├── channels/
│   │   └── workflow_channel.ex              # Real-time sync channel
│   └── components/
│       └── workflow_editor_component.ex     # LiveView component wrapper

assets/
├── js/
│   ├── hooks/
│   │   └── workflow_editor_hook.js          # LiveView ↔ React bridge
│   ├── components/
│   │   ├── WorkflowEditor.tsx               # Main React component
│   │   ├── ActionCatalog.tsx                # Action search/selection
│   │   ├── PropertyPanel.tsx                # Node parameter editing
│   │   ├── nodes/
│   │   │   ├── PranaNode.tsx                # Custom React Flow node
│   │   │   └── NodePortRenderer.tsx         # Port rendering
│   │   └── utils/
│   │       ├── workflow_converter.ts        # Prana ↔ React Flow conversion
│   │       └── validation.ts                # Client-side validation helpers
│   └── app.js                               # Register hooks
├── css/
│   └── workflow_editor.css                  # Editor-specific styles
└── package.json                             # React dependencies
```

## Implementation Benefits

### 1. **Server-Side State Management**
- Workflow state managed in LiveView (reliable, consistent)
- Direct access to Prana's validation and serialization
- Automatic persistence and change tracking

### 2. **Real-time Collaboration** 
- Multiple users can edit workflows simultaneously
- Changes broadcast instantly via Phoenix channels
- Conflict resolution handled server-side

### 3. **Rich Client Interaction**
- React Flow provides smooth drag-and-drop UX
- Monaco Editor for advanced parameter editing
- Client-side optimizations for responsiveness

### 4. **Seamless Integration**
- Feels native to Phoenix applications
- Uses existing authentication/authorization
- Leverages LiveView's reactive model

### 5. **Progressive Enhancement**
- Works without JavaScript (basic form fallback)
- Enhanced with React for better UX
- Graceful degradation for accessibility

## Development Workflow

1. **Start with LiveView**: Create basic workflow CRUD
2. **Add React Hook**: Embed React component via hook
3. **Implement Data Flow**: JSON message protocol
4. **Add Real-time Sync**: Phoenix channels integration
5. **Enhance UX**: Advanced React Flow features

This architecture provides the best of both worlds: LiveView's robust server-side capabilities with React's rich client-side interactions.