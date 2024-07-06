require "util"
autodeconstruct = {}

blacklist_surface_prefixes = {"BPL_TheLab", "bpsb%-lab"}
belt_type_check = {["transport-belt"]=true, ["underground-belt"]=true, ["splitter"]=true}
belt_types = {"transport-belt","underground-belt","splitter"}

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
      for _,entity in pairs(surface.find_entities_filtered{type = entity_type}) do
        table.insert(entities, entity)
      end
    end
  end
  return entities
end

-- Find the target entity the miner is dropping in, if any
local function find_target(entity)
  if entity.drop_target then  -- works when target is a chest
    if global.debug then msg_all({"autodeconstruct-debug", "found " .. entity.drop_target.name .. " at " .. util.positiontostr(entity.drop_target.position)}) end
    return entity.drop_target
  else
    local entities = entity.surface.find_entities_filtered{position=entity.drop_position, limit=1}  -- works when target is a belt
    if #entities > 0 then
      if global.debug then msg_all({"autodeconstruct-debug", "found " .. entities[1].name .. " at " .. util.positiontostr(entities[1].position)}) end
      --game.print("found target using position: "..entities[1].name)
      return entities[1]
    end
  end
end


local function find_target_line(drill, target)
  if not target or not belt_type_check[target.type] then
    return
  end
  
  -- Figure out all the cases for where the miner can drop the item on the belt.
  -- If drop_pos is at exactly 0.5, it defaults to the right line
  local belt_pos = target.position
  local drop_pos = drill.drop_position
  local belt_dir = target.direction
  
  local target_line_index = 0
  
  if target.type == "transport-belt" and target.belt_shape == "left" then
    -- Left turn belt, can only ever deposit on the right line (assuming miner drops close to itself)
    target_line_index = defines.transport_line.right_line
      
  elseif target.type == "transport-belt" and target.belt_shape == "right" then
    -- Right turn belt, can only ever deposit on the left line (assuming miner drops close to itself)
    target_line_index = defines.transport_line.left_line
    
  elseif target.type == "transport-belt" or target.type == "underground-belt" then
    -- Straight belt or underground
    if belt_dir == defines.direction.north then
      if drop_pos.x < belt_pos.x then
        target_line_index = defines.transport_line.left_line
      else
        target_line_index = defines.transport_line.right_line
      end
    elseif belt_dir == defines.direction.south then
      if drop_pos.x > belt_pos.x then
        target_line_index = defines.transport_line.left_line
      else
        target_line_index = defines.transport_line.right_line
      end
    elseif belt_dir == defines.direction.east then
      if drop_pos.y  < belt_pos.y then
        target_line_index = defines.transport_line.left_line
      else
        target_line_index = defines.transport_line.right_line
      end
    elseif belt_dir == defines.direction.west then
      if drop_pos.y > belt_pos.y then
        target_line_index = defines.transport_line.left_line
      else
        target_line_index = defines.transport_line.right_line
      end
    end
  elseif target.type == "splitter" then
    -- Splitter has 8 different lines
    -- "right_line" and "left_line" refer to the leftmost input belt
    -- "secondary_*" refer to the rightmost input belt
    -- "*_split_*" refer to the output belts
    -- When dropping from the side or the front, items only go to the output belts
    -- When dropping from the back, items go to the input belts
    
    -- When drop-pos is at 0.5 lengthwise, defaults to input belts
    -- Divide area into 8 zones for each of the 4 cardinal directions
    
    
    if belt_dir == defines.direction.north then
      -- when facing north, outputs are negative y and left lane is negative x
      -- Check if input or output
      if drop_pos.y < belt_pos.y then
        -- Use output belts
        if drop_pos.x < belt_pos.x-0.5 then
          target_line_index = defines.transport_line.left_split_line
        elseif drop_pos.x < belt_pos.x then
          target_line_index = defines.transport_line.right_split_line
        elseif drop_pos.x < belt_pos.x+0.5 then
          target_line_index = defines.transport_line.secondary_left_split_line
        else
          target_line_index = defines.transport_line.secondary_right_split_line
        end
      else
        -- Use input belts
        if drop_pos.x < belt_pos.x-0.5 then
          target_line_index = defines.transport_line.left_line
        elseif drop_pos.x < belt_pos.x then
          target_line_index = defines.transport_line.right_line
        elseif drop_pos.x < belt_pos.x+0.5 then
          target_line_index = defines.transport_line.secondary_left_line
        else
          target_line_index = defines.transport_line.secondary_right_line
        end
      end
    
    elseif belt_dir == defines.direction.south then
      -- when facing south, outputs are positive y and left lane is positive x
      -- Check if input or output
      if drop_pos.y > belt_pos.y then
        -- Use output belts
        if drop_pos.x > belt_pos.x+0.5 then
          target_line_index = defines.transport_line.left_split_line
        elseif drop_pos.x > belt_pos.x then
          target_line_index = defines.transport_line.right_split_line
        elseif drop_pos.x > belt_pos.x-0.5 then
          target_line_index = defines.transport_line.secondary_left_split_line
        else
          target_line_index = defines.transport_line.secondary_right_split_line
        end
      else
        -- Use input belts
        if drop_pos.x > belt_pos.x+0.5 then
          target_line_index = defines.transport_line.left_line
        elseif drop_pos.x > belt_pos.x then
          target_line_index = defines.transport_line.right_line
        elseif drop_pos.x > belt_pos.x-0.5 then
          target_line_index = defines.transport_line.secondary_left_line
        else
          target_line_index = defines.transport_line.secondary_right_line
        end
      end
    
    elseif belt_dir == defines.direction.east then
      -- when facing east, outputs are positive x and left lane is negative y
      -- Check if input or output
      if drop_pos.x > belt_pos.x then
        -- Use output belts
        if drop_pos.y < belt_pos.y-0.5 then
          target_line_index = defines.transport_line.left_split_line
        elseif drop_pos.y < belt_pos.y then
          target_line_index = defines.transport_line.right_split_line
        elseif drop_pos.y < belt_pos.y+0.5 then
          target_line_index = defines.transport_line.secondary_left_split_line
        else
          target_line_index = defines.transport_line.secondary_right_split_line
        end
      else
        -- Use input belts
        if drop_pos.y < belt_pos.y-0.5 then
          target_line_index = defines.transport_line.left_line
        elseif drop_pos.y < belt_pos.y then
          target_line_index = defines.transport_line.right_line
        elseif drop_pos.y < belt_pos.y+0.5 then
          target_line_index = defines.transport_line.secondary_left_line
        else
          target_line_index = defines.transport_line.secondary_right_line
        end
      end
    
    elseif belt_dir == defines.direction.west then
      -- when facing west, outputs are negative x and left lane is positive y
      -- Check if input or output
      if drop_pos.x < belt_pos.x then
        -- Use output belts
        if drop_pos.y > belt_pos.y+0.5 then
          target_line_index = defines.transport_line.left_split_line
        elseif drop_pos.y > belt_pos.y then
          target_line_index = defines.transport_line.right_split_line
        elseif drop_pos.y > belt_pos.y-0.5 then
          target_line_index = defines.transport_line.secondary_left_split_line
        else
          target_line_index = defines.transport_line.secondary_right_split_line
        end
      else
        -- Use input belts
        if drop_pos.y > belt_pos.y+0.5 then
          target_line_index = defines.transport_line.left_line
        elseif drop_pos.y > belt_pos.y then
          target_line_index = defines.transport_line.right_line
        elseif drop_pos.y > belt_pos.y-0.5 then
          target_line_index = defines.transport_line.secondary_left_line
        else
          target_line_index = defines.transport_line.secondary_right_line
        end
      end
    
    end
  
  end
  -- Return the selected transport line reference
  if target_line_index > 0 then
    return target.get_transport_line(target_line_index)
  end

