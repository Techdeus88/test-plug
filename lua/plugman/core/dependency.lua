---@class PlugmanDependency
local PlugmanDependency = {}
PlugmanDependency.__index = PlugmanDependency

local utils = require('plugman.core.utils')

---Create new dependency resolver
---@param plugins table<string, PlugmanPlugin>
---@return PlugmanDependency
function PlugmanDependency:new(plugins)
    local dependency = setmetatable({}, self)
    dependency.plugins = plugins
    dependency.resolved = {}
    dependency.visiting = {}
    dependency.logger = utils.create_logger('info')
    return dependency
end

---Resolve all plugin dependencies
---@return table<string, PlugmanPlugin>, string?
function PlugmanDependency:resolve_all()
    self.resolved = {}
    self.visiting = {}

    local ordered_plugins = {}
    local errors = {}

    -- First pass: validate all dependencies exist
    for name, plugin in pairs(self.plugins) do
        local missing_deps = self:_find_missing_dependencies(plugin)
        if #missing_deps > 0 then
            table.insert(errors, string.format('Plugin "%s" has missing dependencies: %s',
                name, table.concat(missing_deps, ', ')))
        end
    end

    if #errors > 0 then
        return {}, table.concat(errors, '; ')
    end

    -- Second pass: resolve dependency order
    for name, plugin in pairs(self.plugins) do
        if not self.resolved[name] then
            local success, err = self:_resolve_plugin(name, ordered_plugins)
            if not success then
                table.insert(errors, err)
            end
        end
    end

    if #errors > 0 then
        return {}, table.concat(errors, '; ')
    end

    -- Convert to ordered table maintaining dependency order
    local result = {}
    for _, plugin in ipairs(ordered_plugins) do
        result[plugin.name] = plugin
    end

    return result, nil
end

---Resolve dependencies for a specific plugin
---@param name string
---@param ordered table
---@return boolean, string?
function PlugmanDependency:_resolve_plugin(name, ordered)
    if self.resolved[name] then
        return true
    end

    if self.visiting[name] then
        return false, string.format('Circular dependency detected involving plugin "%s"', name)
    end

    local plugin = self.plugins[name]
    if not plugin then
        return false, string.format('Plugin "%s" not found', name)
    end

    self.visiting[name] = true

    -- Resolve dependencies first
    for _, dep_name in ipairs(plugin.depends) do
        local success, err = self:_resolve_plugin(dep_name, ordered)
        if not success then
            return false, err
        end
    end

    -- Add current plugin to resolved list
    self.visiting[name] = nil
    self.resolved[name] = true
    table.insert(ordered, plugin)

    self.logger.debug('Resolved plugin: %s', name)

    return true
end

---Find missing dependencies for a plugin
---@param plugin PlugmanPlugin
---@return table
function PlugmanDependency:_find_missing_dependencies(plugin)
    local missing = {}

    for _, dep_name in ipairs(plugin.depends) do
        -- Check if dependency is in our plugin list
        if not self.plugins[dep_name] then
            -- Check if it's already installed (external dependency)
            if not utils.plugin_exists(dep_name) then
                table.insert(missing, dep_name)
            end
        end
    end

    return missing
end

---Get dependency graph for visualization
---@return table
function PlugmanDependency:get_dependency_graph()
    local graph = {
        nodes = {},
        edges = {}
    }

    -- Add nodes
    for name, plugin in pairs(self.plugins) do
        table.insert(graph.nodes, {
            id = name,
            label = name,
            plugin = plugin,
            dependencies = #plugin.depends,
            dependents = self:_count_dependents(name)
        })
    end

    -- Add edges
    for name, plugin in pairs(self.plugins) do
        for _, dep_name in ipairs(plugin.depends) do
            table.insert(graph.edges, {
                from = dep_name,
                to = name,
                type = 'dependency'
            })
        end
    end

    return graph
end

---Count how many plugins depend on this one
---@param name string
---@return number
function PlugmanDependency:_count_dependents(name)
    local count = 0

    for _, plugin in pairs(self.plugins) do
        if utils.contains(plugin.depends, name) then
            count = count + 1
        end
    end

    return count
end

---Get plugins that depend on a specific plugin
---@param name string
---@return table<string, PlugmanPlugin>
function PlugmanDependency:get_dependents(name)
    local dependents = {}

    for plugin_name, plugin in pairs(self.plugins) do
        if utils.contains(plugin.depends, name) then
            dependents[plugin_name] = plugin
        end
    end

    return dependents
