import React, { useState, useRef, useEffect } from 'react';
import { createRoot } from 'react-dom/client';
import { ReactFlow, Controls, Background, addEdge, useNodesState, useEdgesState, Handle, Position } from '@xyflow/react';
import { PanelLeft, Download, Settings, Trash2, Play, MapPin, GitBranch, GitFork, Globe, Zap, FileText, ArrowLeftRight } from 'lucide-react';
import { SidebarProvider, SidebarInset, SidebarTrigger } from './ui/sidebar.jsx';
import { Button } from './ui/button.jsx';
import { Input } from './ui/input.jsx';
import { Dialog, DialogContent, DialogHeader, DialogFooter, DialogTitle, DialogClose } from './ui/dialog.jsx';
import { Label } from './ui/label.jsx';
import { Tabs, TabsList, TabsTrigger, TabsContent } from './ui/tabs.jsx';
import WorkflowSidebar from './WorkflowSidebar.jsx';
import { useWorkflow } from '../contexts/WorkflowContext.js';
import dagre from 'dagre';

// Auto-layout function using dagre
const getLayoutedElements = (nodes, edges, direction = 'TB') => {
  const dagreGraph = new dagre.graphlib.Graph();
  dagreGraph.setDefaultEdgeLabel(() => ({}));

  const nodeWidth = 250;
  const nodeHeight = 80;

  const isHorizontal = direction === 'LR';
  dagreGraph.setGraph({ rankdir: direction });

  nodes.forEach((node) => {
    dagreGraph.setNode(node.id, { width: nodeWidth, height: nodeHeight });
  });

  edges.forEach((edge) => {
    dagreGraph.setEdge(edge.source, edge.target);
  });

  dagre.layout(dagreGraph);

  const newNodes = nodes.map((node) => {
    const nodeWithPosition = dagreGraph.node(node.id);
    const newNode = {
      ...node,
      targetPosition: isHorizontal ? 'left' : 'top',
      sourcePosition: isHorizontal ? 'right' : 'bottom',
      position: {
        x: nodeWithPosition.x - nodeWidth / 2,
        y: nodeWithPosition.y - nodeHeight / 2,
      },
    };

    return newNode;
  });

  return { nodes: newNodes, edges };
};

