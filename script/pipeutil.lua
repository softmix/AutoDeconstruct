require "util"
local math2d = require("math2d")
local vectorAdd = math2d.position.add
local vectorSub = math2d.position.subtract

pipeutil = {}

-- Build pipes from the given relative target to the center of the miner
local function build_pipe(drillData, pipeType, pipeTarget)
  --log("pipeTarget: "..util.positiontostr(pipeTarget).."; drillData.position: "..util.positiontostr(drillData.position))
  --log("pipeType: "..serpent.line(pipeType))
  local pipes = {}
  
  -- build in X first, then in Y
  local x = pipeTarget.x or pipeTarget[1]
  local y = pipeTarget.y or pipeTarget[2]

  -- Build connection point first
  --log("> Building connector pipe at "..util.positiontostr({x=x,y=y}))
  pipes[#pipes+1] = drillData.surface.create_entity{
          name="entity-ghost",
          position = vectorAdd(drillData.position, {x=x,y=y}),
          force=drillData.force,
          inner_name=pipeType.name,
          quality=pipeType.quality,
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
    pipes[#pipes+1] = drillData.surface.create_entity{
          name="entity-ghost",
          position = vectorAdd(drillData.position, {x,y}),
          force=drillData.force,
          inner_name=pipeType.name,
          quality=pipeType.quality,
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
    pipes[#pipes+1] = drillData.surface.create_entity{
          name="entity-ghost",
          position = vectorAdd(drillData.position, {x,y}),
          force=drillData.force,
          inner_name=pipeType.name,
          quality=pipeType.quality,
          raise_built=true
        }
  end
  return pipes
end

-- Check the center four tiles of even-sided miners to see if caddy-corner pipes need to be joined
local function join_pipes(drillData, pipeType)
  local pipeGhosts = drillData.surface.find_entities_filtered{position = drillData.position, radius = 1.1, ghost_type = "pipe"}
  --log("> Found "..tostring(#pipeGhosts).." near center of even-sided drill at "..util.positiontostr(drillData.position))
  
  if #pipeGhosts == 2 then
    if pipeGhosts[1].position.x ~= pipeGhosts[2].position.x and pipeGhosts[1].position.y ~= pipeGhosts[2].position.y then
      -- Build a third pipe to connect these two on a diagonal
      --log("Building Diagonal Connecting pipe at relative position " .. util.positiontostr({x=pipeGhosts[1].position.x - drillData.position.x,y=pipeGhosts[2].position.y - drillData.position.y}) )
      return drillData.surface.create_entity{
            name="entity-ghost",
            position = {x = pipeGhosts[1].position.x, y = pipeGhosts[2].position.y},
            force=drillData.force,
            inner_name=pipeType.name,
            quality=pipeType.quality,
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


function pipeutil.build_pipes(drill, pipeType, pipesToBuild)

  local pipes = {}

  local drillData = {
    position  = drill.position,
    direction = drill.direction,
    force     = drill.force,
    owner     = drill.last_user,
    surface   = drill.surface
  }

  --log("Building pipes for drill: "..drill.name.." at "..util.positiontostr(drill.position))
    
  -- Box with coordinates of entity grid boundary
  local box = snap_box_to_grid(drill.selection_box)

  -- Box with coordinates of pipes placed inside the entity boundary
  local pipe_box = {left_top =     vectorAdd(vectorSub(box.left_top, drillData.position), {0.5,0.5}),
                    right_bottom = vectorSub(vectorSub(box.right_bottom, drillData.position), {0.5,0.5}) }
  
  -- Only build pipes if we found more than 1 connecting point
  if #pipesToBuild > 1 then
    for k, pipe_target in pairs(pipesToBuild) do
      local newpipes = build_pipe(drillData, pipeType, pipe_target.offset)
      for _,p in pairs(newpipes) do
        table.insert(pipes, p)
      end
    end
      
    -- Check if we need to fill in a corner of an even-sided miner
    -- Pipe construction box is odd-sided if the miner is even-sided
    if ((pipe_box.left_top.x - pipe_box.right_bottom.x) % 2 == 1) and
       ((pipe_box.left_top.y - pipe_box.right_bottom.y) % 2 == 1) then
      pipes[#pipes+1] = join_pipes(drillData, pipeType)
    end
    debug_message_with_position(drill, "connected pipes to "..tostring(#pipesToBuild).." neighbors")
  else
    debug_message_with_position(drill, "can't find fluid connectors pointing toward any neighbors")
  end
  
  return pipes
end

-- Cache available pipe prototypes
-- Ignore hidden entities, ones with other than 4 normal pipe connections, and ones with dissimilar connection_categories
function pipeutil.cache_pipe_categories()
  storage.category_to_pipe_map = {} -- [category_name] = {list of pipe names}
  storage.pipe_to_category_map = {} -- [pipe_name] = {map of category names=true}
  for name,p in pairs(prototypes.get_entity_filtered{{filter="type",type="pipe"}}) do
    if not p.hidden and p.fluidbox_prototypes and #p.fluidbox_prototypes == 1 then
      local pconns = p.fluidbox_prototypes[1].pipe_connections
      if #pconns == 4 and pconns[1].connection_type == "normal" then
        local good = true
        local cat1 = pconns[1].connection_category
        for k=2,4 do
          if pconns[k].connection_type ~= "normal" or not table.compare(cat1, pconns[k].connection_category) then
            good = false
            break
          end
        end
        if good then
          storage.pipe_to_category_map[name] = util.list_to_map(cat1)
          for _,category in pairs(cat1) do
            storage.category_to_pipe_map[category] = storage.category_to_pipe_map[category] or {}
            table.insert(storage.category_to_pipe_map[category], name)
          end
        end
      end
    end
  end
  storage.default_pipes = {}
  for _,name in pairs(util.split(settings.global['autodeconstruct-pipe-name'].value,",")) do
    if storage.pipe_to_category_map[name] then
      table.insert(storage.default_pipes, name)
    else
      msg_all({"autodeconstruct-err-pipe-name", name})
    end
  end
end



function pipeutil.find_pipes_to_build(drill)
  -- Box with coordinates of entity grid boundary
  local box = snap_box_to_grid(drill.selection_box)
  -- Box with coordinates of pipes placed inside the entity boundary
  local pipe_box = {left_top =     vectorAdd(vectorSub(box.left_top, drill.position), {0.5,0.5}),
                    right_bottom = vectorSub(vectorSub(box.right_bottom, drill.position), {0.5,0.5}) }

  -- With the new API, only one check is needed to get the coordinates of each fluidbox that is connected to any fluidbox (including ghosts and undergrounds!)
  local pipes_to_build = {}
  for k, connection in pairs(drill.fluidbox.get_pipe_connections(1)) do
    if connection.connection_type == "normal" and connection.target then
      -- Determine the connection categories of the other pipe connection
      -- Find which pipe_connection prototype in the connected entity is connected to this one.
      local target_pipe_categories = connection.target.get_prototype(connection.target_fluidbox_index).pipe_connections[connection.target_pipe_connection_index].connection_category
      table.insert(pipes_to_build, {offset=vectorSub(connection.position, drill.position), categories=target_pipe_categories})
    end
  end
  
  return pipes_to_build
end

local function list_intersection(inputs)
  local c = {}
  for _,v in pairs(inputs[1]) do
    -- see if this value is in all the other tables
    local exclude = false
    for k=2,#inputs do
      local found = false
      for _,v2 in pairs(inputs[k]) do
        if v2 == v then
          found = true
          break
        end
      end
      if not found then
        exclude = true
        break
      end
    end
    if not exclude then
      table.insert(c, v)
    end
  end
  return c
end

local function list_union(inputs)
  local c = {}
  for _,list in pairs(inputs) do
    for _,v in pairs(list) do
      local found = false
      for _,cv in pairs(c) do
        if v == cv then
          found = true
          break
        end
      end
      if not found then
        table.insert(c, v)
      end
    end
  end
  return c
end

function pipeutil.choose_pipe(drill, pipes_to_build)

  --log(serpent.line(pipes_to_build))
  -- Find which pipe categories can be used by each connector
  local target_cat_sets = {}
  for k=1,#pipes_to_build do
    target_cat_sets[k] = pipes_to_build[k].categories
  end
  --log(serpent.line(target_cat_sets))
  
  -- Find all the pipes that have at least one category from each set in cats
  local valid_pipes = {}
  -- For each pipe prototype
  for this_name,this_cat_map in pairs(storage.pipe_to_category_map) do
    local found_match_for_all_targets = true
    -- Check its category map against each set
    for _,target_cat_set in pairs(target_cat_sets) do
      -- Check against each category in this set
      local found_match_for_this_target = false
      for _,target_cat in pairs(target_cat_set) do
        if this_cat_map[target_cat] then
          found_match_for_this_target = true
          break
        end
      end
      if not found_match_for_this_target then
        found_match_for_all_targets = false
        break
      end
    end
    if found_match_for_all_targets then
      valid_pipes[this_name] = true
    end
  end
  --log(serpent.line(valid_pipes))
  
  -- Make sure the resulting list of pipes includes something real
  if table_size(valid_pipes) == 0 then return nil end
  
  -- Pick the first applicable default pipe
  local chosen_default = nil
  for _,name in pairs(storage.default_pipes) do
    if valid_pipes[name] then
      chosen_default = name
    end
  end
  -- If priority pipes aren't available, use any valid pipe as the default
  if not chosen_default then
    chosen_default = next(valid_pipes)
  end
  
  local preferred_pipe = {name=chosen_default, quality="normal", count=0}
  
  -- Find the networks that cover the whole drill
  local box = snap_box_to_grid(drill.selection_box)
  local networks = list_intersection{ drill.surface.find_logistic_networks_by_construction_area(vectorSub(box.left_top, drill.position), drill.force), 
                                      drill.surface.find_logistic_networks_by_construction_area(vectorSub(box.right_bottom, drill.position), drill.force)}
  -- Now see what pipes are available in each network
  -- Only stationary networks of this force, so there should only be one
  for _,network in pairs(networks) do
    if #network.cells > 1 or network.cells[1].mobile == false then
      local contents = network.get_contents()
      for _,item in pairs(contents) do
        if valid_pipes[item.name] and item.count > preferred_pipe.count then
          preferred_pipe = table.deepcopy(item)
        end
      end
    end
  end
  
  if preferred_pipe.name then
    debug_message_with_position(drill, "Selected pipe "..serpent.line(preferred_pipe).." from among "..serpent.line(valid_pipes).." to connect neighbors")
    return preferred_pipe
  else
    debug_message_with_position(drill, "No valid pipe to infill depleted fluid miner.")
    return nil
  end
end

return pipeutil
