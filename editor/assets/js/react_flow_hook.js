import React, { useState, useEffect, useRef } from 'react';
import { createRoot } from 'react-dom/client';
import { ReactFlow, Controls, Background, addEdge, useNodesState, useEdgesState, Handle, Position } from '@xyflow/react';
import { Button } from './components/ui/button.jsx';
import { Dialog, DialogContent, DialogHeader, DialogFooter, DialogTitle, DialogClose } from './components/ui/dialog.jsx';
import { Input } from './components/ui/input.jsx';
import { Label } from './components/ui/label.jsx';
import { Tabs, TabsList, TabsTrigger, TabsContent } from './components/ui/tabs.jsx';
import { Settings, Trash2 } from 'lucide-react';
import WorkflowLayout from './components/WorkflowLayout.jsx';

// Node Edit Dialog Component
const NodeEditDialog = ({ node, isOpen, onClose, onSave }) => {
  const [nodeKey, setNodeKey] = useState('');
  const [jsonParams, setJsonParams] = useState('{}');
  const [activeTab, setActiveTab] = useState('params');
  const editorRef = useRef(null);
  const monacoEditorRef = useRef(null);

  useEffect(() => {
    if (node && isOpen) {
      setNodeKey(node.node_key || '');
      const params = node.params ? JSON.stringify(node.params, null, 2) : '{}';
      setJsonParams(params);
      
      // Initialize Monaco editor when dialog opens
      setTimeout(() => initializeDialogEditor(params), 100);
    }
  }, [node, isOpen]);

  const initializeDialogEditor = (initialValue) => {
    if (!editorRef.current || monacoEditorRef.current) return;

    if (typeof require !== 'undefined') {
      require.config({ 
        paths: { 
          'vs': 'https://unpkg.com/monaco-editor@0.44.0/min/vs' 
        } 
      });

      require(['vs/editor/editor.main'], () => {
        if (monacoEditorRef.current) return;

        monacoEditorRef.current = monaco.editor.create(editorRef.current, {
          value: initialValue,
          language: 'json',
          theme: 'vs-light',
          minimap: { enabled: false },
          lineNumbers: 'on',
          roundedSelection: false,
          scrollBeyondLastLine: false,
          automaticLayout: true,
          fontSize: 13,
          tabSize: 2,
          insertSpaces: true,
          folding: true,
          bracketMatching: 'always',
          autoIndent: 'full',
          formatOnPaste: true,
          formatOnType: true,
          scrollbar: {
            vertical: 'auto',
            horizontal: 'auto',
            useShadows: false
          },
          overviewRulerBorder: false,
          hideCursorInOverviewRuler: true,
          contextmenu: true,
          quickSuggestions: {
            other: true,
            comments: false,
            strings: true
          }
        });

        monacoEditorRef.current.onDidChangeModelContent(() => {
          setJsonParams(monacoEditorRef.current.getValue());
        });

        monacoEditorRef.current.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyMod.Shift | monaco.KeyCode.KeyF, () => {
          monacoEditorRef.current.getAction('editor.action.formatDocument').run();
        });
      });
    }
  };

  const handleSave = () => {
    try {
      const params = JSON.parse(jsonParams);
      onSave({
        ...node,
        node_key: nodeKey,
        params: params,
        data: {
          ...node.data,
          node_key: nodeKey
        }
      });
      onClose();
    } catch (error) {
      alert('Invalid JSON format. Please check your parameters.');
    }
  };

  const handleClose = () => {
    if (monacoEditorRef.current) {
      monacoEditorRef.current.dispose();
      monacoEditorRef.current = null;
    }
    onClose();
  };

  return (
    <Dialog open={isOpen} onOpenChange={(open) => !open && handleClose()}>
      <DialogContent className="max-w-2xl">
        <DialogHeader>
          <DialogTitle className="flex items-center space-x-2">
            <Settings className="w-5 h-5" />
            <span>{node?.data?.action_name || node?.data?.label || 'Edit Node'}</span>
          </DialogTitle>
          <DialogClose />
        </DialogHeader>

        <Tabs value={activeTab} onValueChange={setActiveTab}>
          <TabsList className="grid w-full grid-cols-2">
            <TabsTrigger value="params">Params</TabsTrigger>
            <TabsTrigger value="settings">Settings</TabsTrigger>
          </TabsList>
          
          <TabsContent value="params" className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="node-key">Node Key</Label>
              <Input
                id="node-key"
                type="text"
                value={nodeKey}
                onChange={(e) => setNodeKey(e.target.value)}
                placeholder="Enter node key"
              />
            </div>
            
            <div className="space-y-2">
              <Label>Parameters (JSON)</Label>
              <div 
                ref={editorRef}
                className="border rounded-md"
                style={{ height: '200px', width: '100%' }}
              />
            </div>
          </TabsContent>
          
          <TabsContent value="settings" className="space-y-4">
            <div className="text-sm text-muted-foreground">
              Settings panel coming soon...
            </div>
          </TabsContent>
        </Tabs>

        <DialogFooter>
          <Button variant="outline" onClick={handleClose}>
            Cancel
          </Button>
          <Button onClick={handleSave}>
            Save
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
};

