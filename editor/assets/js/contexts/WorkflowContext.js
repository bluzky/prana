import React, { createContext, useContext, useReducer, useCallback, useEffect } from 'react';
import { WorkflowConverter } from '../utils/workflow-converter.js';
import { NodeHelpers } from '../utils/node-helpers.js';

// Action types
const WORKFLOW_ACTIONS = {
  INITIALIZE: 'INITIALIZE',
  UPDATE_TITLE: 'UPDATE_TITLE',
  UPDATE_NODES: 'UPDATE_NODES',
  UPDATE_EDGES: 'UPDATE_EDGES',
  UPDATE_WORKFLOW_DATA: 'UPDATE_WORKFLOW_DATA',
  UPDATE_JSON_EDITOR: 'UPDATE_JSON_EDITOR',
  ADD_NODE: 'ADD_NODE',
  UPDATE_NODE: 'UPDATE_NODE',
  DELETE_NODE: 'DELETE_NODE',
  SYNC_TO_SERVER: 'SYNC_TO_SERVER'
};

// Initial state
const initialState = {
  // Clean workflow data (server format)
  workflowData: {
    id: '',
    name: '',
    version: 1,
    variables: {},
    nodes: [],
    connections: {}
  },
  // React Flow format
  reactFlowData: {
    nodes: [],
    edges: []
  },
  // UI state
  title: '',
  integrations: [],
  allActions: [],
  // Flags to prevent infinite loops
  isUpdatingFromJson: false,
  isUpdatingFromFlow: false,
  isUpdatingFromTitle: false
};

// Reducer function
function workflowReducer(state, action) {
  switch (action.type) {
    case WORKFLOW_ACTIONS.INITIALIZE:
      const { workflowData, integrations, allActions } = action.payload;
      const reactFlowData = WorkflowConverter.convertWorkflowToReactFlow(workflowData, integrations);
      
      return {
        ...state,
        workflowData,
        reactFlowData,
        title: workflowData.name || '',
        integrations,
        allActions
      };

    case WORKFLOW_ACTIONS.UPDATE_TITLE:
      if (state.isUpdatingFromTitle) return state;
      
      const updatedWorkflowWithTitle = {
        ...state.workflowData,
        name: action.payload.title
      };
      
      return {
        ...state,
        title: action.payload.title,
        workflowData: updatedWorkflowWithTitle,
        isUpdatingFromTitle: true
      };

    case WORKFLOW_ACTIONS.UPDATE_NODES:
    case WORKFLOW_ACTIONS.UPDATE_EDGES:
      if (state.isUpdatingFromFlow) return state;
      
      const { nodes, edges } = action.payload;
      const updatedReactFlowData = { nodes, edges };
      const updatedWorkflowFromFlow = WorkflowConverter.convertReactFlowToWorkflow(
        state.workflowData, 
        nodes, 
        edges
      );
      
      return {
        ...state,
        reactFlowData: updatedReactFlowData,
        workflowData: updatedWorkflowFromFlow,
        isUpdatingFromFlow: true
      };

    case WORKFLOW_ACTIONS.UPDATE_WORKFLOW_DATA:
      if (state.isUpdatingFromJson) return state;
      
      const newWorkflowData = action.payload.workflowData;
      const newReactFlowData = WorkflowConverter.convertWorkflowToReactFlow(
        newWorkflowData, 
        state.integrations
      );
      
      return {
        ...state,
        workflowData: newWorkflowData,
        reactFlowData: newReactFlowData,
        title: newWorkflowData.name || state.title,
        isUpdatingFromJson: true
      };

    case WORKFLOW_ACTIONS.ADD_NODE:
      const { action: actionName, integration } = action.payload;
      const integrationData = state.integrations.find(i => i.name === integration);
      
      if (!integrationData) return state;
      
      const newNode = NodeHelpers.createNodeFromAction(actionName, integrationData);
      const updatedWorkflowWithNode = NodeHelpers.addNodeToWorkflow(state.workflowData, newNode);
      const updatedReactFlowWithNode = WorkflowConverter.convertWorkflowToReactFlow(
        updatedWorkflowWithNode, 
        state.integrations
      );
      
      return {
        ...state,
        workflowData: updatedWorkflowWithNode,
        reactFlowData: updatedReactFlowWithNode
      };

    case WORKFLOW_ACTIONS.UPDATE_NODE:
      const { nodeId, updates } = action.payload;
      
      // Update in React Flow data, ensuring node_key and node_id are properly updated in the data object
      const updatedNodes = state.reactFlowData.nodes.map(node =>
        node.id === nodeId ? { 
          ...node, 
          ...updates,
          data: {
            ...node.data,
            ...updates.data,
            // Ensure node_key and node_id are synced from data updates
            node_key: updates.data?.node_key || node.data.node_key,
            node_id: updates.data?.node_id || node.data.node_id || node.id
          }
        } : node
      );
      
      // Convert back to workflow data
      const updatedWorkflowFromNode = WorkflowConverter.convertReactFlowToWorkflow(
        state.workflowData,
        updatedNodes,
        state.reactFlowData.edges
      );
      
      return {
        ...state,
        reactFlowData: {
          ...state.reactFlowData,
          nodes: updatedNodes
        },
        workflowData: updatedWorkflowFromNode
      };

    case WORKFLOW_ACTIONS.DELETE_NODE:
      const { nodeId: nodeToDeleteId } = action.payload;
      
      // Remove from React Flow data
      const filteredNodes = state.reactFlowData.nodes.filter(node => node.id !== nodeToDeleteId);
      const filteredEdges = state.reactFlowData.edges.filter(edge => 
        edge.source !== nodeToDeleteId && edge.target !== nodeToDeleteId
      );
      
      // Convert back to workflow data
      const updatedWorkflowFromDelete = WorkflowConverter.convertReactFlowToWorkflow(
        state.workflowData,
        filteredNodes,
        filteredEdges
      );
      
      return {
        ...state,
        reactFlowData: {
          nodes: filteredNodes,
          edges: filteredEdges
        },
        workflowData: updatedWorkflowFromDelete
      };

    case WORKFLOW_ACTIONS.SYNC_TO_SERVER:
      // Reset update flags after server sync
      return {
        ...state,
        isUpdatingFromJson: false,
        isUpdatingFromFlow: false,
        isUpdatingFromTitle: false
      };

    default:
      return state;
  }
}

