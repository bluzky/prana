// Utility functions for converting between clean workflow data and React Flow format

export class WorkflowConverter {
  // Generate unique ID for nodes
  static generateNodeId() {
    return 'node_' + Math.random().toString(36).substr(2, 9) + '_' + Date.now().toString(36);
  }

  // Convert clean workflow data to React Flow format
  static convertWorkflowToReactFlow(cleanWorkflow, integrations) {
    if (!cleanWorkflow.nodes) {
      return { nodes: [], edges: [] };
    }

    // Create mapping from node keys to IDs for edge conversion
    const keyToIdMap = {};
    
    const nodes = cleanWorkflow.nodes.map(node => {
      const { input_ports, output_ports, action_display_name } = this.getNodePorts(node.type, integrations);
      
      // Generate unique ID if missing, otherwise use existing ID
      const nodeId = node.id || this.generateNodeId();
      
      // Build key-to-ID mapping
      keyToIdMap[node.key] = nodeId;
      
      return {
        id: nodeId,
        type: 'custom',
        position: {
          x: node.x || 0,
          y: node.y || 0
        },
        data: {
          type: 'action',
          label: node.name,
          action_display_name: action_display_name,
          node_key: node.key,
          node_id: nodeId,
          integration_type: node.type,
          params: node.params || {},
          input_ports,
          output_ports
        }
      };
    });

    const edges = this.convertConnectionsToEdges(cleanWorkflow.connections || {}, keyToIdMap);

    return { nodes, edges };
  }

  // Get input and output ports for a node type
  static getNodePorts(nodeType, integrations) {
    const [integrationName, actionName] = nodeType.split('.');
    
    const integration = integrations.find(i => i.name === integrationName);
    if (!integration || !integration.actions) {
      return { input_ports: ['main'], output_ports: ['main'], action_display_name: actionName };
    }

    // Try to find the action data from integration
    let action_display_name = actionName;
    let input_ports = ['main'];
    let output_ports = ['main', 'error'];
    
    if (integration.actions && Array.isArray(integration.actions)) {
      // Actions is now an array of action objects
      const action = integration.actions.find(a => a.key === actionName);
      if (action) {
        action_display_name = action.display_name || actionName;
        input_ports = action.input_ports || ['main'];
        output_ports = action.output_ports || ['main', 'error'];
      }
    } else if (integration.actions && typeof integration.actions === 'object') {
      // Fallback for object-based actions structure
      const action = integration.actions[actionName];
      if (action) {
        action_display_name = action.display_name || actionName;
        input_ports = action.input_ports || ['main'];
        output_ports = action.output_ports || ['main', 'error'];
      }
    }

    // If no action found, use default ports
    if (!input_ports || !output_ports) {
      const defaultPorts = this.getDefaultPortsForAction(nodeType);
      input_ports = defaultPorts.input_ports;
      output_ports = defaultPorts.output_ports;
    }

    return { input_ports, output_ports, action_display_name };
  }

  // Default port mappings for known action types
  static getDefaultPortsForAction(actionType) {
    switch (actionType) {
      case 'logic.if_condition':
        return { input_ports: ['main'], output_ports: ['true', 'false'] };
      case 'data.merge':
        return { input_ports: ['input_a', 'input_b'], output_ports: ['main', 'error'] };
      case 'manual.trigger':
        return { input_ports: [], output_ports: ['main'] };
      default:
        return { input_ports: ['main'], output_ports: ['main', 'error'] };
    }
  }

  // Convert connections to React Flow edges
  static convertConnectionsToEdges(connections, keyToIdMap = {}) {
    const edges = [];
    
    Object.entries(connections).forEach(([fromNodeKey, ports]) => {
      Object.entries(ports).forEach(([fromPort, connectionsList]) => {
        connectionsList.forEach(conn => {
          // Convert node keys to IDs for React Flow
          const sourceId = keyToIdMap[fromNodeKey] || fromNodeKey;
          const targetId = keyToIdMap[conn.to] || conn.to;
          
          edges.push({
            id: `e${sourceId}-${fromPort}-${targetId}-${conn.to_port}`,
            source: sourceId,
            target: targetId,
            sourceHandle: fromPort,
            targetHandle: conn.to_port
          });
        });
      });
    });
    
    return edges;
  }

  // Convert React Flow data back to clean workflow format
  static convertReactFlowToWorkflow(cleanWorkflow, reactNodes, reactEdges) {
    // Create mapping of React Flow IDs to actual node keys for connections
    const idToKeyMap = {};
    reactNodes.forEach(reactNode => {
      idToKeyMap[reactNode.id] = reactNode.data.node_key || reactNode.id;
    });

    const nodes = reactNodes.map(reactNode => ({
      id: reactNode.data.node_id || reactNode.id, // Preserve unique ID
      key: reactNode.data.node_key || reactNode.id,
      name: reactNode.data.label,
      type: reactNode.data.integration_type,
      params: reactNode.data.params || {},
      x: reactNode.position.x,
      y: reactNode.position.y
    }));

    const connections = this.convertEdgesToConnections(reactEdges, idToKeyMap);

    return {
      ...cleanWorkflow,
      nodes,
      connections
    };
  }

  // Convert React Flow edges back to connections format
  static convertEdgesToConnections(edges, idToKeyMap = {}) {
    const connections = {};
    
    edges.forEach(edge => {
      // Use actual node keys instead of React Flow IDs
      const sourceKey = idToKeyMap[edge.source] || edge.source;
      const targetKey = idToKeyMap[edge.target] || edge.target;
      const sourceHandle = edge.sourceHandle || 'main';
      
      if (!connections[sourceKey]) {
        connections[sourceKey] = {};
      }
      
      if (!connections[sourceKey][sourceHandle]) {
        connections[sourceKey][sourceHandle] = [];
      }
      
      connections[sourceKey][sourceHandle].push({
        to: targetKey,
        from: sourceKey,
        to_port: edge.targetHandle || 'main',
        from_port: sourceHandle
      });
    });
    
    return connections;
  }
}