// Custom node component
const CustomNode = ({ data, selected }) => {
  const getNodeIcon = (type) => {
    switch (type) {
      case 'start':
        return (
          <div className="w-8 h-8 bg-purple-500 rounded flex items-center justify-center">
            <svg className="w-4 h-4 text-white" fill="currentColor" viewBox="0 0 20 20">
              <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM9.555 7.168A1 1 0 008 8v4a1 1 0 001.555.832l3-2a1 1 0 000-1.664l-3-2z" clipRule="evenodd" />
            </svg>
          </div>
        );
      case 'action':
        return (
          <div className="w-8 h-8 bg-pink-500 rounded flex items-center justify-center">
            <svg className="w-4 h-4 text-white" fill="currentColor" viewBox="0 0 20 20">
              <path fillRule="evenodd" d="M11.49 3.17c-.38-1.56-2.6-1.56-2.98 0a1.532 1.532 0 01-2.286.948c-1.372-.836-2.942.734-2.106 2.106.54.886.061 2.042-.947 2.287-1.561.379-1.561 2.6 0 2.978a1.532 1.532 0 01.947 2.287c-.836 1.372.734 2.942 2.106 2.106a1.532 1.532 0 012.287.947c.379 1.561 2.6 1.561 2.978 0a1.533 1.533 0 012.287-.947c1.372.836 2.942-.734 2.106-2.106a1.533 1.533 0 01.947-2.287c1.561-.379 1.561-2.6 0-2.978a1.532 1.532 0 01-.947-2.287c.836-1.372-.734-2.942-2.106-2.106a1.532 1.532 0 01-2.287-.947zM10 13a3 3 0 100-6 3 3 0 000 6z" clipRule="evenodd" />
            </svg>
          </div>
        );
      case 'review':
        return (
          <div className="w-8 h-8 bg-orange-500 rounded flex items-center justify-center">
            <svg className="w-4 h-4 text-white" fill="currentColor" viewBox="0 0 20 20">
              <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clipRule="evenodd" />
            </svg>
          </div>
        );
      case 'end':
        return (
          <div className="w-8 h-8 bg-blue-500 rounded flex items-center justify-center">
            <svg className="w-4 h-4 text-white" fill="currentColor" viewBox="0 0 20 20">
              <path fillRule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clipRule="evenodd" />
            </svg>
          </div>
        );
      default:
        return (
          <div className="w-8 h-8 bg-gray-500 rounded flex items-center justify-center">
            <svg className="w-4 h-4 text-white" fill="currentColor" viewBox="0 0 20 20">
              <path fillRule="evenodd" d="M3 4a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1zm0 4a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1zm0 4a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1z" clipRule="evenodd" />
            </svg>
          </div>
        );
    }
  };

  return (
    <div 
      className={`bg-white border-2 rounded-lg shadow-sm min-w-[200px] ${selected ? 'border-gray-900' : 'border-gray-200'}`}
      onDoubleClick={(e) => {
        e.stopPropagation();
        data.onDoubleClick && data.onDoubleClick();
      }}
    >
      <Handle type="target" position={Position.Top} className="w-3 h-3" />
      
      <div className="p-3">
        <div className="flex items-center space-x-3">
          {getNodeIcon(data.type)}
          <div className="flex-1">
            <div className="font-medium text-gray-900 text-sm">
              {data.label || data.action_name || 'Untitled'}
            </div>
            <div className="text-xs text-gray-500">
              {data.subtitle || data.node_key || 'No key'}
            </div>
          </div>
          <div className="flex space-x-1">
            <Button
              variant="ghost"
              size="icon"
              className="h-6 w-6 text-gray-400 hover:text-gray-600"
              onClick={(e) => {
                e.stopPropagation();
                data.onGearClick && data.onGearClick();
              }}
            >
              <Settings className="h-4 w-4" />
            </Button>
            <Button
              variant="ghost"
              size="icon"
              className="h-6 w-6 text-gray-400 hover:text-red-600"
              onClick={(e) => {
                e.stopPropagation();
                data.onDeleteClick && data.onDeleteClick();
              }}
            >
              <Trash2 className="h-4 w-4" />
            </Button>
          </div>
        </div>
      </div>
      
      <Handle type="source" position={Position.Bottom} className="w-3 h-3" />
    </div>
  );
};

