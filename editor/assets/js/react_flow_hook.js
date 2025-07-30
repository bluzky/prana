import React from 'react';
import { createRoot } from 'react-dom/client';
import WorkflowLayout from './components/WorkflowLayout.jsx';
import { WorkflowConverter } from './utils/workflow-converter.js';
import { NodeHelpers } from './utils/node-helpers.js';

/**
 * Phoenix LiveView Hook for React Flow Workflow Editor
 * 
 * This hook integrates the React Flow workflow editor with Phoenix LiveView,
 * handling client-server communication and local state management.
 */

const ReactFlowHook = {

  mounted() {
    // Get all data attributes from the element
    const cleanWorkflowData = JSON.parse(this.el.dataset.workflow || '{}');
    const integrations = JSON.parse(this.el.dataset.integrations || '[]');
    const allActions = JSON.parse(this.el.dataset.allActions || '[]');
    
    // Convert clean workflow data to React Flow format using utility
    const workflowData = WorkflowConverter.convertWorkflowToReactFlow(cleanWorkflowData, integrations);

    // Create React root and store current state
    const root = createRoot(this.el);
    this.React = React;
    this.currentWorkflowData = cleanWorkflowData;
    this.currentIntegrations = integrations;

    // Event handlers
    const onWorkflowChange = ({ nodes, edges }) => {
      if (this.el && this.el.isConnected) {
        const updatedWorkflow = WorkflowConverter.convertReactFlowToWorkflow(this.currentWorkflowData, nodes, edges);
        this.currentWorkflowData = updatedWorkflow;
        this.pushEvent("workflow_update", { workflow: updatedWorkflow });
      }
    };

    const onTitleChange = (title) => {
      // Update local workflow data only, don't sync to server immediately
      this.currentWorkflowData = { ...this.currentWorkflowData, name: title };
    };

    const onExportJson = () => {
      if (this.el && this.el.isConnected) {
        const json_data = JSON.stringify(this.currentWorkflowData, null, 2);
        const blob = new Blob([json_data], { type: "application/json" });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = "workflow.json";
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        URL.revokeObjectURL(url);
      }
    };

    const onAddNode = (action, integration) => {
      if (this.el && this.el.isConnected) {
        const integrationData = this.currentIntegrations.find(i => i.name === integration);
        if (integrationData) {
          const newNode = NodeHelpers.createNodeFromAction(action, integrationData);
          const updatedWorkflow = NodeHelpers.addNodeToWorkflow(this.currentWorkflowData, newNode);
          this.currentWorkflowData = updatedWorkflow;
          this.pushEvent("workflow_update", { workflow: updatedWorkflow });
        }
      }
    };

    // Render the WorkflowLayout component
    root.render(
      React.createElement(WorkflowLayout, {
        initialNodes: workflowData.nodes,
        initialEdges: workflowData.edges,
        workflowTitle: cleanWorkflowData.name || "Workflow Editor",
        onWorkflowChange,
        onTitleChange,
        onExportJson,
        integrations,
        allActions,
        workflowData: cleanWorkflowData,
        onAddNode
      })
    );

    this.root = root;
  },


  destroyed() {
    if (this.root) {
      this.root.unmount();
    }
  }


};

export default ReactFlowHook;
