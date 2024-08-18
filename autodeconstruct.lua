beltutil = require("beltutil")
pipeutil = require("pipeutil")
autodeconstruct = {}

blacklist_surface_prefixes = {"BPL_TheLab", "bpsb%-lab"}

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

function autodeconstruct.is_valid_pipe(name)
  return game.entity_prototypes[name] and game.entity_prototypes[name].type == "pipe"
end

local function queue_deconstruction(drill)
  global.drill_queue = global.drill_queue or {}
  local decon_tick = game.tick + 30  -- by default, wait just long enough to eject the last item
  local timeout_tick = decon_tick + 1800  -- wait at most 30 seconds for items to clear out
  local target = find_target(drill)
  local target_line = beltutil.find_target_line(drill, target)
  if target_line then
    target = nil  -- Don't look for chest stuff if we have a transport line
  end
  local lp = nil
  if target then
    if target.type == "logistic-container" then
      lp = target.get_logistic_point()[1]  -- logistic container means keep target and store logistic point
    elseif target.type ~= "container" then
      target = nil  -- not logistic container and not container means don't keep target, it's something we can't deconstruct
    end
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
  if target ~= nil and target.minable and target.prototype.selectable_in_game and not global.blacklist[target.name] and beltutil.belt_type_check[target.type] then
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


local function deconstruct_belts(drill)
  local to_deconstruct_list = {}
  local to_deconstruct_map = {}
  
  -- 1. Check if the target of this drill is a belt
  local target = find_target(drill)
  if not target or not target.valid or not (target.type == "transport-belt" or target.type == "underground-belt" or target.type == "splitter") then
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
      local upstream_belts_to_check = beltutil.get_belt_inputs(next_start_belt, to_deconstruct_map)  -- List of belts upstream of the first safe belt
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
      local next_start_outputs = beltutil.get_belt_outputs(next_start_belt, to_deconstruct_map)
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
        for _,belt in pairs(beltutil.get_belt_inputs(next_belt, to_deconstruct_map)) do
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
          --belt.order_deconstruction(belt.force)
          table.insert(to_deconstruct_list, belt)
          to_deconstruct_map[belt.unit_number] = true
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
  
  -- After all that, we have a list of belts we "virtually deconstructed".
  -- Add this to the global queue as an entry that gets checked.
  -- The idea is that we only deconstruct belts before the timeout if they are empty and have no inputs.
  -- If there are loops or items stuck behind underground belts, those will wait for the timeout.
  -- Every time we successfully deconstruct an empty belt, extend the timeout a bit.
  -- Is there any sorting we can do to make it easier to find the next one that will be empty?
  table.insert(global.drill_queue, {tick=game.tick+30, timeout=game.tick+1830, belt_list = to_deconstruct_list})
  
  -- Temporary instant deconstruction
  -- for _,belt in pairs(to_deconstruct_list) do
    -- belt.order_deconstruction(belt.force)
  -- end
  
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
        pipeutil.build_pipes(drill, pipeType)
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
      
      if entry.drill then
        local deconstruct_drill = false
        
        if not entry.drill.valid then
          -- no valid drill or belts to deconstruct, purge from queue and check a different entry
          table.remove(global.drill_queue, i)
          break
        elseif game.tick >= entry.timeout then
          -- When timeout occurs, deconstruct everything
          deconstruct_drill = true
          
        elseif game.tick >= entry.tick then
          -- Check conditions to see if we can deconstruct early
          if entry.target and entry.target.valid then
            local inv = entry.target.get_inventory(defines.inventory.chest)
            if not inv or inv.is_empty() then
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
      
      elseif entry.belt_list then
        if not settings.global['autodeconstruct-remove-belts'].value then
          -- If belts are disabled, clear the queue of belts to remove.
          entry.belt_list = nil
        else
          -- Check the belt network for any that can be deconstructed
          if game.tick >= entry.timeout then
            -- When timeout hits, deconstruct everything at once
            for _,belt in pairs(entry.belt_list) do
              if belt and belt.valid then
                belt.order_deconstruction(belt.force)
              end
            end
            -- Clear the queue entry
            table.remove(global.drill_queue, i)
            --game.print("timed out deconstructing belts")
            break
          else
            for k,belt in pairs(entry.belt_list) do
              if #beltutil.get_belt_inputs(belt) == 0 and beltutil.is_belt_empty(belt) then
                -- Deconstruct this belt that has no inputs and no relevant contents
                if belt and belt.valid then
                  belt.order_deconstruction(belt.force)
                end
                table.remove(global.drill_queue[i].belt_list, k)
                -- Wait at least 5 seconds after the last empty belt was deconstructed before timing out
                global.drill_queue[i].timeout = math.max(global.drill_queue[i].timeout, game.tick + 300)
                break
              end
            end
            -- If we deconstructed every belt as it emptied, clear queue entry
            if table_size(global.drill_queue[i].belt_list) == 0 then
              table.remove(global.drill_queue, i)
              --game.print("finished deconstructing empty belts")
              break
            end
          end
        end
      end
    end
  end
end