// Node types mapping
const nodeTypes = {
  custom: CustomNode,
};

const ReactFlowComponent = ({ initialNodes, initialEdges, onWorkflowChange, onNodeSelect }) => {
  console.log('ReactFlowComponent rendering with:', { initialNodes, initialEdges });
  
  const [dialogNode, setDialogNode] = useState(null);
  const [isDialogOpen, setIsDialogOpen] = useState(false);
  
  const openDialog = (node) => {
    setDialogNode(node);
    setIsDialogOpen(true);
  };
  
  const closeDialog = () => {
    setIsDialogOpen(false);
    setDialogNode(null);
  };
  
  const saveNode = (updatedNode) => {
    // Update the nodes state with the modified node
    setNodes(currentNodes => 
      currentNodes.map(node => 
        node.id === updatedNode.id ? updatedNode : node
      )
    );
  };

  const deleteNode = (nodeToDelete) => {
    // Remove the node from nodes array
    setNodes(currentNodes => 
      currentNodes.filter(node => node.id !== nodeToDelete.id)
    );
    
    // Remove all edges connected to this node
    setEdges(currentEdges => 
      currentEdges.filter(edge => 
        edge.source !== nodeToDelete.id && edge.target !== nodeToDelete.id
      )
    );
  };
  
  const [nodes, setNodes, onNodesChange] = useNodesState(initialNodes);
  
  // Add event handlers to nodes
  const nodesWithHandlers = React.useMemo(() => 
    nodes.map(node => ({
      ...node,
      data: {
        ...node.data,
        onGearClick: () => openDialog(node),
        onDoubleClick: () => openDialog(node),
        onDeleteClick: () => deleteNode(node)
      }
    })), [nodes]
  );
  const [edges, setEdges, onEdgesChange] = useEdgesState(initialEdges);
  console.log('Current state:', { nodes, edges });

  const onConnect = React.useCallback((params) => {
    const newEdge = {
      ...params,
      id: `e${params.source}-${params.target}`,
    };
    setEdges((eds) => addEdge(newEdge, eds));
  }, [setEdges]);

  const onNodeClick = React.useCallback((event, node) => {
    console.log('Node clicked:', node);
    onNodeSelect(node);
  }, [onNodeSelect]);

  // Track if this is the initial render
  const isInitialRender = React.useRef(true);

  // Notify parent component of changes (skip initial render)
  React.useEffect(() => {
    if (isInitialRender.current) {
      isInitialRender.current = false;
      return;
    }

    // Debounce updates to prevent rapid re-renders
    const timeoutId = setTimeout(() => {
      onWorkflowChange({ nodes, edges });
    }, 100);

    return () => clearTimeout(timeoutId);
  }, [nodes, edges, onWorkflowChange]);

  try {
    return (
      <div style={{ height: '100%', width: '100%' }}>
        <ReactFlow
          nodes={nodesWithHandlers}
          edges={edges}
          onNodesChange={onNodesChange}
          onEdgesChange={onEdgesChange}
          onConnect={onConnect}
          onNodeClick={onNodeClick}
          nodeTypes={nodeTypes}
          fitView
        >
          <Background />
          <Controls />
        </ReactFlow>
        
        <NodeEditDialog
          node={dialogNode}
          isOpen={isDialogOpen}
          onClose={closeDialog}
          onSave={saveNode}
        />
      </div>
    );
  } catch (error) {
    console.error('ReactFlow render error:', error);
    return <div>Error rendering ReactFlow: {error.message}</div>;
  }
};

// Export components for use in WorkflowLayout
export { NodeEditDialog, CustomNode, nodeTypes };

