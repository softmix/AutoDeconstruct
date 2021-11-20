require "util"
autodeconstruct = {}

local function map_to_string(t)
  local s = "{"
  for k,_ in pairs(t) do
    s = s..tostring(k)..","
  end
  s = s.."}"
  return s
end
  

local function has_resources(drill)
  local resource_categories = drill.prototype.resource_categories
  local position = drill.position
  local range = drill.prototype.mining_drill_radius
  if resource_categories then
    local top_left = {x = position.x - range, y = position.y - range}
    local bottom_right = {x = position.x + range, y = position.y + range}

    local resources = drill.surface.find_entities_filtered{area={top_left, bottom_right}, type='resource'}
    if global.debug then msg_all("found "..#resources.." resources near "..util.positiontostr(drill.position)..", checking for types "..map_to_string(resource_categories)) end

    for _, resource in pairs(resources) do
      if resource_categories[resource.prototype.resource_category] and
          resource.amount > 0 then
        if global.debug then msg_all("drill still mining "..resource.name.." at "..util.positiontostr(resource.position)) end
        return true
      else
        if global.debug then msg_all("drill can't mine "..resource.name.." at "..util.positiontostr(resource.position)) end
      end
    end
  end
  return false
end

local function find_all_entities(entity_type)
  local entities = {}
  for _, surface in pairs(game.surfaces) do
    if surface and surface.valid then
      for chunk in surface.get_chunks() do
        local chunk_area = {lefttop = {x = chunk.x*32, y = chunk.y*32}, rightbottom = {x = chunk.x*32+32, y = chunk.y*32+32}}
        local chunk_entities = surface.find_entities_filtered({area = chunk_area, type = entity_type})
        for i = 1, #chunk_entities do
          entities[#entities + 1] = chunk_entities[i]
        end
      end
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
  local range = global.max_radius
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

  local entities = surface.find_entities_filtered{area={top_left, bottom_right}, type='inserter'}
  for i = 1, #entities do
    if find_target(entities[i]) == entity then
      targeting[#targeting + 1] = entities[i]
    end
  end

  if global.debug then msg_all({"autodeconstruct-debug", "found " .. #targeting .. " targeting"}) end

  return targeting
end

local function find_drills(entity)
  local position = entity.position
  local surface = entity.surface

  local top_left = {x = position.x - global.max_radius, y = position.y - global.max_radius}
  local bottom_right = {x = position.x + global.max_radius, y = position.y + global.max_radius}

  local entities = {}
  
  local entities = surface.find_entities_filtered{area={top_left, bottom_right}, type='mining-drill'}
  if global.debug then msg_all({"autodeconstruct-debug", "found " .. #entities  .. " drills"}) end

  for _, e in pairs(entities) do
    if (math.abs(e.position.x - position.x) < e.prototype.mining_drill_radius and 
        math.abs(e.position.y - position.y) < e.prototype.mining_drill_radius) then
      autodeconstruct.check_drill(e)
    end
  end
end

local function debug_message_with_position(entity, msg)
  if not global.debug then return end

  msg_all({"autodeconstruct-debug", util.positiontostr(entity.position) .. " " .. entity.name  .. " " .. msg})
end

function autodeconstruct.init_globals()
  global.max_radius = 0.99
  local drill_entities = find_all_entities('mining-drill')

  for _, drill_entity in pairs(drill_entities) do
    autodeconstruct.check_drill(drill_entity)
  end
end

function autodeconstruct.on_resource_depleted(event)
  if event.entity.prototype.infinite_resource then
    if global.debug then msg_all({"autodeconstruct-debug", "on_resource_depleted", game.tick .. " amount " .. event.entity.amount .. " resource_category " .. event.entity.prototype.resource_category .. " infinite_resource " .. (event.entity.prototype.infinite_resource == true and "true" or "false" )}) end
    return
  end

  find_drills(event.entity)
end

function autodeconstruct.check_drill(drill)
  if drill.mining_target ~= nil and drill.mining_target.valid then
    if drill.mining_target.amount > 0 then return end -- this should also filter out pumpjacks and infinite resources
  end

  local mining_drill_radius = drill.prototype.mining_drill_radius
  if mining_drill_radius == nil then return end
  if mining_drill_radius > global.max_radius then
    global.max_radius = mining_drill_radius
  end

  if not has_resources(drill) then
    if global.debug then msg_all({"autodeconstruct-debug", util.positiontostr(drill.position) .. " found no compatible resources, deconstructing"}) end
    autodeconstruct.order_deconstruction(drill)
  end
end

function autodeconstruct.on_cancelled_deconstruction(event)
  if event.player_index ~= nil or event.entity.type ~= 'mining-drill' then return end

  if global.debug then msg_all({"autodeconstruct-debug", "on_cancelled_deconstruction", util.positiontostr(event.entity.position) .. " deconstruction timed out, checking again"}) end

  autodeconstruct.check_drill(event.entity)
end

function autodeconstruct.on_built_entity(event)
  if event.created_entity.type ~= 'mining-drill' then return end
  if event.created_entity.prototype.mining_drill_radius > global.max_radius then
    global.max_radius = event.created_entity.prototype.mining_drill_radius
    if global.debug then msg_all({"autodeconstruct-debug", "on_built_entity", "global.max_radius updated to " .. global.max_radius}) end
  end
end

function autodeconstruct.deconstruct_target(drill)
  local target = find_target(drill)

  if target ~= nil and target.minable and target.prototype.selectable_in_game then
    if target.type == "logistic-container" or target.type == "container" then
      local targeting = find_targeting(target)

      if targeting ~= nil then
        for i = 1, #targeting do
          if not targeting[i].to_be_deconstructed(targeting[i].force) and targeting[i] ~= drill then break end
        end

        -- we are the only one targeting
        if target.to_be_deconstructed(target.force) then
          target.cancel_deconstruction(target.force)
        end

        if target.order_deconstruction(target.force, target.last_user) then
          debug_message_with_position(target, "marked for deconstruction")
        else
          msg_all({"autodeconstruct-err-specific", "target.order_deconstruction", util.positiontostr(target.position) .. " failed to order deconstruction on " .. target.name})
        end
      end
    end
  end
end

local function range(from,to,step)
  step = (from <= to) and step or -step
  local t = {}
  for i = from, to - step, step do 
      t[#t + 1] = i
  end
  t = (#t>0) and t or {from}
  --log("from:"..tostring(from)..",to:"..tostring(to)..", result:"..serpent.block(t, {comment = false, numformat = '%1.8g', compact = true } ))
  return t
end

local function rotate(v,dir)
  if dir == defines.direction.east then
    return {x = -v.y, y = v.x}
  elseif dir == defines.direction.south then
    return {x = -v.x, y = -v.y}
  elseif dir == defines.direction.west then
    return {x = v.y, y = -v.x}
  end
  return v
end

function autodeconstruct.build_pipe(drillData, pipeType, pipeTarget)
  --log("pipeTarget"..serpent.block(pipeTarget, {comment = false, numformat = '%1.8g', compact = true } ).."; drillData.position" .. serpent.block(drillData.position, {comment = false, numformat = '%1.8g', compact = true } ))
  pipeTarget = rotate(pipeTarget,drillData.direction)
  for _,x in pairs(range(drillData.position.x, drillData.position.x + pipeTarget.x, 1)) do
    for _, y in pairs(range(drillData.position.y, drillData.position.y + pipeTarget.y, 1)) do
      drillData.surface.create_entity{name="entity-ghost", player = drillData.owner, position = {x = x, y = y}, force=drillData.force, inner_name=pipeType}
    end
  end
end

function autodeconstruct.build_pipes(drill)
  -- future improvement: a mod setting for the pipeType to allow modded pipes
  -- future improvement: it would be nice if it could detect which directions were connected and only connect those
  local drillData = {
    position  = {
      x = drill.position.x,
      y = drill.position.y
    },
    direction = drill.direction,
    force     = drill.force,
    owner     = drill.last_user,
    surface   = drill.surface
  }
  --Space Exploration Compatibility check for space-surfaces
  local pipeType = "pipe"
  if game.active_mods["space-exploration"] then
    local se_zone = remote.call("space-exploration", "get_zone_from_surface_index", {surface_index = drillData.surface.index})
    local is_space = remote.call("space-exploration", "get_zone_is_space", {zone_index = se_zone.index})
    if is_space then
      pipeType = "se-space-pipe"
    end
  end
  -- fluidbox_prototype.pipe_connections contains a array with various connection points, it seems the one we need is always the 1st
  local fluidbox_prototype = drill.fluidbox.get_prototype(1)
  if fluidbox_prototype.pipe_connections and #fluidbox_prototype.pipe_connections > 0 then
    for k, conn in pairs(fluidbox_prototype.pipe_connections) do
      if conn.positions and #conn.positions > 0 then
        autodeconstruct.build_pipe(drillData, pipeType, conn.positions[1])
      end
    end
  end
end

function autodeconstruct.order_deconstruction(drill)
  if drill.to_be_deconstructed(drill.force) then
    debug_message_with_position(drill, "already marked, skipping")

    return
  end
  local has_fluid = false
  if drill.fluidbox and #drill.fluidbox > 0 then
    has_fluid = true
    if settings.global['autodeconstruct-remove-fluid-drills'].value ~= true then
      debug_message_with_position(drill, "has a non-empty fluidbox and fluid deconstruction is not enabled, skipping")

      return
    end
  end

  if next(drill.circuit_connected_entities.red) ~= nil or next(drill.circuit_connected_entities.green) ~= nil then
    debug_message_with_position(drill, "is hooked up to the circuit network, skipping")

    return
  end

  if not drill.minable then
    debug_message_with_position(drill, "is not minable, skipping")

    return
  end

  if not drill.prototype.selectable_in_game then
    debug_message_with_position(drill, "is not selectable in game, skipping")

    return
  end

  if drill.has_flag("not-deconstructable") then
    debug_message_with_position(drill, "is flagged as not-deconstructable, skipping")

    return
  end

  -- end guards

  if settings.global['autodeconstruct-remove-target'].value then
    autodeconstruct.deconstruct_target(drill)
  end

  if drill.order_deconstruction(drill.force, drill.last_user) then
    debug_message_with_position(drill, "marked for deconstruction")
    if has_fluid and settings.global['autodeconstruct-build-pipes'].value then
      debug_message_with_position(drill, "adding pipe blueprints")
      autodeconstruct.build_pipes(drill)
    end
  else
    msg_all({"autodeconstruct-err-specific", "drill.order_deconstruction", util.positiontostr(drill.position) .. " " .. drill.name .. " failed to order deconstruction" })
  end

end
