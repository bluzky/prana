// Helper functions for node creation and manipulation

export class NodeHelpers {
  // Generate unique ID for nodes
  static generateNodeId() {
    return 'node_' + Math.random().toString(36).substr(2, 9) + '_' + Date.now().toString(36);
  }

  // Create a new node from an action
  static createNodeFromAction(actionName, integration) {
    const nodeKey = this.generateNodeKey(actionName);
    
    return {
      id: this.generateNodeId(),
      key: nodeKey,
      name: actionName,
      type: `${integration.name}.${actionName}`,
      params: {},
      x: 200,  // Default position
      y: 200
    };
  }

  // Add a node to workflow data
  static addNodeToWorkflow(workflowData, node) {
    const updatedNodes = [node, ...workflowData.nodes];
    return { ...workflowData, nodes: updatedNodes };
  }

  // Generate a unique node key
  static generateNodeKey(actionName) {
    const timestamp = Date.now();
    return `${actionName.toLowerCase().replace(/\s+/g, '_')}_${timestamp}`;
  }
}