// NodeEditDialog component
const NodeEditDialog = ({ node, isOpen, onClose, onSave }) => {
  const [nodeKey, setNodeKey] = useState('');
  const [jsonParams, setJsonParams] = useState('{}');
  const [activeTab, setActiveTab] = useState('params');
  const editorRef = useRef(null);
  const monacoEditorRef = useRef(null);

  useEffect(() => {
    if (node && isOpen) {
      // Access data from React Flow node structure
      const nodeKey = node.data?.node_key || node.node_key || '';
      const params = node.data?.params || node.params || {};

      setNodeKey(nodeKey);
      const paramString = JSON.stringify(params, null, 2);
      setJsonParams(paramString);

      // Initialize Monaco editor when dialog opens
      setTimeout(() => initializeNodeEditor(paramString), 100);
    }
  }, [node, isOpen]);

  // Cleanup Monaco editor when dialog closes
  useEffect(() => {
    if (!isOpen && monacoEditorRef.current) {
      monacoEditorRef.current.dispose();
      monacoEditorRef.current = null;
    }
  }, [isOpen]);

  const initializeNodeEditor = (initialValue) => {
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
        data: {
          ...node.data,
          node_key: nodeKey,
          params: params
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
      <DialogContent className="max-w-4xl w-[90vw]">
        <DialogHeader>
          <DialogTitle className="flex items-center space-x-2">
            <Settings className="w-5 h-5" />
            <span>{node?.data?.action_name || node?.data?.label || 'Edit Node'}</span>
          </DialogTitle>
          <DialogClose onClick={handleClose} />
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
                style={{ height: '300px', width: '100%' }}
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

// We'll define nodeTypes here since we need the CustomNode
const CustomNode = ({ data, selected }) => {

  const getNodeIcon = (integration_type, action_display_name) => {
    const iconClass = "w-8 h-8 rounded flex items-center justify-center text-white";

    // Special actions with custom icons and colors
    const specialActions = {
      // Trigger actions
      'manual.trigger': {
        color: 'bg-green-500',
        icon: <Zap className="w-4 h-4" />
      },

      // Logic actions
      'logic.if_condition': {
        color: 'bg-amber-500',
        icon: <ArrowLeftRight className="w-4 h-4" />
      },
      'logic.switch': {
        color: 'bg-orange-500',
        icon: <GitBranch className="w-4 h-4" />
      },

      // Data actions
      'data.merge': {
        color: 'bg-blue-500',
        icon: <GitFork className="w-4 h-4" />
      },

      // HTTP actions
      'http.request': {
        color: 'bg-purple-500',
        icon: <Globe className="w-4 h-4" />
      },

      // Workflow actions
      'workflow.execute_workflow': {
        color: 'bg-indigo-500',
        icon: <Play className="w-4 h-4" />
      }
    };

    // Check if this is a special action
    const specialAction = specialActions[integration_type];
    if (specialAction) {
      return <div className={`${iconClass} ${specialAction.color}`}>{specialAction.icon}</div>;
    }
    
    // Check if action display name contains "trigger" (case insensitive)
    if (action_display_name && action_display_name.toLowerCase().includes('trigger')) {
      return <div className={`${iconClass} bg-green-500`}><Zap className="w-4 h-4" /></div>;
    }

    // Default icon for other actions
    return <div className={`${iconClass} bg-gray-500`}><FileText className="w-4 h-4" /></div>;
  };

  // Get port colors based on port names
  const getPortColor = (portName) => {
    switch (portName) {
      case 'main': return '#3b82f6'; // blue-500
      case 'true': return '#10b981'; // green-500
      case 'false': return '#ef4444'; // red-500
      case 'error': return '#ef4444'; // red-500
      case 'timeout': return '#eab308'; // yellow-500
      case 'success': return '#059669'; // green-600
      default: return '#6b7280'; // gray-500
    }
  };

  const inputPorts = data.input_ports || ['main'];
  const outputPorts = data.output_ports || ['main'];

  return (
    <div
      className={`bg-white border-2 rounded-lg shadow-sm min-w-[250px] relative ${selected ? 'border-gray-900' : 'border-gray-200'}`}
      onDoubleClick={(e) => {
        e.stopPropagation();
        data.onDoubleClick && data.onDoubleClick();
      }}
    >
      {/* Input Ports */}
      {inputPorts.map((port, index) => {
        const totalPorts = inputPorts.length;
        const leftPosition = totalPorts === 1 ? 50 : (100 / (totalPorts + 1)) * (index + 1);

        return (
          <React.Fragment key={`input-${port}`}>
            <Handle
              type="target"
              position={Position.Top}
              id={port}
              className="border-2 border-white transition-all duration-150 hover:scale-125"
              style={{
                left: `${leftPosition}%`,
                transform: 'translateX(-50%)',
                top: '-8px',
                width: '12px',
                height: '12px',
                backgroundColor: getPortColor(port)
              }}
              isConnectable={true}
            />
            {totalPorts > 1 && (
              <div
                className="absolute text-xs text-gray-600 font-medium bg-white px-1 rounded"
                style={{
                  left: `${leftPosition}%`,
                  top: '-28px',
                  transform: 'translateX(-50%)'
                }}
              >
                {port}
              </div>
            )}
          </React.Fragment>
        );
      })}

      <div className="p-3">
        <div className="flex items-center space-x-3">
          {getNodeIcon(data.integration_type, data.action_display_name)}
          <div className="flex-1">
            <div className="font-medium text-gray-900 text-sm">
              {data.action_display_name || data.label || data.action_name || 'Untitled'}
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

      {/* Output Ports */}
      {outputPorts.map((port, index) => {
        const totalPorts = outputPorts.length;
        const leftPosition = totalPorts === 1 ? 50 : (100 / (totalPorts + 1)) * (index + 1);

        return (
          <React.Fragment key={`output-${port}`}>
            <Handle
              type="source"
              position={Position.Bottom}
              id={port}
              className="border-2 border-white transition-all duration-150 hover:scale-125"
              style={{
                left: `${leftPosition}%`,
                transform: 'translateX(-50%)',
                bottom: '-8px',
                width: '12px',
                height: '12px',
                backgroundColor: getPortColor(port)
              }}
              isConnectable={true}
            />
            {totalPorts > 1 && (
              <div
                className="absolute text-xs text-gray-600 font-medium bg-white px-1 rounded"
                style={{
                  left: `${leftPosition}%`,
                  bottom: '-28px',
                  transform: 'translateX(-50%)'
                }}
              >
                {port}
              </div>
            )}
          </React.Fragment>
        );
      })}
    </div>
  );
};

const nodeTypes = {
  custom: CustomNode,
};

const WorkflowLayout = ({
  initialWorkflowData,
  initialIntegrations,
  initialAllActions
}) => {
  // Get shared state and actions from context
  const {
    workflowData,
    reactFlowData,
    title,
    integrations,
    allActions,
    initialize,
    updateTitle,
    updateFlow,
    updateWorkflowData,
    addNode,
    updateNode,
    deleteNode,
    exportJson
  } = useWorkflow();

  // Initialize context with data from props
  useEffect(() => {
    initialize(initialWorkflowData, initialIntegrations, initialAllActions);
  }, [initialize, initialWorkflowData, initialIntegrations, initialAllActions]);

  // Local UI state (not workflow data)
  const [dialogNode, setDialogNode] = useState(null);
  const [isDialogOpen, setIsDialogOpen] = useState(false);
  const [showWorkflowJson, setShowWorkflowJson] = useState(false);
  const [searchQuery, setSearchQuery] = useState("");
  const [selectedIntegration, setSelectedIntegration] = useState(null);
  const [selectedNode, setSelectedNode] = useState(null);
  const [isUpdatingJsonEditor, setIsUpdatingJsonEditor] = useState(false);

  // Handle title changes through context
  const handleTitleChange = (newTitle) => {
    updateTitle(newTitle);
  };

  // Initialize Monaco editor when JSON panel is shown
  useEffect(() => {
    if (showWorkflowJson) {
      // Small delay to ensure DOM is ready
      setTimeout(() => {
        const editorContainer = document.getElementById('react-workflow-json-editor');
        if (editorContainer) {
          // Clean up any existing editor first
          if (window.workflowMonacoEditor) {
            window.workflowMonacoEditor.dispose();
            window.workflowMonacoEditor = null;
          }
          initializeWorkflowEditor(editorContainer);
        }
      }, 100);
    } else {
      // Clean up editor when hiding the panel
      if (window.workflowMonacoEditor) {
        window.workflowMonacoEditor.dispose();
        window.workflowMonacoEditor = null;
      }
    }
  }, [showWorkflowJson]);

  // Update Monaco editor when workflow data changes from other sources
  useEffect(() => {
    if (window.workflowMonacoEditor && showWorkflowJson) {
      const currentValue = window.workflowMonacoEditor.getValue();
      const newValue = JSON.stringify(workflowData, null, 2);

      // Only update if the content is different to avoid infinite loops
      if (currentValue !== newValue) {
        setIsUpdatingJsonEditor(true);
        window.workflowMonacoEditor.setValue(newValue);
        // Reset flag after a short delay to allow the change event to be ignored
        setTimeout(() => setIsUpdatingJsonEditor(false), 100);
      }
    }
  }, [workflowData, showWorkflowJson]);

  // Cleanup Monaco editor on unmount
  useEffect(() => {
    return () => {
      if (window.workflowMonacoEditor) {
        window.workflowMonacoEditor.dispose();
        window.workflowMonacoEditor = null;
      }
      // Clear any pending update timeout
      if (window.workflowUpdateTimeout) {
        clearTimeout(window.workflowUpdateTimeout);
        window.workflowUpdateTimeout = null;
      }
    };
  }, []);

  const initializeWorkflowEditor = (container) => {
    // Show the clean workflow data directly
    const initialValue = JSON.stringify(workflowData, null, 2);

    if (typeof require !== 'undefined') {
      require.config({
        paths: {
          'vs': 'https://unpkg.com/monaco-editor@0.44.0/min/vs'
        }
      });

      require(['vs/editor/editor.main'], () => {
        // Create new editor instance
        window.workflowMonacoEditor = monaco.editor.create(container, {
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

        // Handle content changes with debouncing to prevent update loops
        window.workflowMonacoEditor.onDidChangeModelContent(() => {
          // Clear previous timeout
          if (window.workflowUpdateTimeout) {
            clearTimeout(window.workflowUpdateTimeout);
          }
          
          // Debounce updates to prevent rapid firing
          window.workflowUpdateTimeout = setTimeout(() => {
            try {
              const value = window.workflowMonacoEditor.getValue();
              const parsedWorkflow = JSON.parse(value);
              
              // Update workflow data through context
              updateWorkflowData(parsedWorkflow);
            } catch (error) {
              // Invalid JSON - don't update but don't show errors either
              console.log('Invalid JSON in editor:', error.message);
            }
          }, 500); // 500ms debounce
        });

        // Format JSON on Ctrl+Shift+F
        window.workflowMonacoEditor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyMod.Shift | monaco.KeyCode.KeyF, () => {
          window.workflowMonacoEditor.getAction('editor.action.formatDocument').run();
        });
      });
    }
  };

  const openDialog = (node) => {
    setDialogNode(node);
    setIsDialogOpen(true);
  };

  const closeDialog = () => {
    setIsDialogOpen(false);
    setDialogNode(null);
  };

  const saveNodeFromDialog = (updatedNode) => {
    updateNode(updatedNode.id, updatedNode);
  };

  const deleteNodeFromButton = (nodeToDelete) => {
    deleteNode(nodeToDelete.id);
  };

  // Apply auto-layout before initializing React Flow state to prevent flash
  const layoutedData = React.useMemo(() => {
    if (reactFlowData.nodes && reactFlowData.nodes.length > 0) {
      try {
        const { nodes: layoutedNodes, edges: layoutedEdges } = getLayoutedElements(reactFlowData.nodes, reactFlowData.edges);
        return { nodes: layoutedNodes, edges: layoutedEdges };
      } catch (error) {
        console.error('Pre-layout error:', error);
        return reactFlowData;
      }
    }
    return reactFlowData;
  }, [reactFlowData.nodes, reactFlowData.edges]);

  const [nodes, setNodes, onNodesChange] = useNodesState([]);
  const [edges, setEdges, onEdgesChange] = useEdgesState([]);

  // Sync context reactFlowData changes to React Flow local state
  useEffect(() => {
    if (reactFlowData.nodes) {
      setNodes(reactFlowData.nodes);
    }
    if (reactFlowData.edges) {
      setEdges(reactFlowData.edges);
    }
  }, [reactFlowData.nodes, reactFlowData.edges, setNodes, setEdges]);

  const reactFlowInstance = React.useRef(null);

  // Apply fitView only when ReactFlow instance is initialized
  const onReactFlowInit = React.useCallback((instance) => {
    reactFlowInstance.current = instance;
    // Fit view once on initialization
    setTimeout(() => {
      instance.fitView({ padding: 0.1, maxZoom: 1.2 });
    }, 100);
  }, []);

  const nodesWithHandlers = React.useMemo(() =>
    nodes.map(node => ({
      ...node,
      data: {
        ...node.data,
        onGearClick: () => openDialog(node),
        onDoubleClick: () => openDialog(node),
        onDeleteClick: () => deleteNodeFromButton(node)
      }
    })), [nodes]
  );

  const onConnect = React.useCallback((params) => {
    console.log('Connection params:', params);
    const newEdge = {
      ...params,
      id: `e${params.source}-${params.sourceHandle || 'main'}-${params.target}-${params.targetHandle || 'main'}`,
      sourceHandle: params.sourceHandle || 'main',
      targetHandle: params.targetHandle || 'main'
    };
    console.log('Creating new edge:', newEdge);
    setEdges((eds) => addEdge(newEdge, eds));
  }, [setEdges]);

  const onNodeClick = React.useCallback((event, node) => {
    setSelectedNode(node);
  }, []);

  const isInitialRender = React.useRef(true);

  React.useEffect(() => {
    if (isInitialRender.current) {
      isInitialRender.current = false;
      return;
    }

    const timeoutId = setTimeout(() => {
      // Update context with React Flow changes
      updateFlow(nodes, edges);
    }, 100);

    return () => clearTimeout(timeoutId);
  }, [nodes, edges, updateFlow]);

  return (
    <SidebarProvider defaultOpen={true}>
      <div className="flex h-screen w-full">
        <WorkflowSidebar
          searchQuery={searchQuery}
          onSearchChange={setSearchQuery}
          selectedIntegration={selectedIntegration}
          onSelectIntegration={setSelectedIntegration}
          integrations={integrations}
          allActions={allActions}
          onAddNode={addNode}
        />

        <SidebarInset className="flex flex-col relative">
          {/* Main Content - React Flow (behind header, above status bar and JSON editor) */}
          <div className={`absolute top-0 left-0 right-0 ${showWorkflowJson ? 'bottom-80' : 'bottom-8'}`}>
            <ReactFlow
              nodes={nodesWithHandlers}
              edges={edges}
              onNodesChange={onNodesChange}
              onEdgesChange={onEdgesChange}
              onConnect={onConnect}
              onNodeClick={onNodeClick}
              nodeTypes={nodeTypes}
              onInit={onReactFlowInit}
              defaultViewport={{ x: 0, y: 0, zoom: 1 }}
              className="bg-background"
              connectionMode="loose"
              snapToGrid={true}
              snapGrid={[15, 15]}
              defaultEdgeOptions={{
                style: { strokeWidth: 2 }
              }}
            >
              <Background />
              <Controls />
            </ReactFlow>
          </div>

          {/* Transparent Header (overlaid on canvas) */}
          <header className="relative z-10 flex h-12 items-center gap-2 px-4">
            <SidebarTrigger className="h-7 w-7" />
            <div className="flex items-center flex-1">
              <Input
                type="text"
                value={title}
                onChange={(e) => handleTitleChange(e.target.value)}
                className="border-none bg-transparent text-sm font-medium focus-visible:ring-0 focus-visible:ring-offset-0"
                style={{ minWidth: '200px' }}
              />
            </div>
            <div className="flex items-center gap-2">
              <Button onClick={exportJson} size="sm">
                <Download className="w-4 h-4 mr-2" />
                Export JSON
              </Button>
            </div>
          </header>

          {/* Spacer to push status bar to bottom */}
          <div className="flex-1"></div>

          {/* JSON Editor Toggle - Status Bar Style (at bottom) */}
          <div className="relative z-10 border-t bg-muted/50 px-3 py-1 flex items-center justify-between h-8">
            <Button
              variant="ghost"
              size="sm"
              onClick={() => setShowWorkflowJson(!showWorkflowJson)}
              className="flex items-center gap-1 text-xs h-6 px-2 py-1"
            >
              <div className={`w-3 h-3 transition-transform ${showWorkflowJson ? 'rotate-90' : ''}`}>
                ▶
              </div>
              <span>{showWorkflowJson ? 'Hide' : 'Show'} JSON</span>
            </Button>
            <div className="text-xs text-muted-foreground">
              Ready
            </div>
          </div>

          {/* JSON Editor */}
          {showWorkflowJson && (
            <div className="relative z-10 border-t bg-background h-80">
              <div
                id="react-workflow-json-editor"
                className="h-full w-full"
              />
            </div>
          )}
        </SidebarInset>

        <NodeEditDialog
          node={dialogNode}
          isOpen={isDialogOpen}
          onClose={closeDialog}
          onSave={saveNodeFromDialog}
        />
      </div>
    </SidebarProvider>
  );
};

export default WorkflowLayout;