end

local function find_targeting(entity, types)
  local range = global.max_radius
  local position = entity.position

  local top_left = {x = position.x - range, y = position.y - range}
  local bottom_right = {x = position.x + range, y = position.y + range}

  local surface = entity.surface
  local targeting = {}

  for _, e in pairs(surface.find_entities_filtered{area={top_left, bottom_right}, type=types}) do
    if find_target(e) == entity then
      table.insert(targeting, e)
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

  for _, e in pairs(surface.find_entities_filtered{area={top_left, bottom_right}, type="inserter"}) do
    if e.pickup_target == entity then
      table.insert(extracting, e)
    end
  end

  if global.debug then msg_all({"autodeconstruct-debug", "found " .. #extracting .. " extracting"}) end

  return extracting
end

local function debug_message_with_position(entity, msg)
  if not global.debug then return end

  msg_all({"autodeconstruct-debug", util.positiontostr(entity.position) .. " " .. entity.name  .. " " .. msg})
end

function autodeconstruct.is_valid_pipe(name)
  return game.entity_prototypes[name] and game.entity_prototypes[name].type == "pipe"
end

local function queue_deconstruction(drill)
  global.drill_queue = global.drill_queue or {}
  local decon_tick = game.tick + 30  -- by default, wait just long enough to eject the last item
  local timeout_tick = decon_tick + 1800  -- wait at most 30 seconds for items to clear out
  local target = find_target(drill)
  local target_line = find_target_line(drill, target)
  if target_line then
    target = nil  -- Don't look for chest stuff if we have a transport line
  end
  local lp = nil
  if target and target.type == "logistic-container" then
    lp = target.get_logistic_point()[1]
  end
  if target and not lp and #find_extracting(target) == 0 then
    target = nil  -- No inserters removing from this chest and no logistics, so no point in waiting to deconstruct
  end
  table.insert(global.drill_queue, {tick=decon_tick, timeout=timeout_tick, drill=drill, target=target, target_lp=lp, target_line=target_line})
end

local function check_drill(drill)
  if global.blacklist[drill.name] then return end

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
    queue_deconstruction(drill)
  end
end

function autodeconstruct.init_globals()

  -- Update the blacklist with the current setting value (whitespace, comma, and semicolon are valid separators)
  global.blacklist = {}
  for token in string.gmatch(settings.global["autodeconstruct-blacklist"].value,"([^%s,;]+)") do
    if game.entity_prototypes[token] then
      global.blacklist[token] = true
    end
  end
  
  -- Find largest-range miner in the game (only check drills not on the blacklist)
  global.max_radius = 0.99
  local drill_prototypes = game.get_filtered_entity_prototypes{{filter="type",type="mining-drill"}}
  for _, p in pairs(drill_prototypes) do
    if not global.blacklist[p.name] then
      if p.mining_drill_radius then
        if p.mining_drill_radius > global.max_radius then
          global.max_radius = p.mining_drill_radius
          if global.debug then msg_all({"autodeconstruct-debug", "init_globals", "global.max_radius updated to " .. global.max_radius}) end
        end
      end
    end
  end
  
  -- Clear existing deconstruction queue_deconstruction
  global.drill_queue = {}

  -- Look for existing depleted miners based on current settings, and re-add them to the queue
  local drill_entities = find_all_entities('mining-drill')
  for _, drill_entity in pairs(drill_entities) do
    check_drill(drill_entity)
  end
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
      check_drill(e)
    end
  end
end

function autodeconstruct.on_resource_depleted(event)
  if event.entity.prototype.infinite_resource then
    if global.debug then msg_all({"autodeconstruct-debug", "on_resource_depleted", game.tick .. " amount " .. event.entity.amount .. " resource_category " .. event.entity.prototype.resource_category .. " infinite_resource " .. (event.entity.prototype.infinite_resource == true and "true" or "false" )}) end
    return
  end

  find_drills(event.entity)
end

function autodeconstruct.on_cancelled_deconstruction(event)
  if event.player_index ~= nil then return end

  if global.debug then msg_all({"autodeconstruct-debug", "on_cancelled_deconstruction", util.positiontostr(event.entity.position) .. " deconstruction timed out, checking again"}) end
  -- If another mod cancelled deconstruction of a miner, check this miner again
  check_drill(event.entity)
end


local function deconstruct_beacons(drill)
  local beacons = drill.get_beacons()
  if beacons == nil then return end   -- Drills that don't accept beacons return nil intead of empty list
  local beacon_busy = false
  for _,beacon in pairs(drill.get_beacons()) do
    if not beacon.to_be_deconstructed() and not global.blacklist[beacon.name] then
      -- Receiving entities still show up if they are marked for deconstruction, so we have to check them all
      for _,receiver in pairs(beacon.get_beacon_effect_receivers()) do
        if receiver ~= drill then
          if not receiver.to_be_deconstructed() then
            beacon_busy = true
            break
          end
        end
      end
      if not beacon_busy then
        local ent_dat = {name=beacon.name, position=beacon.position}
        if beacon.order_deconstruction(beacon.force) then
          if beacon and beacon.valid then
            debug_message_with_position(beacon, "marked for deconstruction")
          else
            debug_message_with_position(ent_dat, "instantly deconstructed")
          end
        end
      end
    end
  end
end


-- Returns true if the belt is safe to deconstruct and the only targeter (if any) is the to-be-deconstructed drill
local function check_is_belt_deconstructable(target, drill)
  if target ~= nil and target.minable and target.prototype.selectable_in_game and not global.blacklist[target.name] and belt_type_check[target.type] then
    -- This belt is safe to deconstruct if necessary
    local targeting = find_targeting(target, {'mining-drill', 'inserter'})
    
    
    if #targeting == 0 then
      debug_message_with_position(target, "checked "..tostring(target.unit_number).." for targeting entities, found "..tostring(#targeting)..". Not targeted by anything.")
      return true
    else
    
      for _,targeter in pairs(targeting) do
        if targeter ~= drill and not targeter.to_be_deconstructed() then
          debug_message_with_position(target, "checked "..tostring(target.unit_number).." for targeting entities, found "..tostring(#targeting)..". At least one is new, so belt is targeted.")
          return false  -- targeted by a different drill or inserter that is not marked for deconstruction, so it is in use
        end
      end
      
      debug_message_with_position(target, "checked "..tostring(target.unit_number).." for targeting entities, but the only one is the OLD miner.")
      return true
    end
  else
    return false
  end
end

-- These functions return a list of belt neighbors that includes underground belt input/output, since they are in a different API structure.
local function get_belt_outputs(belt)
  local outputs = belt.belt_neighbours.outputs
  if belt.type == "underground-belt" and belt.belt_to_ground_type == "input" then
    table.insert(outputs,belt.neighbours)  -- insert the output undie for this input undie, since that is downstream
  end
  return outputs
end
local function get_belt_inputs(belt)
  local inputs = belt.belt_neighbours.inputs
  if belt.type == "underground-belt" and belt.belt_to_ground_type == "output" then
    table.insert(inputs,belt.neighbours)  -- insert the input undie for this output undie, since that is upstream
  end
  return inputs
end

local function deconstruct_belts(drill)
  
  -- 1. Check if the target of this drill is a belt
  local target = find_target(drill)
  if not (target.type == "transport-belt" or target.type == "underground-belt" or target.type == "splitter") then
    return
  end
  local starting_belt = target
  
  --    Start at the first belt and deconstruct and its upstream belts it if possible.
  --    Then check the belt downstream of that one in case it has another upstream path, and so on.
  --    Luckily, once a belt is marked for deconstruction, it no longer appears in belt_neighbours for anything
  
  -- 3. Go to each downstream belt and see if everything upstream of it can be removed
  local downstream_belts_to_check = {starting_belt}
  while table_size(downstream_belts_to_check) > 0 do
    local next_start_belt = table.remove(downstream_belts_to_check)
    if check_is_belt_deconstructable(next_start_belt, drill) then
      --game.print("checking upstream from belt "..tostring(next_start_belt.unit_number))
      local upstream_belts_to_check = next_start_belt.belt_neighbours.inputs  -- List of belts upstream of the first safe belt
      local upstream_belts_to_deconstruct = {}
      local upstream_belts_checked = {}
      upstream_belts_checked[next_start_belt.unit_number] = true
      
      -- 3a. Check if deconstructing this belt will interfere with sideloading downstream
      --  v
      -- >>>  bad to remove leftmost but okay to remove upper (input count = 2)
      --
      --  v
      -- >>>  okay to remove any one belt  (input count = 3)
      --  ^ 
      --
      -- >>>  okay to remove any one belt (input count = 1)
      --
      --  v
      --  >>  okay to remove any one belt (input count = 1)
      --
      --  v
      --  >>  bad to remove any belt (input count = 2)
      --  ^
      --
      -- Conclusion: If input_count == 2, to be safe don't remove the last belt. It may be removed safely once more miners in the patch are exhausted.
      local sideload_safe = true
      local next_start_outputs = get_belt_outputs(next_start_belt)
      for _,belt in pairs(next_start_outputs) do
        if belt.type == "transport-belt" and #belt.belt_neighbours.inputs == 2 then
          sideload_safe = false  -- one of the output belts from this is side-loaded and might reconnect incorrectly if this start_belt were removed
          break
        end
      end
      if sideload_safe then
        table.insert(upstream_belts_to_deconstruct, next_start_belt)
      end
      
      -- 3b. Follow the tree upstream, make a list of all the belts we travel and stop if we find another dropping entity
      local belt_in_use = false
      while table_size(upstream_belts_to_check) > 0 do
        local next_belt = table.remove(upstream_belts_to_check)
        
        if not check_is_belt_deconstructable(next_belt, drill) then
          -- Found a belt that has another target.  We can't remove any belts up this tree, including this next_start_belt.
          -- Also don't check any belts that are downstream of our current next_start_belt because something upstream is in use
          belt_in_use = true
          break
        end
        
        -- This belt does not have any other targets
        table.insert(upstream_belts_to_deconstruct, next_belt)
        upstream_belts_checked[next_belt.unit_number] = true
      
        -- Check if it has any upstream belts to keep traveling on
        for _,belt in pairs(get_belt_inputs(next_belt)) do
          -- This is a new one, add it to check in a future iteration
          if not upstream_belts_checked[belt.unit_number] then
            table.insert(upstream_belts_to_check, belt)
          end
        end
      end
      
      -- 3c. If no other users were found, deconstruct all the upstream belts, 
      --   including the one we started at if it's sideload-safe, since if we got here we did not find any other users attached
      if not belt_in_use then
        for _,belt in pairs(upstream_belts_to_deconstruct) do
          belt.order_deconstruction(belt.force)
        end
        upstream_belts_checked = {}
        upstream_belts_to_deconstruct = {}
      
      -- Keep looking downstream, even if this particular isn't sideload safe. If the next belt can be deconstructed then it doesn't matter.
        for _,belt in pairs(next_start_outputs) do
          table.insert(downstream_belts_to_check, belt)
        end
      end
    end
  end
end
  

local function deconstruct_target(drill)
  local target = find_target(drill)

  if target ~= nil and target.minable and target.prototype.selectable_in_game and not global.blacklist[target.name] then
    if target.type == "logistic-container" or target.type == "container" then
      local targeting = find_targeting(target, {'mining-drill', 'inserter'})

      if targeting ~= nil then
        local chest_is_idle = true
        for _, e in pairs(targeting) do
          if not e.to_be_deconstructed(e.force) and e ~= drill then
            chest_is_idle = false
            break
          end
        end

        if chest_is_idle then
          -- we are the only one targeting
          if target.to_be_deconstructed() then
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
local function build_pipe(drillData, pipeType, pipeTarget)
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
          inner_name=pipeType,
          raise_built=true
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
          inner_name=pipeType,
          raise_built=true
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
          inner_name=pipeType,
          raise_built=true
        }
  end
end

-- Check the center four tiles of even-sided miners to see if caddy-corner pipes need to be joined
local function join_pipes(drillData, pipeType)
  local pipeGhosts = drillData.surface.find_entities_filtered{position = drillData.position, radius = 1.1, ghost_type = "pipe"}
  --log("> Found "..tostring(#pipeGhosts).." near center of even-sided drill at "..util.positiontostr(drillData.position))
  if #pipeGhosts == 2 then
    if pipeGhosts[1].position.x ~= pipeGhosts[2].position.x and pipeGhosts[1].position.y ~= pipeGhosts[2].position.y then
      -- Build a third pipe to connect these two on a diagonal
      --log("Building Diagonal Connecting pipe at relative position " .. util.positiontostr({x=pipeGhosts[1].position.x - drillData.position.x,y=pipeGhosts[2].position.y - drillData.position.y}) )
      drillData.surface.create_entity{
            name="entity-ghost",
            position = {x = pipeGhosts[1].position.x, y = pipeGhosts[2].position.y},
            force=drillData.force,
            inner_name=pipeType,
            raise_built=true
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


local function find_ghost_pipe(drillData, connecting_pipe_position)
  local found_pipe = drillData.surface.find_entities_filtered{ghost_type = "pipe", position = connecting_pipe_position}
  if (found_pipe and next(found_pipe)) then
    return true
  end
  local found_underground = drillData.surface.find_entities_filtered{ghost_type = "pipe-to-ground", position = connecting_pipe_position, direction = connecting_pipe_position.direction}
  if (found_underground and next(found_underground)) then
    return true
  end
  return false
end

local function build_pipes(drill, pipeType)
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
  local connecting_pipe_positions = {}
  for k, connection in pairs(drill.fluidbox.get_prototype(1).pipe_connections) do
    local conn = connection.positions[conn_index]  -- offset from center of where mating pipe goes
    junctions[k] = {x = util.clamp(conn.x + drillData.position.x, box.left_top.x, box.right_bottom.x),  -- world coordinate of edge where mating pipe meets entity (integer coordinate at tile boundary, integer+0.5 coordinate at centerline of pipe)
                    y = util.clamp(conn.y + drillData.position.y, box.left_top.y, box.right_bottom.y)}
    pipe_offsets[k] = {x = util.clamp(conn.x, pipe_box.left_top.x, pipe_box.right_bottom.x),      -- offset from center to where internal pipe goes
                       y = util.clamp(conn.y, pipe_box.left_top.y, pipe_box.right_bottom.y)}
    
    -- prepare to look for ghost pipes (they don't have fluidboxes, have to search coordinates)
    local underground_direction  -- If direction is undetermined, then it will search for all directions
    if junctions[k].y == box.right_bottom.y then
      underground_direction = defines.direction.north  -- connection is on south border, mating pipe faces north
    elseif junctions[k].x == box.right_bottom.x then
      underground_direction = defines.direction.west  -- connection is on east border, mating pipe faces west
    elseif junctions[k].y == box.left_top.y then
      underground_direction = defines.direction.south  -- connection is on north border, mating pipe faces south
    elseif junctions[k].x == box.left_top.x then
      underground_direction = defines.direction.east  -- connection is on west border, mating pipe faces east
    end
    connecting_pipe_positions[k] = {x = conn.x + drillData.position.x,    -- world coordinate of where the mating pipe for this fluidbox connection goes
                                    y = conn.y + drillData.position.y,
                                    direction = underground_direction}
  end
  
  
  -- Make a dict of which junctions are still empty to check for ghost pipes
  local connections_remaining = {}
  for k,v in pairs(junctions) do
    connections_remaining[k] = true
  end
  
  local pipes_to_build = {}
  
  -- Drills only have one fluidbox, get the first
  local connected_fluidboxes = drill.fluidbox.get_connections(1)

  if connected_fluidboxes then
    for _,other_fluidbox in pairs(connected_fluidboxes) do
      local other_box = snap_box_to_grid(other_fluidbox.owner.selection_box)

      -- Look for any of our junctions that lines up on the target's boundary box
      local this_pipe_built = false
      for k, junc in pairs(junctions) do
        if connections_remaining[k] then
          if (junc.y == other_box.right_bottom.y and junc.x >= other_box.left_top.x and junc.x <= other_box.right_bottom.x) or -- match on north side
             (junc.y == other_box.left_top.y and junc.x >= other_box.left_top.x and junc.x <= other_box.right_bottom.x) or     -- match on south side
             (junc.x == other_box.right_bottom.x and junc.y >= other_box.left_top.y and junc.y <= other_box.right_bottom.y) or -- match on east side
             (junc.x == other_box.left_top.x and junc.y >= other_box.left_top.y and junc.y <= other_box.right_bottom.y) then   -- match on west side

            debug_message_with_position(drill,"found junction "..util.positiontostr(junc).." is adjacent to "..other_fluidbox.owner.name.." box "..string.gsub(serpent.line(other_box),"[\n ]",""))
            table.insert(pipes_to_build, pipe_offsets[k])
            this_pipe_built = true
            connections_remaining[k] = nil
          end
        end
      end
      if not this_pipe_built then
        debug_message_with_position(drill, "can't find fluid connectors pointing toward neighbor at "..util.positiontostr(other_fluidbox.owner.position))
      end
    end
  end
    
  -- See if any of the remaining sides are adjacent to pipe ghosts
  for k, t in pairs(connections_remaining) do
    if find_ghost_pipe(drillData, connecting_pipe_positions[k]) then
      debug_message_with_position(drill, "building pipe to ghost pipe at "..util.positiontostr(connecting_pipe_positions[k]))
      table.insert(pipes_to_build, pipe_offsets[k])
    else
      debug_message_with_position(drill, "no ghost pipe found at "..util.positiontostr(connecting_pipe_positions[k]))
    end
  end
  
  -- Only build pipes if we found more than 1 connecting point
  if #pipes_to_build > 1 then
    for k, pipe_target in pairs(pipes_to_build) do
      build_pipe(drillData, pipeType, pipe_target)
    end
      
    -- Check if we need to fill in a corner of an even-sided miner
    -- Pipe construction box is odd-sided if the miner is even-sided
    if ((pipe_box.left_top.x - pipe_box.right_bottom.x) % 2 == 1) and
       ((pipe_box.left_top.y - pipe_box.right_bottom.y) % 2 == 1) then
      join_pipes(drillData, pipeType)
    end
    debug_message_with_position(drill, "connected pipes to "..tostring(#pipes_to_build).." neighbors")
  else
    debug_message_with_position(drill, "can't find fluid connectors pointing toward any neighbors")
  end
end

local function order_deconstruction(drill)
  if drill.to_be_deconstructed(drill.force) then
    debug_message_with_position(drill, "already marked, skipping")
    return
  end
  
  local surface_name = drill.surface.name
  for _,pfx in pairs(blacklist_surface_prefixes) do
    if string.match(surface_name, pfx) then
      debug_message_with_position(drill, "is on blacklisted surface "..surface_name..", skipping")
      return
    end
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
      is_space = ( se_zone and remote.call("space-exploration", "get_zone_is_space", {zone_index = se_zone.index}) ) or false
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

  if not settings.global['autodeconstruct-remove-wired'].value then
    if next(drill.circuit_connected_entities.red) ~= nil or next(drill.circuit_connected_entities.green) ~= nil then
      debug_message_with_position(drill, "is hooked up to the circuit network and wire deconstruction is not enabled, skipping")

      return
    end
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

  if settings.global['autodeconstruct-preserve-inserter-chains'].value and drill.burner and #find_extracting(drill)>0 then
    debug_message_with_position(drill, "is part of inserter chain, skipping")

    return
  end

  -- end guards

  if settings.global['autodeconstruct-remove-target'].value then
    deconstruct_target(drill)
  end
  
  if settings.global['autodeconstruct-remove-beacons'].value then
    deconstruct_beacons(drill)
  end

  if settings.global['autodeconstruct-remove-belts'].value then
    deconstruct_belts(drill)
  end
  
  local ent_dat = {name=drill.name, position=drill.position}
  if drill.order_deconstruction(drill.force) then
    if drill and drill.valid then
      debug_message_with_position(drill, "marked for deconstruction")
      -- Handle pipes
      if has_fluid and settings.global['autodeconstruct-build-pipes'].value then
        debug_message_with_position(drill, "trying to add pipe blueprints")
        build_pipes(drill, pipeType)
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

-- Queue contents:
-- Drill: {tick=decon_tick, timeout=timeout_tick, drill=drill, target=target, target_lp = lp, target_line = target_line}
function autodeconstruct.process_queue()
  if global.drill_queue and next(global.drill_queue) then
    for i, entry in pairs(global.drill_queue) do
      local deconstruct_drill = false
      
      if not entry.drill or not entry.drill.valid then
        -- no valid drill or belts to deconstruct, purge from queue and check a different entry
        table.remove(global.drill_queue, i)
        
      elseif game.tick >= entry.timeout then
        -- When timeout occurs, deconstruct everything
        deconstruct_drill = true
        
      elseif game.tick >= entry.tick then
        -- Check conditions to see if we can deconstruct early
        if entry.target then
          if entry.target.get_inventory(defines.inventory.chest).is_empty() then
            deconstruct_drill = true  -- chest is empty
          elseif entry.lp and table_size(entry.lp.targeted_items_pickup)==0 then
            deconstruct_drill = true  -- no robots coming to pick up
          end
        elseif entry.target_line then
          if #entry.target_line == 0 then
            deconstruct_drill = true  -- belt transport line is empty
          end
        else
          deconstruct_drill = true -- no output chest or belt needs to be checked, deconstruct immediately
        end
      end
      
      if deconstruct_drill then
        order_deconstruction(entry.drill)
        table.remove(global.drill_queue, i)
        break
      end
    
    end
  end
end
