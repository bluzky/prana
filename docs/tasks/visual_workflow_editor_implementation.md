# Visual Workflow Editor Implementation Task

## Overview

Implement a React Flow-based visual workflow editor for Prana that allows users to create, edit, and manage workflows through a drag-and-drop interface. The editor will integrate with Prana's existing core data structures and execution engine.

## Requirements Summary

1. **Action Search & Discovery**: Users can search for actions and add them to the workflow graph
2. **Node Parameter Management**: Each node supports parameter validation and dynamic field configuration via code editor
3. **Port-to-Port Connections**: Drag and drop connections between node ports with validation
4. **Unique Node Keys**: Each node has a user-defined unique key within the workflow scope

## Design Decisions

### 1. Parameter Input Strategy
- **Approach**: Code editor for manual parameter input as JSON
- **Rationale**: Simple to implement, flexible for complex configurations, familiar to developers
- **Implementation**: JSON editor with syntax highlighting and validation

### 2. Dynamic Port Management
- **Approach**: Remove all related ports and connections when parameters change
- **Rationale**: Prevents invalid connection states, forces user to rebuild connections intentionally
- **Implementation**: Clear connections on parameter change, regenerate ports from new configuration

### 3. Expression System
- **Approach**: Plain text input for Prana expressions (`$input.field`, `$nodes.api.response`)
- **Rationale**: Direct mapping to Prana's expression syntax, no abstraction layer needed
- **Implementation**: Text-based input with syntax validation

### 4. Validation Timing
- **Approach**: Real-time validation as user types
- **Rationale**: Immediate feedback prevents errors, better user experience
- **Implementation**: Debounced validation on parameter changes

### 5. Key Rename Strategy
- **Approach**: Auto-update connections and references, manual update for parameters
- **Rationale**: Maintains graph integrity while giving users control over expression updates
- **Implementation**: Automatic connection updates with user warnings for manual parameter updates

## Technical Architecture

### Phoenix LiveView + React Component Integration
- **Primary Interface**: Phoenix LiveView for server-side reactivity
- **Visual Editor**: React component embedded via LiveView hooks
- **Real-time Sync**: Phoenix channels for multi-user collaboration
- **Data Flow**: JSON messages between LiveView and React component

### Component Stack
- **React** with TypeScript for the visual editor component
- **React Flow** for graph visualization and interaction
- **Monaco Editor** for JSON parameter editing
- **Phoenix LiveView** for server-side state management and validation

### Data Integration
- **LiveView State**: Server-side workflow state management
- **Integration Registry**: Direct access to Prana's IntegrationRegistry
- **Real-time Validation**: Server-side validation via LiveView
- **Persistence**: Native Elixir workflow serialization

## Implementation Phases

### Phase 1: Core Infrastructure
**Goal**: Basic LiveView + React integration

#### 1.1 LiveView Hook Setup
- [ ] Create LiveView hook for React component communication (`workflow_editor_hook.js`)
- [ ] Design JSON message protocol between LiveView and React
- [ ] Set up React component mounting and unmounting lifecycle
- [ ] Configure esbuild for React/TypeScript compilation
- [ ] Install React Flow and Monaco Editor dependencies

#### 1.2 LiveView Module
- [ ] Create `WorkflowEditorLive` LiveView module
- [ ] Implement workflow state management in LiveView
- [ ] Add integration registry data loading from Prana
- [ ] Set up real-time validation via server-side events

#### 1.2 Basic Node System
- [ ] Create base node component with port rendering
- [ ] Implement node selection and positioning
- [ ] Add node deletion functionality
- [ ] Create node property panel with JSON editor

#### 1.3 Connection System
- [ ] Implement port-to-port drag connections
- [ ] Add connection validation rules
- [ ] Create visual feedback for valid/invalid connections
- [ ] Implement connection deletion

### Phase 2: Integration Catalog
**Goal**: Dynamic node creation from Prana integrations

#### 2.1 Action Search
- [ ] Create searchable action catalog sidebar
- [ ] Implement integration filtering (Manual, Logic, Data, Workflow)
- [ ] Add fuzzy search for action names and descriptions
- [ ] Create recently used actions section

#### 2.2 Node Creation
- [ ] Implement drag-and-drop from catalog to canvas
- [ ] Auto-generate unique node keys with user override
- [ ] Auto-position new nodes to avoid overlaps
- [ ] Load integration definitions to configure node ports

