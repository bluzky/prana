import React, { useState, useRef, useEffect } from 'react';
import { createRoot } from 'react-dom/client';
import { ReactFlow, Controls, Background, addEdge, useNodesState, useEdgesState, Handle, Position } from '@xyflow/react';
import { PanelLeft, Download, Settings, Trash2 } from 'lucide-react';
import { SidebarProvider, SidebarInset, SidebarTrigger } from './ui/sidebar.jsx';
import { Button } from './ui/button.jsx';
import { Input } from './ui/input.jsx';
import { Dialog, DialogContent, DialogHeader, DialogFooter, DialogTitle, DialogClose } from './ui/dialog.jsx';
import { Label } from './ui/label.jsx';
import { Tabs, TabsList, TabsTrigger, TabsContent } from './ui/tabs.jsx';
import WorkflowSidebar from './WorkflowSidebar.jsx';

// NodeEditDialog component
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
      setTimeout(() => initializeNodeEditor(params), 100);
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
  
  const getNodeIcon = (type) => {
    const iconClass = "w-8 h-8 rounded flex items-center justify-center text-white";
    const iconSvg = <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
      <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM9.555 7.168A1 1 0 008 8v4a1 1 0 001.555.832l3-2a1 1 0 000-1.664l-3-2z" clipRule="evenodd" />
    </svg>;
    
    switch (type) {
      case 'start':
        return <div className={`${iconClass} bg-purple-500`}>{iconSvg}</div>;
      case 'action':
        return <div className={`${iconClass} bg-pink-500`}>{iconSvg}</div>;
      case 'review':
        return <div className={`${iconClass} bg-orange-500`}>{iconSvg}</div>;
      case 'end':
        return <div className={`${iconClass} bg-blue-500`}>{iconSvg}</div>;
      default:
        return <div className={`${iconClass} bg-gray-500`}>{iconSvg}</div>;
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

const nodeTypes = {
  custom: CustomNode,
};

const WorkflowLayout = ({ 
  initialNodes, 
  initialEdges, 
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
}) => {
  const [dialogNode, setDialogNode] = useState(null);
  const [isDialogOpen, setIsDialogOpen] = useState(false);
  const [showWorkflowJson, setShowWorkflowJson] = useState(false);
  
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

  // Cleanup Monaco editor on unmount
  useEffect(() => {
    return () => {
      if (window.workflowMonacoEditor) {
        window.workflowMonacoEditor.dispose();
        window.workflowMonacoEditor = null;
      }
    };
  }, []);

  const initializeWorkflowEditor = (container) => {
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

        // Handle content changes
        window.workflowMonacoEditor.onDidChangeModelContent(() => {
          const value = window.workflowMonacoEditor.getValue();
          console.log("JSON editor content changed:", value);
          // We could add a callback here to update the workflow data
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
  
  const saveNode = (updatedNode) => {
    setNodes(currentNodes => 
      currentNodes.map(node => 
        node.id === updatedNode.id ? updatedNode : node
      )
    );
  };

  const deleteNode = (nodeToDelete) => {
    setNodes(currentNodes => 
      currentNodes.filter(node => node.id !== nodeToDelete.id)
    );
    
    setEdges(currentEdges => 
      currentEdges.filter(edge => 
        edge.source !== nodeToDelete.id && edge.target !== nodeToDelete.id
      )
    );
  };
  
  const [nodes, setNodes, onNodesChange] = useNodesState(initialNodes);
  
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

  const onConnect = React.useCallback((params) => {
    const newEdge = {
      ...params,
      id: `e${params.source}-${params.target}`,
    };
    setEdges((eds) => addEdge(newEdge, eds));
  }, [setEdges]);

  const onNodeClick = React.useCallback((event, node) => {
    onNodeSelect(node);
  }, [onNodeSelect]);

  const isInitialRender = React.useRef(true);

  React.useEffect(() => {
    if (isInitialRender.current) {
      isInitialRender.current = false;
      return;
    }

    const timeoutId = setTimeout(() => {
      onWorkflowChange({ nodes, edges });
    }, 100);

    return () => clearTimeout(timeoutId);
  }, [nodes, edges, onWorkflowChange]);

  return (
    <SidebarProvider defaultOpen={true}>
      <div className="flex h-screen w-full">
        <WorkflowSidebar 
          searchQuery={searchQuery}
          onSearchChange={onSearchChange}
          selectedIntegration={selectedIntegration}
          onSelectIntegration={onSelectIntegration}
          integrations={integrations}
          allActions={allActions}
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
              fitView
              className="bg-background"
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
                value={workflowTitle}
                onChange={(e) => onTitleChange(e.target.value)}
                className="border-none bg-transparent text-sm font-medium focus-visible:ring-0 focus-visible:ring-offset-0"
                style={{ minWidth: '200px' }}
              />
            </div>
            <div className="flex items-center gap-2">
              <Button onClick={onExportJson} size="sm">
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
                data-value={JSON.stringify(workflowData, null, 2)}
                className="h-full w-full"
              />
            </div>
          )}
        </SidebarInset>
        
        <NodeEditDialog
          node={dialogNode}
          isOpen={isDialogOpen}
          onClose={closeDialog}
          onSave={saveNode}
        />
      </div>
    </SidebarProvider>
  );
};

export default WorkflowLayout;