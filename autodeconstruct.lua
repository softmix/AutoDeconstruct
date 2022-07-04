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
      if resource_categories[resource.prototype.resource_category] then
        if resource.amount > 0 then
          if global.debug then msg_all("drill still mining "..resource.name.." at "..util.positiontostr(resource.position)) end
          return true
        else
          if global.debug then msg_all("drill finished mining "..resource.name.." at "..util.positiontostr(resource.position)) end
        end
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
    if global.debug then msg_all({"autodeconstruct-debug", "found " .. entity.drop_target.name .. " at " .. util.positiontostr(entity.drop_target.position)}) end
    return entity.drop_target
  else
    local entities = entity.surface.find_entities_filtered{position=entity.drop_position}
    if #entities > 0 then
      if global.debug then msg_all({"autodeconstruct-debug", "found " .. entities[1].name .. " at " .. util.positiontostr(entities[1].position)}) end
      return entities[1]
    end
  end
end

local function find_targeting(entity, types)
  local range = global.max_radius
  local position = entity.position

  local top_left = {x = position.x - range, y = position.y - range}
  local bottom_right = {x = position.x + range, y = position.y + range}

  local surface = entity.surface
  local targeting = {}

  local entities = surface.find_entities_filtered{area={top_left, bottom_right}, type=types}
  for i = 1, #entities do
    if find_target(entities[i]) == entity then
      targeting[#targeting + 1] = entities[i]
    end
  end

  if global.debug then msg_all({"autodeconstruct-debug", "found " .. #targeting .. " targeting"}) end

  return targeting
end

local function find_extracting(entity)
  local range = global.max_radius
  local position = entity.position

  local top_left = {x = position.x - range, y = position.y - range}
  local bottom_right = {x = position.x + range, y = position.y + range}

  local surface = entity.surface
  local extracting = {}

  local entities = surface.find_entities_filtered{area={top_left, bottom_right}, type="inserter"}
  for i = 1, #entities do
    if entities[i].pickup_target == entity then
      extracting[#extracting + 1] = entities[i]
    end
  end

  if global.debug then msg_all({"autodeconstruct-debug", "found " .. #extracting .. " extracting"}) end

  return extracting
end

local function find_drills(entity)
  local position = entity.position
  local surface = entity.surface

  local top_left = {x = position.x - global.max_radius, y = position.y - global.max_radius}
  local bottom_right = {x = position.x + global.max_radius, y = position.y + global.max_radius}

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

function autodeconstruct.is_valid_pipe(name)
  return game.entity_prototypes[name] and game.entity_prototypes[name].type == "pipe"
end

function autodeconstruct.init_globals()
  -- Find largest-range miner in the game
  global.max_radius = 0.99
  local drill_prototypes = game.get_filtered_entity_prototypes{{filter="type",type="mining-drill"}}
  for _, p in pairs(drill_prototypes) do
    if p.mining_drill_radius then
      if p.mining_drill_radius > global.max_radius then
        global.max_radius = p.mining_drill_radius
        if global.debug then msg_all({"autodeconstruct-debug", "init_globals", "global.max_radius updated to " .. global.max_radius}) end
      end
    end
  end

  -- Look for existing depleted miners based on current settings
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
  if event.player_index ~= nil then return end

  if global.debug then msg_all({"autodeconstruct-debug", "on_cancelled_deconstruction", util.positiontostr(event.entity.position) .. " deconstruction timed out, checking again"}) end
  -- If another mod cancelled deconstruction of a miner, check this miner again
  autodeconstruct.check_drill(event.entity)
end

function autodeconstruct.deconstruct_target(drill)
  local target = find_target(drill)

  if target ~= nil and target.minable and target.prototype.selectable_in_game then
    if target.type == "logistic-container" or target.type == "container" then
      local targeting = find_targeting(target, {'mining-drill', 'inserter'})

      if targeting ~= nil then
        local chest_is_idle = true
        for i = 1, #targeting do
          if not targeting[i].to_be_deconstructed(targeting[i].force) and targeting[i] ~= drill then
            chest_is_idle = false
            break
          end
        end

        if chest_is_idle then
          -- we are the only one targeting
          if target.to_be_deconstructed(target.force) then
            target.cancel_deconstruction(target.force)
          end
          local ent_dat = {name=target.name, position=target.position}
          if target.order_deconstruction(target.force) then
            if target and target.valid then
              debug_message_with_position(target, "marked for deconstruction")
            else
              debug_message_with_position(ent_dat, "instantly deconstructed")
            end
          else
            msg_all({"autodeconstruct-err-specific", "target.order_deconstruction", util.positiontostr(ent_dat.position) .. " failed to order deconstruction on " .. ent_dat.name})
          end
        end
      end
    end
  end
end

-- Build pipes from the given relative target to the center of the miner
function autodeconstruct.build_pipe(drillData, pipeType, pipeTarget)
  --log("pipeTarget: "..util.positiontostr(pipeTarget).."; drillData.position: "..util.positiontostr(drillData.position))

  -- build in X first, then in Y
  local x = pipeTarget.x
  local y = pipeTarget.y

  -- Build connection point first
  --log("> Building connector pipe at "..util.positiontostr({x=x,y=y}))
  drillData.surface.create_entity{
          name="entity-ghost",
          position = {x = drillData.position.x + x, y = drillData.position.y + y},
          force=drillData.force,
          inner_name=pipeType
        }

  -- Build X pipes left/right toward center (stop short if center is off-grid)
  while math.abs(x) >= 0.75 do
    if x > 0 then
      x = x - 1
    elseif x < 0 then
      x = x + 1
    end
    --log("building X pipe at relative position "..util.positiontostr({x=x,y=y}))
    drillData.surface.create_entity{
          name="entity-ghost",
          position = {x = drillData.position.x + x, y = drillData.position.y + y},
          force=drillData.force,
          inner_name=pipeType
        }
  end
  -- Build Y pipes up/down from where X left off (stop short if center is off-grid)
  while math.abs(y) >= 0.75 do
    if y > 0 then
      y = y - 1
    elseif y < 0 then
      y = y + 1
    end
    --log("building Y pipe at relative position "..util.positiontostr({x=x,y=y}))
    drillData.surface.create_entity{
          name="entity-ghost",
          position = {x = drillData.position.x + x, y = drillData.position.y + y},
          force=drillData.force,
          inner_name=pipeType
        }
  end
end

-- Check the center four tiles of even-sided miners to see if caddy-corner pipes need to be joined
function autodeconstruct.join_pipes(drillData, pipeType)
  pipeGhosts = drillData.surface.find_entities_filtered{position = drillData.position, radius = 1.1, ghost_type = "pipe"}
  --log("> Found "..tostring(#pipeGhosts).." near center of even-sided drill at "..util.positiontostr(drillData.position))
  if #pipeGhosts == 2 then
    if pipeGhosts[1].position.x ~= pipeGhosts[2].position.x and pipeGhosts[1].position.y ~= pipeGhosts[2].position.y then
      -- Build a third pipe to connect these two on a diagonal
      --log("Building Diagonal Connecting pipe at relative position " .. util.positiontostr({x=pipeGhosts[1].position.x - drillData.position.x,y=pipeGhosts[2].position.y - drillData.position.y}) )
      drillData.surface.create_entity{
            name="entity-ghost",
            position = {x = pipeGhosts[1].position.x, y = pipeGhosts[2].position.y},
            force=drillData.force,
            inner_name=pipeType
          }
    end
  end

end

-- Round selection box to nearest integer coordinates
local function snap_box_to_grid(box)
  box.left_top.x = math.floor(box.left_top.x*2+0.5)/2
  box.left_top.y = math.floor(box.left_top.y*2+0.5)/2
  box.right_bottom.x = math.floor(box.right_bottom.x*2+0.5)/2
  box.right_bottom.y = math.floor(box.right_bottom.y*2+0.5)/2
  return box
end

function autodeconstruct.build_pipes(drill, pipeType)
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

  --log("Building pipes for drill: "..drill.name.." at "..util.positiontostr(drill.position))

  -- Drills only have one fluidbox, get the first
  local connected_fluidboxes = drill.fluidbox.get_connections(1)

  if connected_fluidboxes then
    -- Find the points at the edge of the drill where the pipes actually meet
    -- Connection position index is different from entity.direction
    -- {0,2,4,6} ==> {1,2,3,4}
    local conn_index = math.floor(drillData.direction/2)+1

    -- Box with coordinates of entity grid boundary
    local box = snap_box_to_grid(drill.selection_box)

    -- Box with coordinates of pipes placed inside the entity boundary
    local pipe_box = {left_top =     {x = box.left_top.x - drillData.position.x + 0.5,     y = box.left_top.y - drillData.position.y + 0.5},
                      right_bottom = {x = box.right_bottom.x - drillData.position.x - 0.5, y = box.right_bottom.y - drillData.position.y - 0.5}}

    --log("Selection box: "..serpent.line(box).."\nPipe box: "..serpent.line(pipe_box))
    local junctions = {}
    local pipe_offsets = {}
    for k, connection in pairs(drill.fluidbox.get_prototype(1).pipe_connections) do
      local conn = connection.positions[conn_index]  -- offset from center of where mating pipe goes
      junctions[k] = {x = util.clamp(conn.x + drillData.position.x, box.left_top.x, box.right_bottom.x),  -- world coordinate of where mating pipe meets entity
                      y = util.clamp(conn.y + drillData.position.y, box.left_top.y, box.right_bottom.y)}
      pipe_offsets[k] = {x = util.clamp(conn.x, pipe_box.left_top.x, pipe_box.right_bottom.x),      -- offset from center to where internal pipe goes
                         y = util.clamp(conn.y, pipe_box.left_top.y, pipe_box.right_bottom.y)}
    end

    -- See how many neighboring fluidboxes we can find
    local pipes_built = 0
    for _,other_fluidbox in pairs(connected_fluidboxes) do
      local other_box = snap_box_to_grid(other_fluidbox.owner.selection_box)

      -- Look for any of our junctions that lines up on the target's boundary box
      local this_pipe_built = false
      for k, junc in pairs(junctions) do
        if (junc.y == other_box.right_bottom.y and junc.x >= other_box.left_top.x and junc.x <= other_box.right_bottom.x) or -- match on north side
           (junc.y == other_box.left_top.y and junc.x >= other_box.left_top.x and junc.x <= other_box.right_bottom.x) or     -- match on south side
           (junc.x == other_box.right_bottom.x and junc.y >= other_box.left_top.y and junc.y <= other_box.right_bottom.y) or -- match on east side
           (junc.x == other_box.left_top.x and junc.y >= other_box.left_top.y and junc.y <= other_box.right_bottom.y) then   -- match on west side

          --log("found junction "..util.positiontostr(junc).." is adjacent to "..other_fluidbox.owner.name.." box "..string.gsub(serpent.block(other_box),"[\n ]",""))
          autodeconstruct.build_pipe(drillData, pipeType, pipe_offsets[k])
          pipes_built = pipes_built + 1
          this_pipe_built = true
        end
      end
      if not this_pipe_built then
        debug_message_with_position(drill, "can't find fluid connectors pointing toward neighbor at "..util.positiontostr(other_fluidbox.owner.position))
      end
    end

    -- Check if we need to fill in a corner of an even-sided miner
    if pipes_built > 1 then
      -- Pipe construction box is odd-sided if the miner is even-sided
      if ((pipe_box.left_top.x - pipe_box.right_bottom.x) % 2 == 1) and
         ((pipe_box.left_top.y - pipe_box.right_bottom.y) % 2 == 1) then
        autodeconstruct.join_pipes(drillData, pipeType)
      end
    end

    if pipes_built > 0 then
      debug_message_with_position(drill, "connected pipes to "..tostring(pipes_built).." neighbors")
    else
      debug_message_with_position(drill, "can't find fluid connectors pointing toward any neighbors")
    end
  end
end

function autodeconstruct.order_deconstruction(drill)
  if drill.to_be_deconstructed(drill.force) then
    debug_message_with_position(drill, "already marked, skipping")

    return
  end
  local has_fluid = false
  local pipeType = nil
  if drill.fluidbox and #drill.fluidbox > 0 then
    has_fluid = true
    if not settings.global['autodeconstruct-remove-fluid-drills'].value then
      debug_message_with_position(drill, "has a non-empty fluidbox and fluid deconstruction is not enabled, skipping")

      return
    end
    --Space Exploration Compatibility check for space-surfaces
    -- Select the pipe to use for replacements
    pipeType = settings.global['autodeconstruct-pipe-name'].value
    local is_space = false
    if game.active_mods["space-exploration"] then
      local se_zone = remote.call("space-exploration", "get_zone_from_surface_index", {surface_index = drill.surface.index})
      is_space = remote.call("space-exploration", "get_zone_is_space", {zone_index = se_zone.index})
      if is_space then
        pipeType = settings.global['autodeconstruct-space-pipe-name'].value
      end
    end

    if not autodeconstruct.is_valid_pipe(pipeType) then
      if is_space then
        debug_message_with_position(drill, "can't find space pipe named '"..pipeType.."' to infill depleted fluid miner in space.")
      else
        debug_message_with_position(drill, "can't find pipe named '"..pipeType.."' to infill depleted fluid miner.")
      end

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

  if drill.burner and #find_extracting(drill)>0 then
    debug_message_with_position(drill, "is part of inserter chain, skipping")

    return
  end

  -- end guards

  if settings.global['autodeconstruct-remove-target'].value then
    autodeconstruct.deconstruct_target(drill)
  end

  local ent_dat = {name=drill.name, position=drill.position}
  if drill.order_deconstruction(drill.force) then
    if drill and drill.valid then
      debug_message_with_position(drill, "marked for deconstruction")
      -- Handle pipes
      if has_fluid and settings.global['autodeconstruct-build-pipes'].value then
        if #drill.fluidbox.get_connections(1) > 1 then
          debug_message_with_position(drill, "adding pipe blueprints")
          autodeconstruct.build_pipes(drill, pipeType)
        else
          debug_message_with_position(drill, "skipping pipe blueprints, only one connection")
        end
      end
      -- Check for inserters providing fuel to this miner
      if drill.valid and drill.burner then
        local targeting = find_targeting(drill, {'inserter'})
        for _,e in pairs(targeting) do
          e.order_deconstruction(e.force)
        end
      end
    else
      msg_all({"autodeconstruct-err-specific", "drill.order_deconstruction", util.positiontostr(ent_dat.position) .. " " .. ent_dat.name .. " instantly deconstructed, nothing else done" })
    end
  else
    msg_all({"autodeconstruct-err-specific", "drill.order_deconstruction", util.positiontostr(drill.position) .. " " .. drill.name .. " failed to order deconstruction" })
  end
end