#### 2.3 Integration Data Loading
- [ ] Create integration definition JSON schema
- [ ] Implement JSON file loading and parsing
- [ ] Add integration definition validation
- [ ] Handle missing or malformed integration data
- [ ] Create integration data hot-reloading for development

### Phase 3: Advanced Node Features
**Goal**: Full parameter management and validation

#### 3.1 Parameter Management
- [ ] Implement JSON schema validation for parameters
- [ ] Add real-time parameter validation with error display
- [ ] Create parameter templates for common configurations
- [ ] Add parameter auto-completion for expressions

#### 3.2 Dynamic Port System
- [ ] Implement port regeneration on parameter changes
- [ ] Add connection removal when ports become invalid
- [ ] Create port conflict resolution UI
- [ ] Add port type indicators and tooltips

#### 3.3 Node Key Management
- [ ] Implement unique key validation across workflow
- [ ] Add key rename functionality with auto-updates
- [ ] Create reference tracking and update warnings
- [ ] Add key format validation (identifier rules)

### Phase 4: Workflow Management
**Goal**: Complete workflow lifecycle management

#### 4.1 Workflow Operations
- [ ] Implement workflow save/load functionality
- [ ] Add workflow validation before execution
- [ ] Create workflow export/import features
- [ ] Add workflow version management

#### 4.2 Execution Integration
- [ ] Create execution monitoring overlay
- [ ] Add real-time execution status updates
- [ ] Implement execution history visualization
- [ ] Add execution debugging tools

#### 4.3 Error Handling
- [ ] Implement comprehensive error display system
- [ ] Add workflow validation error reporting
- [ ] Create connection error visualization
- [ ] Add recovery suggestions for common errors

## Data Models

### Node Data Structure
```typescript
interface PranaNode {
  id: string;                    // React Flow node ID
  type: 'pranaAction' | 'pranaTrigger';
  data: {
    key: string;                 // User-defined unique key
    integration: string;         // Integration name (manual, logic, etc.)
    action: string;             // Action name within integration
    params: Record<string, any>; // JSON parameters
    ports: {
      input: string[];          // Available input port names
      output: string[];         // Available output port names
    };
    validation?: {
      errors: ValidationError[];
      warnings: ValidationWarning[];
    };
  };
  position: { x: number; y: number };
}
```

### Connection Data Structure
```typescript
interface PranaConnection {
  id: string;                   // React Flow edge ID
  source: string;              // Source node ID
  sourceHandle: string;        // Source port name
  target: string;              // Target node ID  
  targetHandle: string;        // Target port name
  type?: 'success' | 'error' | 'default';
  data?: {
    condition?: string;        // Optional connection condition
  };
}
```

### Workflow Data Structure
```typescript
interface WorkflowData {
  id: string;
  name: string;
  description?: string;
  nodes: PranaNode[];
  connections: PranaConnection[];
  variables: Record<string, any>;
  version: number;
}
```

## Data Specifications

