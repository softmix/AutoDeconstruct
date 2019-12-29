require "util"
require "config"

local function find_resource_at(surface, position, range, resource_category)
    local resource_category = resource_category or 'basic-solid'
    local top_left = {x = position.x - range, y = position.y - range}
    local bottom_right = {x = position.x + range, y = position.y + range}

    local resources = surface.find_entities_filtered{area={top_left, bottom_right}, type='resource'}
    categorized = {}
    for _, resource in pairs(resources) do
        if resource.prototype.resource_category == resource_category then
            table.insert(categorized, resource)
        end
    end
    return categorized
end

local function find_all_entities(entity_type)
    local surface = game.surfaces['nauvis']
    local entities = {}
    for chunk in surface.get_chunks() do
        local chunk_area = {lefttop = {x = chunk.x*32, y = chunk.y*32}, rightbottom = {x = chunk.x*32+32, y = chunk.y*32+32}}
        local chunk_entities = surface.find_entities_filtered({area = chunk_area, type = entity_type})
        for i = 1, #chunk_entities do
            entities[#entities + 1] = chunk_entities[i]
        end
    end
    return entities
end

local function find_target(entity)
    if entity.drop_target then
        return entity.drop_target
    else
        local entities = entity.surface.find_entities_filtered{position=entity.drop_position}
        if global.debug then msg_all({"autodeconstruct-debug", "found " .. entities[1].name .. " at " .. util.positiontostr(entities[1].position)}) end
        return entities[1]
    end
end

local function find_targeting(entity)
    local range = global.max_range
    local position = entity.position

    local top_left = {x = position.x - range, y = position.y - range}
    local bottom_right = {x = position.x + range, y = position.y + range}

    local surface = entity.surface
    local entities = {}
    local targeting = {}

    local entities = surface.find_entities_filtered{area={top_left, bottom_right}, type='mining-drill'}
    for i = 1, #entities do
        if find_target(entities[i]) == entity then 
            targeting[#targeting + 1] = entities[i]
        end
    end

    entities = surface.find_entities_filtered{area={top_left, bottom_right}, type='inserter'}
    for i = 1, #entities do
        if find_target(entities[i]) == entity then 
            targeting[#targeting + 1] = entities[i]
        end
    end
    if global.debug then msg_all({"autodeconstruct-debug", "found " .. #targeting .. " targeting"}) end
    return targeting
end

local function find_drills(entity)
    local range = global.max_range
    local position = entity.position

    local top_left = {x = position.x - range, y = position.y - range}
    local bottom_right = {x = position.x + range, y = position.y + range}

    local surface = game.surfaces['nauvis']
    local entities = {}
    local targeting = {}

    local entities = surface.find_entities_filtered{area={top_left, bottom_right}, type='mining-drill'}
    if global.debug then msg_all({"autodeconstruct-debug", "found " .. #entities  .. " drills"}) end
    for i = 1, #entities do
        -- hack because resource_searching_radius is hidden at runtime, see data-final-fixes.lua
        drill_range = entities[i].force.technologies["data-dummy-" .. entities[i].name].research_unit_energy / 60
        if math.abs(entities[i].position.x - position.x) < drill_range and math.abs(entities[i].position.y - position.y) < drill_range then
            if global.debug then msg_all({"autodeconstruct-debug", "checking drill " .. i }) end
            autodeconstruct.check_drill(entities[i])
        end
    end
end

function autodeconstruct.init_globals()
    global = {
        max_range = game.forces.neutral.technologies["data-dummy-max-range"].research_unit_energy / 60 / 2
    }
    drill_entities = find_all_entities('mining-drill')
    for _, drill_entity in pairs(drill_entities) do
        autodeconstruct.check_drill(drill_entity)
    end
end

function autodeconstruct.on_resource_depleted(event)
    if event.entity.prototype.resource_category ~= 'basic-solid' or event.entity.prototype.infinite_resource ~= false then
        if global.debug then msg_all({"autodeconstruct-debug", game.tick .. " resource_category " .. event.entity.prototype.resource_category .. " infinite_resource " .. (event.entity.prototype.infinite_resource == true and "true" or "false" )}) end
        return
    end
    drill = find_drills(event.entity)
end

function autodeconstruct.check_drill(drill)
    -- hack because resource_searching_radius is hidden at runtime, see data-final-fixes.lua
    local range = drill.force.technologies["data-dummy-" .. drill.name].research_unit_energy / 60

    if range == nil then return end 
    if range < .5 then return end
    
    resources = find_resource_at(drill.surface, drill.position, range)
    for i = 1, #resources do
        if resources[i].amount > 0 then return end
    end
    if global.debug then msg_all({"autodeconstruct-debug", " found no resources for drill at " .. util.positiontostr(drill.position) .. ", deconstructing"}) end
    autodeconstruct.order_deconstruction(drill)
end

function autodeconstruct.order_deconstruction(drill)
    if drill.to_be_deconstructed(drill.force) then
        if global.debug then msg_all({"autodeconstruct-debug", debug.getinfo(2).name, " already marked"}) end
        return
    end
    
    local deconstruct = false
--[[ #TODO
config.lua: autodeconstruct.wait_for_robots = false
    if autodeconstruct.wait_for_robots then
        logistic_network = drill.surface.find_logistic_network_by_position(drill.position, drill.force.name)
        if logistic_network ~= nil then
            if logistic_network.available_construction_robots > 0 then
                deconstruct = true
            end
        end
    else
        deconstruct = true
    end
--]]
    deconstruct = true
--[[ END TODO

--]]
    if deconstruct == true and drill.minable then
        if drill.order_deconstruction(drill.force) then
            if global.debug then msg_all({"autodeconstruct-debug", drill.name .. " at " .. util.positiontostr(drill.position) .. " success"}) end
        else
            if global.debug then msg_all({"autodeconstruct-debug", drill.name .. " at " .. util.positiontostr(drill.position) .. " success"}) end
        end
        if autodeconstruct.remove_target then
            target = find_target(drill)
            if target ~= nil and target.minable then
                if target.type == "logistic-container" or target.type == "container" then
                    targeting = find_targeting(target)
                    if targeting ~= nil then
                        for i = 1, #targeting do
                            if not targeting[i].to_be_deconstructed(targeting[i].force) then return end
                        end
                        -- we are the only one targeting
                        if target.order_deconstruction(target.force) then
                            if global.debug then msg_all({"autodeconstruct-debug", target.name .. " at " .. util.positiontostr(target.position) .. " success"}) end
                        else
                            if global.debug then msg_all({"autodeconstruct-debug", target.name .. " at " .. util.positiontostr(target.position) .. " failed"}) end
                        end
                    end
                end
--[[ #TODO
                if target.type == "transport-belt" then
                    -- find entities with this belt as target
                end
--]]
            end
        end
    end
end