const ReactFlowHook = {
  mounted() {
    // Get all data attributes from the element
    const workflowData = JSON.parse(this.el.dataset.workflow || '{"nodes":[],"edges":[]}');
    const workflowTitle = this.el.dataset.workflowTitle || "Workflow Editor";
    const searchQuery = this.el.dataset.searchQuery || "";
    const selectedIntegration = this.el.dataset.selectedIntegration || null;
    const integrations = JSON.parse(this.el.dataset.integrations || '[]');
    const allActions = JSON.parse(this.el.dataset.allActions || '[]');

    // Create React root
    const root = createRoot(this.el);
    this.React = React;
    
    
    // Initialize Monaco Editor if container exists
    this.initializeMonacoEditor();

    // Event handlers
    const onWorkflowChange = ({ nodes, edges }) => {
      if (this.el && this.el.isConnected) {
        this.pushEvent("workflow_changed", {
          nodes: nodes,
          edges: edges
        });
      }
    };

    const onNodeSelect = (node) => {
      if (this.el && this.el.isConnected) {
        this.pushEvent("node_selected", {
          node: node
        });
      }
    };

    const onTitleChange = (title) => {
      if (this.el && this.el.isConnected) {
        this.pushEvent("title_changed", { title });
      }
    };

    const onExportJson = () => {
      if (this.el && this.el.isConnected) {
        this.pushEvent("export_json", {});
      }
    };

    const onSearchChange = (search) => {
      if (this.el && this.el.isConnected) {
        this.pushEvent("search_changed", { search });
      }
    };

    const onSelectIntegration = (integration) => {
      if (this.el && this.el.isConnected) {
        this.pushEvent("select_integration", { integration });
      }
    };

    // Render the full WorkflowLayout with sidebar and header
    root.render(
      React.createElement(WorkflowLayout, {
        initialNodes: workflowData.nodes,
        initialEdges: workflowData.edges,
        workflowTitle,
        onWorkflowChange,
        onNodeSelect,
        onTitleChange,
        onExportJson,
        searchQuery,
        onSearchChange,
        selectedIntegration,
        onSelectIntegration,
        integrations,
        allActions,
        workflowData
      })
    );

    this.root = root;

    // Handle download file event
    this.handleEvent("download_file", ({content, filename, mime_type}) => {
      const blob = new Blob([content], { type: mime_type });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = filename;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
    });

  },

  updated() {
    // Handle workflow data updates
    const workflowData = JSON.parse(this.el.dataset.workflow || '{"nodes":[],"edges":[]}');
    const workflowTitle = this.el.dataset.workflowTitle || "Workflow Editor";
    const searchQuery = this.el.dataset.searchQuery || "";
    const selectedIntegration = this.el.dataset.selectedIntegration || null;
    const integrations = JSON.parse(this.el.dataset.integrations || '[]');
    const allActions = JSON.parse(this.el.dataset.allActions || '[]');

    if (this.root && this.React) {
      const onWorkflowChange = ({ nodes, edges }) => {
        if (this.el && this.el.isConnected) {
          this.pushEvent("workflow_changed", {
            nodes: nodes,
            edges: edges
          });
        }
      };

      const onNodeSelect = (node) => {
        if (this.el && this.el.isConnected) {
          this.pushEvent("node_selected", {
            node: node
          });
        }
      };

      const onTitleChange = (title) => {
        if (this.el && this.el.isConnected) {
          this.pushEvent("title_changed", { title });
        }
      };

      const onExportJson = () => {
        if (this.el && this.el.isConnected) {
          this.pushEvent("export_json", {});
        }
      };

      const onSearchChange = (search) => {
        if (this.el && this.el.isConnected) {
          this.pushEvent("search_changed", { search });
        }
      };

      const onSelectIntegration = (integration) => {
        if (this.el && this.el.isConnected) {
          this.pushEvent("select_integration", { integration });
        }
      };

      // Render the full WorkflowLayout with sidebar and header
      this.root.render(
        React.createElement(WorkflowLayout, {
          initialNodes: workflowData.nodes,
          initialEdges: workflowData.edges,
          workflowTitle,
          onWorkflowChange,
          onNodeSelect,
          onTitleChange,
          onExportJson,
          searchQuery,
          onSearchChange,
          selectedIntegration,
          onSelectIntegration,
          integrations,
          allActions,
          workflowData
        })
      );
    }

    // Update Monaco Editor if it exists
    this.initializeMonacoEditor();
    const editorContainer = document.getElementById('monaco-editor');
    if (editorContainer) {
      const newValue = editorContainer.dataset.value;
      this.updateMonacoEditor(newValue);
    }
  },

  destroyed() {
    if (this.root) {
      this.root.unmount();
    }
    if (this.nodeMonacoEditor) {
      this.nodeMonacoEditor.dispose();
      this.nodeMonacoEditor = null;
    }
    // Workflow JSON editor is now managed by React component
  },

  initializeMonacoEditor() {
    // Initialize node params editor using persistent container
    const nodeEditorContainer = document.getElementById('persistent-monaco-editor');
    if (nodeEditorContainer) {
      if (!this.nodeMonacoEditor) {
        this.createNodeMonacoEditor(nodeEditorContainer);
      } else {
        // Editor exists, just update its value
        const nodeValue = nodeEditorContainer.dataset.value;
        if (nodeValue !== undefined) {
          this.updateNodeEditor(nodeValue);
        }
      }
    }

    // Workflow JSON editor is now managed by React component

  },

  createNodeMonacoEditor(container) {
    const initialValue = container.dataset.value || '{}';
    
    // Don't create if editor already exists
    if (this.nodeMonacoEditor) {
      return;
    }
    
    // Configure Monaco loader for node editor
    if (typeof require !== 'undefined') {
      require.config({ 
        paths: { 
          'vs': 'https://unpkg.com/monaco-editor@0.44.0/min/vs' 
        } 
      });

      // Load Monaco Editor for node params
      require(['vs/editor/editor.main'], () => {
        // Double check editor doesn't exist after async load
        if (this.nodeMonacoEditor) {
          return;
        }

        this.nodeMonacoEditor = monaco.editor.create(container, {
          value: initialValue,
          language: 'json',
          theme: 'vs-light',
          minimap: { enabled: false },
          lineNumbers: 'on',
          roundedSelection: false,
          scrollBeyondLastLine: false,
          automaticLayout: true,
          fontSize: 13,
          tabSize: 2,
          insertSpaces: true,
          folding: true,
          bracketMatching: 'always',
          autoIndent: 'full',
          formatOnPaste: true,
          formatOnType: true,
          scrollbar: {
            vertical: 'auto',
            horizontal: 'auto',
            useShadows: false
          },
          overviewRulerBorder: false,
          hideCursorInOverviewRuler: true,
          contextmenu: true,
          quickSuggestions: {
            other: true,
            comments: false,
            strings: true
          }
        });

        // Handle content changes for node params
        this.nodeMonacoEditor.onDidChangeModelContent(() => {
          if (this.el && this.el.isConnected) {
            const value = this.nodeMonacoEditor.getValue();
            this.pushEvent('update_node_params', { params: value });
          }
        });

        // Format JSON on Ctrl+Shift+F
        this.nodeMonacoEditor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyMod.Shift | monaco.KeyCode.KeyF, () => {
          this.nodeMonacoEditor.getAction('editor.action.formatDocument').run();
        });
      });
    }
  },


  updateMonacoEditor(newValue) {
    // Update node params editor only if it exists and has new value
    const nodeEditorContainer = document.getElementById('persistent-monaco-editor');
    if (nodeEditorContainer && this.nodeMonacoEditor && newValue !== undefined) {
      this.updateNodeEditor(newValue);
    }

    // Workflow JSON editor is now managed by React component

  },

  updateNodeEditor(newValue) {
    if (!this.nodeMonacoEditor) {
      console.log('Node editor not found, trying to create...');
      const nodeEditorContainer = document.getElementById('persistent-monaco-editor');
      if (nodeEditorContainer) {
        this.createNodeMonacoEditor(nodeEditorContainer);
      }
      return;
    }
    
    const currentValue = this.nodeMonacoEditor.getValue();
    
    // Only update if the value actually changed to avoid cursor jumping
    if (newValue !== currentValue) {
      console.log('Updating node editor with new value');
      // Save cursor position
      const position = this.nodeMonacoEditor.getPosition();
      
      // Update value
      this.nodeMonacoEditor.setValue(newValue);
      
      // Restore cursor position if valid
      if (position) {
        this.nodeMonacoEditor.setPosition(position);
      }
      
      // Format the JSON
      setTimeout(() => {
        if (this.nodeMonacoEditor) {
          this.nodeMonacoEditor.getAction('editor.action.formatDocument').run();
        }
      }, 100);
    }
  },


};

export default ReactFlowHook;