end

---Check if removing a plugin would break dependencies
---@param name string
---@return boolean, table
function PlugmanDependency:can_remove(name)
    local dependents = self:get_dependents(name)
    local blocking_dependents = {}

    for dep_name, dep_plugin in pairs(dependents) do
        if dep_plugin.enabled then
            table.insert(blocking_dependents, dep_name)
        end
    end

    return #blocking_dependents == 0, blocking_dependents
end

---Get load order for plugins considering priorities and dependencies
---@return table
function PlugmanDependency:get_load_order()
    local ordered, err = self:resolve_all()
    if err then
        self.logger.error('Failed to resolve dependencies: %s', err)
        return {}
    end

    -- Convert to array and sort by priority and dependency order
    local plugins_array = {}
    for _, plugin in pairs(ordered) do
        table.insert(plugins_array, plugin)
    end

    -- Stable sort by priority (higher priority first)
    -- while maintaining dependency order
    table.sort(plugins_array, function(a, b)
        -- First, ensure dependencies come before dependents
        if utils.contains(a.depends, b.name) then
            return false -- b should come before a
        elseif utils.contains(b.depends, a.name) then
            return true -- a should come before b
        end

        -- Then sort by priority
        if a.priority ~= b.priority then
            return a.priority > b.priority
        end

        -- Finally, maintain stable order by name
        return a.name < b.name
    end)

    return plugins_array
end

---Validate dependency constraints
---@return table
function PlugmanDependency:validate()
    local issues = {}

    -- Check for circular dependencies
    local temp_resolved = {}
    local temp_visiting = {}

    local function check_circular(name, path)
        if temp_visiting[name] then
            table.insert(issues, {
                type = 'circular',
                message = string.format('Circular dependency: %s -> %s',
                    table.concat(path, ' -> '), name),
                plugins = vim.deepcopy(path)
            })
            return
        end

        if temp_resolved[name] then
            return
        end

        local plugin = self.plugins[name]
        if not plugin then
            return
        end

        temp_visiting[name] = true
        table.insert(path, name)

        for _, dep_name in ipairs(plugin.depends) do
            check_circular(dep_name, path)
        end

        table.remove(path)
        temp_visiting[name] = nil
        temp_resolved[name] = true
    end

    for name in pairs(self.plugins) do
        if not temp_resolved[name] then
            check_circular(name, {})
        end
    end

    -- Check for missing dependencies
    for name, plugin in pairs(self.plugins) do
        local missing = self:_find_missing_dependencies(plugin)
        if #missing > 0 then
            table.insert(issues, {
                type = 'missing',
                message = string.format('Plugin "%s" has missing dependencies: %s',
                    name, table.concat(missing, ', ')),
                plugin = name,
                missing_deps = missing
            })
        end
    end

    -- Check for version conflicts (if version info available)
    -- This would be extended based on version requirements

    return issues
end

---Generate dependency report
---@return table
function PlugmanDependency:generate_report()
    local report = {
        total_plugins = 0,
        plugins_with_deps = 0,
        total_dependencies = 0,
        max_depth = 0,
        issues = self:validate(),
        graph = self:get_dependency_graph()
    }

    for name, plugin in pairs(self.plugins) do
        report.total_plugins = report.total_plugins + 1

        if #plugin.depends > 0 then
            report.plugins_with_deps = report.plugins_with_deps + 1
            report.total_dependencies = report.total_dependencies + #plugin.depends
        end

        -- Calculate dependency depth
        local depth = self:_calculate_depth(name, {})
        if depth > report.max_depth then
            report.max_depth = depth
        end
    end

    return report
end

---Calculate dependency depth for a plugin
---@param name string
---@param visited table
---@return number
function PlugmanDependency:_calculate_depth(name, visited)
    if visited[name] then
        return 0 -- Avoid infinite recursion
    end

    local plugin = self.plugins[name]
    if not plugin or #plugin.depends == 0 then
        return 0
    end

    visited[name] = true
    local max_depth = 0

    for _, dep_name in ipairs(plugin.depends) do
        local depth = self:_calculate_depth(dep_name, visited)
        if depth > max_depth then
            max_depth = depth
        end
    end

    visited[name] = nil
    return max_depth + 1
end

return PlugmanDependency
