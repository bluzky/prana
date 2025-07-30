import React from 'react';
import { createRoot } from 'react-dom/client';
import WorkflowLayout from './components/WorkflowLayout.jsx';
import { WorkflowProvider } from './contexts/WorkflowContext.js';
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
    try {
      // Get all data attributes from the element with safe parsing
      const cleanWorkflowData = this.safeJsonParse(this.el.dataset.workflow, {});
      const integrations = this.safeJsonParse(this.el.dataset.integrations, []);
      const allActions = this.safeJsonParse(this.el.dataset.allActions, []);

      // Create React root
      const root = createRoot(this.el);
      this.React = React;

    // Event handlers for server communication (minimal/disabled for now)
    const onWorkflowChange = ({ nodes, edges }) => {
      // Disabled frequent server updates to prevent network spam
      // Only sync to server on explicit save actions
    };

    const onTitleChange = (title) => {
      // Title changes handled locally only
      // Could sync to server on blur/save if needed
    };

    // Render the WorkflowLayout component wrapped with WorkflowProvider
    root.render(
      React.createElement(WorkflowProvider, {
        onWorkflowChange,
        onTitleChange
      },
        React.createElement(WorkflowLayout, {
          initialWorkflowData: cleanWorkflowData,
          initialIntegrations: integrations,
          initialAllActions: allActions
        })
      )
    );

      this.root = root;
    } catch (error) {
      console.error('ReactFlow hook mount error:', error);
      // Display error message in the container
      this.el.innerHTML = `<div style="padding: 20px; color: red;">Error loading workflow editor: ${error.message}</div>`;
    }
  },

  safeJsonParse(jsonString, fallback) {
    try {
      return JSON.parse(jsonString || 'null') || fallback;
    } catch (error) {
      console.warn('JSON parse error:', error, 'Using fallback:', fallback);
      return fallback;
    }
  },

  destroyed() {
    if (this.root) {
      this.root.unmount();
    }
  }
};

export default ReactFlowHook;