### Integration Definitions JSON
**File**: `editor/src/data/integrations.json`
```json
{
  "integrations": {
    "manual": {
      "name": "manual",
      "display_name": "Manual",
      "description": "Test actions for development and testing workflows",
      "icon": "hand",
      "color": "#3b82f6",
      "actions": {
        "trigger": {
          "name": "trigger",
          "display_name": "Trigger",
          "description": "Workflow trigger point",
          "input_ports": [],
          "output_ports": ["success"]
        },
        "validate": {
          "name": "validate",
          "display_name": "Validate",
          "description": "Validate input data",
          "input_ports": ["input"],
          "output_ports": ["success", "error"],
          "parameter_schema": {
            "field": {
              "type": "string",
              "required": true,
              "description": "Field to validate"
            },
            "required": {
              "type": "boolean", 
              "required": false,
              "default": true
            }
          }
        },
        "process_adult": {
          "name": "process_adult",
          "display_name": "Process Adult",
          "description": "Process adult user data",
          "input_ports": ["input"],
          "output_ports": ["success", "error"]
        },
        "process_minor": {
          "name": "process_minor", 
          "display_name": "Process Minor",
          "description": "Process minor user data",
          "input_ports": ["input"],
          "output_ports": ["success", "error"]
        }
      }
    },
    "logic": {
      "name": "logic",
      "display_name": "Logic",
      "description": "Conditional branching and routing logic",
      "icon": "git-branch",
      "color": "#10b981",
      "actions": {
        "if_condition": {
          "name": "if_condition",
          "display_name": "If Condition",
          "description": "IF/ELSE conditional branching",
          "input_ports": ["input"],
          "output_ports": ["true", "false"],
          "parameter_schema": {
            "condition": {
              "type": "string",
              "required": true,
              "description": "Boolean expression to evaluate"
            }
          }
        },
        "switch": {
          "name": "switch",
          "display_name": "Switch",
          "description": "Multi-path routing based on values",
          "input_ports": ["input"],
          "output_ports": ["default"],
          "parameter_schema": {
            "cases": {
              "type": "array",
              "required": true,
              "description": "Array of case definitions"
            },
            "default_port": {
              "type": "string",
              "required": false,
              "default": "default"
            }
          }
        }
      }
    },
    "data": {
      "name": "data",
      "display_name": "Data",
      "description": "Data merging and transformation operations",
      "icon": "database",
      "color": "#f59e0b",
      "actions": {
        "merge": {
          "name": "merge",
          "display_name": "Merge",
          "description": "Merge data from multiple sources",
          "input_ports": ["input_a", "input_b"],
          "output_ports": ["success"],
          "parameter_schema": {
            "strategy": {
              "type": "string",
              "required": false,
              "default": "append",
              "description": "Merge strategy: append, merge, concat"
            }
          }
        }
      }
    },
    "workflow": {
      "name": "workflow",
      "display_name": "Workflow",
      "description": "Sub-workflow orchestration and coordination",
      "icon": "workflow",
      "color": "#8b5cf6",
      "actions": {
        "execute_workflow": {
          "name": "execute_workflow",
          "display_name": "Execute Workflow",
          "description": "Execute a sub-workflow",
          "input_ports": ["input"],
          "output_ports": ["success", "error"],
          "parameter_schema": {
            "workflow_id": {
              "type": "string",
              "required": true,
              "description": "ID of workflow to execute"
            },
            "execution_mode": {
              "type": "string",
              "required": false,
              "default": "sync",
              "description": "Execution mode: sync, async, fire_and_forget"
            },
            "timeout_ms": {
              "type": "number",
              "required": false,
              "description": "Timeout in milliseconds"
            }
          }
        }
      }
    }
  }
}
```

### Workflow Export Format
**Compatible with**: `Prana.Workflow.from_map/1`
```typescript
interface PranaWorkflowExport {
  id: string;
  name: string;
  description?: string;
  version: number;
  nodes: Array<{
    key: string;
    name: string;
    type: string;  // "integration.action" format
    params: Record<string, any>;
  }>;
  connections: {
    [node_key: string]: {
      [output_port: string]: Array<{
        from: string;
        from_port: string;
        to: string;
        to_port: string;
        condition?: string;
      }>;
    };
  };
  variables?: Record<string, any>;
}
```

## Component Architecture

### Core Components
```
App
├── WorkflowEditor
│   ├── Canvas (React Flow)
│   │   ├── PranaNode
│   │   │   ├── NodeHeader
│   │   │   ├── PortContainer
│   │   │   └── NodeStatus
│   │   └── PranaEdge
│   ├── ActionCatalog
│   │   ├── SearchBar
│   │   ├── IntegrationFilter
│   │   └── ActionList
│   ├── PropertyPanel
│   │   ├── NodeKeyEditor
│   │   ├── ParameterEditor (Monaco)
│   │   └── ValidationErrors
│   └── Toolbar
│       ├── WorkflowActions
│       ├── ViewControls
│       └── ExecutionControls
└── Providers
    ├── WorkflowProvider
    ├── IntegrationProvider
    └── ValidationProvider
```

## Validation Rules

### Node Key Validation
- Must be unique within workflow
- Must be valid identifier (letters, numbers, underscores)
- Cannot be reserved words (input, variables, nodes)
- Length between 1-50 characters
- Cannot start with number

### Parameter Validation
- Must be valid JSON syntax
- Expression syntax validation for `$input.field` patterns
- Required field presence checking
- Type validation where schemas are available

### Connection Validation
- Output port can connect to input port only
- Each input port accepts maximum one connection
- Port names must exist on source and target nodes
- No circular dependencies in workflow graph