// Context creation
const WorkflowContext = createContext();

// Provider component
export const WorkflowProvider = ({ children, onWorkflowChange, onTitleChange }) => {
  const [state, dispatch] = useReducer(workflowReducer, initialState);

  // Initialize workflow data
  const initialize = useCallback((workflowData, integrations, allActions) => {
    dispatch({
      type: WORKFLOW_ACTIONS.INITIALIZE,
      payload: { workflowData, integrations, allActions }
    });
  }, []);

  // Update title
  const updateTitle = useCallback((title) => {
    dispatch({
      type: WORKFLOW_ACTIONS.UPDATE_TITLE,
      payload: { title }
    });
  }, []);

  // Update React Flow nodes/edges
  const updateFlow = useCallback((nodes, edges) => {
    dispatch({
      type: WORKFLOW_ACTIONS.UPDATE_NODES,
      payload: { nodes, edges }
    });
  }, []);

  // Update workflow data from JSON editor
  const updateWorkflowData = useCallback((workflowData) => {
    dispatch({
      type: WORKFLOW_ACTIONS.UPDATE_WORKFLOW_DATA,
      payload: { workflowData }
    });
  }, []);

  // Add node
  const addNode = useCallback((action, integration) => {
    dispatch({
      type: WORKFLOW_ACTIONS.ADD_NODE,
      payload: { action, integration }
    });
  }, []);

  // Update node
  const updateNode = useCallback((nodeId, updates) => {
    dispatch({
      type: WORKFLOW_ACTIONS.UPDATE_NODE,
      payload: { nodeId, updates }
    });
  }, []);

  // Delete node
  const deleteNode = useCallback((nodeId) => {
    dispatch({
      type: WORKFLOW_ACTIONS.DELETE_NODE,
      payload: { nodeId }
    });
  }, []);

  // Export JSON
  const exportJson = useCallback(() => {
    const json_data = JSON.stringify(state.workflowData, null, 2);
    const blob = new Blob([json_data], { type: "application/json" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = "workflow.json";
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  }, [state.workflowData]);

  // Sync to server when state changes (disabled to prevent network spam)
  useEffect(() => {
    if (state.isUpdatingFromFlow || state.isUpdatingFromTitle || state.isUpdatingFromJson) {
      // Server sync disabled - only local state management
      // Could enable for explicit save actions if needed
      
      // Reset flags after a short delay to allow other updates
      setTimeout(() => {
        dispatch({ type: WORKFLOW_ACTIONS.SYNC_TO_SERVER });
      }, 50);
    }
  }, [state.isUpdatingFromFlow, state.isUpdatingFromTitle, state.isUpdatingFromJson]);

  const contextValue = {
    // State
    workflowData: state.workflowData,
    reactFlowData: state.reactFlowData,
    title: state.title,
    integrations: state.integrations,
    allActions: state.allActions,
    
    // Actions
    initialize,
    updateTitle,
    updateFlow,
    updateWorkflowData,
    addNode,
    updateNode,
    deleteNode,
    exportJson
  };

  return (
    <WorkflowContext.Provider value={contextValue}>
      {children}
    </WorkflowContext.Provider>
  );
};

// Custom hook to use workflow context
export const useWorkflow = () => {
  const context = useContext(WorkflowContext);
  if (!context) {
    throw new Error('useWorkflow must be used within a WorkflowProvider');
  }
  return context;
};

export { WORKFLOW_ACTIONS };