// Utility functions for converting between clean workflow data and React Flow format

export class WorkflowConverter {
  // Convert clean workflow data to React Flow format
  static convertWorkflowToReactFlow(cleanWorkflow, integrations) {
    if (!cleanWorkflow.nodes) {
      return { nodes: [], edges: [] };
    }

    const nodes = cleanWorkflow.nodes.map(node => {
      const { input_ports, output_ports } = this.getNodePorts(node.type, integrations);
      
      return {
        id: node.key,
        type: 'custom',
        position: {
          x: node.x || 0,
          y: node.y || 0
        },
        data: {
          type: 'action',
          label: node.name,
          node_key: node.key,
          integration_type: node.type,
          input_ports,
          output_ports
        }
      };
    });

    const edges = this.convertConnectionsToEdges(cleanWorkflow.connections || {});

    return { nodes, edges };
  }

  // Get input and output ports for a node type
  static getNodePorts(nodeType, integrations) {
    const [integrationName, actionName] = nodeType.split('.');
    
    const integration = integrations.find(i => i.name === integrationName);
    if (!integration || !integration.actions) {
      return { input_ports: ['main'], output_ports: ['main'] };
    }

    // For now, return default ports - we'll need to enhance this with actual action data
    // This would require passing action specifications from the server
    const defaultPorts = this.getDefaultPortsForAction(nodeType);
    return defaultPorts;
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
  static convertConnectionsToEdges(connections) {
    const edges = [];
    
    Object.entries(connections).forEach(([fromNode, ports]) => {
      Object.entries(ports).forEach(([fromPort, connectionsList]) => {
        connectionsList.forEach(conn => {
          edges.push({
            id: `e${fromNode}-${fromPort}-${conn.to}-${conn.to_port}`,
            source: fromNode,
            target: conn.to,
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
    const nodes = reactNodes.map(reactNode => ({
      key: reactNode.id,
      name: reactNode.data.label,
      type: reactNode.data.integration_type,
      params: reactNode.params || {},
      x: reactNode.position.x,
      y: reactNode.position.y
    }));

    const connections = this.convertEdgesToConnections(reactEdges);

    return {
      ...cleanWorkflow,
      nodes,
      connections
    };
  }

  // Convert React Flow edges back to connections format
  static convertEdgesToConnections(edges) {
    const connections = {};
    
    edges.forEach(edge => {
      const source = edge.source;
      const sourceHandle = edge.sourceHandle || 'main';
      
      if (!connections[source]) {
        connections[source] = {};
      }
      
      if (!connections[source][sourceHandle]) {
        connections[source][sourceHandle] = [];
      }
      
      connections[source][sourceHandle].push({
        to: edge.target,
        from: edge.source,
        to_port: edge.targetHandle || 'main',
        from_port: sourceHandle
      });
    });
    
    return connections;
  }
}