import React, { useState } from 'react';
import { Search, ChevronRight, ChevronLeft } from 'lucide-react';
import { 
  Sidebar, 
  SidebarContent, 
  SidebarHeader, 
  SidebarMenu, 
  SidebarMenuItem, 
  SidebarMenuButton,
  SidebarGroup,
  SidebarGroupContent,
  SidebarGroupLabel
} from './ui/sidebar.jsx';
import { Input } from './ui/input.jsx';
import { Button } from './ui/button.jsx';

const WorkflowSidebar = ({ 
  searchQuery, 
  onSearchChange, 
  selectedIntegration, 
  onSelectIntegration, 
  integrations, 
  allActions,
  onAddNode 
}) => {
  const filterItems = (items, query) => {
    if (!query || query === "") return items;
    const queryLower = query.toLowerCase();
    return items.filter(item => {
      if (typeof item === 'string') {
        return item.toLowerCase().includes(queryLower);
      }
      // Handle action objects
      if (item && typeof item === 'object') {
        const displayName = item.display_name || item.name || '';
        const description = item.description || '';
        return displayName.toLowerCase().includes(queryLower) || 
               description.toLowerCase().includes(queryLower);
      }
      return false;
    });
  };

  const renderIntegrationActions = () => {
    const integration = integrations.find(i => i.name === selectedIntegration);
    if (!integration) return null;

    return (
      <SidebarGroup>
        <SidebarGroupLabel className="flex items-center justify-between">
          <Button
            variant="ghost" 
            size="sm"
            onClick={() => onSelectIntegration('')}
            className="p-0 h-auto text-xs text-sidebar-foreground hover:text-sidebar-accent-foreground"
          >
            <ChevronLeft className="w-3 h-3 mr-1" />
            Back to integrations
          </Button>
          <span className="text-xs font-medium">{integration.display_name}</span>
        </SidebarGroupLabel>
        <SidebarGroupContent>
          <SidebarMenu>
            {integration.actions.map((action, index) => (
              <SidebarMenuItem key={index}>
                <SidebarMenuButton
                  onClick={() => onAddNode && onAddNode(action.key || action, integration.name)}
                  className="cursor-pointer hover:bg-sidebar-accent hover:text-sidebar-accent-foreground"
                >
                  <span>{action.display_name || action.name || action}</span>
                </SidebarMenuButton>
              </SidebarMenuItem>
            ))}
          </SidebarMenu>
        </SidebarGroupContent>
      </SidebarGroup>
    );
  };

  const renderFilteredActions = () => {
    // Group filtered actions by integration
    const groupedResults = {};
    
    integrations.forEach(integration => {
      const filteredActions = filterItems(integration.actions, searchQuery);
      if (filteredActions.length > 0) {
        groupedResults[integration.name] = filteredActions;
      }
    });
    
    return (
      <div>
        {Object.entries(groupedResults).map(([integrationName, actions]) => {
          // Find the integration to get display_name
          const integration = integrations.find(i => i.name === integrationName);
          const displayName = integration ? integration.display_name : integrationName;
          
          return (
            <SidebarGroup key={integrationName}>
              <SidebarGroupLabel className="flex items-center justify-between">
                <span>{displayName}</span>
                <span className="text-xs text-sidebar-foreground/50">({actions.length})</span>
              </SidebarGroupLabel>
            <SidebarGroupContent>
              <SidebarMenu>
                {actions.map((action, index) => (
                  <SidebarMenuItem key={index}>
                    <SidebarMenuButton
                      onClick={() => onAddNode && onAddNode(action.key || action, integrationName)}
                      className="cursor-pointer hover:bg-sidebar-accent hover:text-sidebar-accent-foreground"
                    >
                      <span>{action.display_name || action.name || action}</span>
                    </SidebarMenuButton>
                  </SidebarMenuItem>
                ))}
              </SidebarMenu>
            </SidebarGroupContent>
            </SidebarGroup>
          );
        })}
        {Object.keys(groupedResults).length === 0 && (
          <SidebarGroup>
            <SidebarGroupLabel>No Results</SidebarGroupLabel>
            <SidebarGroupContent>
              <div className="text-sm text-sidebar-foreground/70 p-2">
                No actions found matching "{searchQuery}"
              </div>
            </SidebarGroupContent>
          </SidebarGroup>
        )}
      </div>
    );
  };

  const renderIntegrations = () => {
    return (
      <SidebarGroup>
        <SidebarGroupLabel>Integrations</SidebarGroupLabel>
        <SidebarGroupContent>
          <SidebarMenu>
            {integrations.map((integration, index) => (
              <SidebarMenuItem key={index}>
                <SidebarMenuButton 
                  onClick={() => onSelectIntegration(integration.name)}
                  isActive={integration.selected}
                  className="flex items-center justify-between"
                >
                  <span>{integration.display_name}</span>
                  {integration.selected && (
                    <ChevronRight className="w-4 h-4" />
                  )}
                </SidebarMenuButton>
              </SidebarMenuItem>
            ))}
          </SidebarMenu>
        </SidebarGroupContent>
      </SidebarGroup>
    );
  };

  return (
    <Sidebar collapsible="offcanvas">
      <SidebarHeader className="p-4 border-b border-sidebar-border">
        <div className="relative">
          <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 w-4 h-4 text-muted-foreground" />
          <Input
            type="text"
            placeholder="Search action"
            value={searchQuery}
            onChange={(e) => onSearchChange(e.target.value)}
            className="pl-10"
          />
        </div>
      </SidebarHeader>
      
      <SidebarContent className="px-4 py-2 flex-1 overflow-y-auto">
        {selectedIntegration ? (
          renderIntegrationActions()
        ) : searchQuery !== "" ? (
          renderFilteredActions()
        ) : (
          renderIntegrations()
        )}
      </SidebarContent>
    </Sidebar>
  );
};

export default WorkflowSidebar;