## Testing Strategy

### Unit Tests
- Node component rendering and interaction
- Parameter validation logic
- Expression parsing and validation
- Key uniqueness checking
- Connection validation rules

### Integration Tests
- Workflow save/load operations
- Integration registry API integration
- Real-time validation feedback
- Node creation and deletion flows

### E2E Tests
- Complete workflow creation flow
- Search and add actions
- Parameter editing and validation
- Connection creation and validation
- Workflow execution monitoring

## Performance Considerations

### Optimization Strategies
- Debounced validation to prevent excessive API calls
- Virtual scrolling for large action catalogs
- Memoized node components to prevent unnecessary re-renders
- Efficient connection validation using lookup maps
- Lazy loading of integration definitions

### Scalability Targets
- Support workflows with 100+ nodes
- Sub-second response for validation operations
- Smooth interaction with 1000+ available actions
- Real-time updates for collaborative editing

## Security Considerations

### Input Validation
- Sanitize all user inputs to prevent XSS
- Validate JSON parameters against schemas
- Prevent injection attacks in expressions
- Limit parameter size and complexity

### API Security
- Authenticate all API requests
- Validate workflow ownership before operations
- Rate limit validation and save operations
- Audit workflow modifications

## Deployment Strategy

### Development Environment
- Vite development server with hot reload (`npm run dev`)
- Static JSON files for integration definitions
- Local storage for workflow persistence
- Browser dev tools integration

### Production Environment
- Static site generation (`npm run build`)
- CDN deployment (Vercel, Netlify, or S3)
- Asset optimization and caching
- Progressive web app capabilities
- Optional: Integration with Prana backend for workflow execution

## Success Metrics

### User Experience
- Time to create first workflow < 5 minutes
- Error rate in workflow validation < 5%
- User satisfaction score > 4/5
- Feature adoption rate > 80%

### Technical Performance
- Page load time < 2 seconds
- Validation response time < 500ms
- 99.9% uptime availability
- Zero data loss incidents

## Future Enhancements

### Phase 5: Advanced Features
- Workflow templates and marketplace
- Collaborative editing with real-time sync
- Version control and branching
- Advanced debugging and profiling tools
- Custom integration development tools

### Phase 6: Enterprise Features
- Role-based access control
- Workflow approval workflows
- Audit logging and compliance
- Enterprise SSO integration
- Advanced monitoring and alerting

## Dependencies

### Node.js Project Dependencies
**File**: `editor/package.json`
```json
{
  "name": "prana-workflow-editor",
  "private": true,
  "version": "0.1.0",
  "type": "module",
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "reactflow": "^11.10.0",
    "@monaco-editor/react": "^4.6.0",
    "lucide-react": "^0.400.0",
    "clsx": "^2.0.0"
  },
  "devDependencies": {
    "@types/react": "^18.2.0",
    "@types/react-dom": "^18.2.0",
    "@typescript-eslint/eslint-plugin": "^6.0.0",
    "@typescript-eslint/parser": "^6.0.0",
    "@vitejs/plugin-react": "^4.0.0",
    "eslint": "^8.45.0",
    "eslint-plugin-react-hooks": "^4.6.0",
    "eslint-plugin-react-refresh": "^0.4.3",
    "typescript": "^5.0.2",
    "vite": "^4.4.5"
  }
}
```

### Project Structure
```
editor/
├── src/
│   ├── components/
│   │   ├── Canvas/
│   │   ├── Nodes/
│   │   ├── ActionCatalog/
│   │   └── PropertyPanel/
│   ├── data/
│   │   └── integrations.json
│   ├── hooks/
│   ├── types/
│   ├── utils/
│   └── App.tsx
├── public/
├── package.json
├── tsconfig.json
├── vite.config.ts
└── README.md
```

## Risk Assessment

### Technical Risks
- **High**: Complex state management between React Flow and Prana data models
- **Medium**: Performance with large workflows
- **Low**: Integration with existing Prana codebase

### Mitigation Strategies
- Prototype core integration early
- Implement performance monitoring from start
- Regular sync with Prana core team
- Incremental rollout with feature flags

## Conclusion

This implementation plan provides a structured approach to building a visual workflow editor that integrates seamlessly with Prana's existing architecture. The phased approach allows for iterative development and early user feedback while maintaining technical quality and performance standards.