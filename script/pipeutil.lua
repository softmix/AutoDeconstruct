require "util"
local math2d = require("math2d")
local vectorAdd = math2d.position.add
local vectorSub = math2d.position.subtract

pipeutil = {}

-- Build pipes from the given relative target to the center of the miner
local function build_pipe(drillData, pipeType, pipeTarget)
  --log("pipeTarget: "..util.positiontostr(pipeTarget).."; drillData.position: "..util.positiontostr(drillData.position))
  local pipes = {}
  
  -- build in X first, then in Y
  local x = pipeTarget.x
  local y = pipeTarget.y

  -- Build connection point first
  --log("> Building connector pipe at "..util.positiontostr({x=x,y=y}))
  pipes[#pipes+1] = drillData.surface.create_entity{
          name="entity-ghost",
          position = vectorAdd(drillData.position, {x,y}),
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
    pipes[#pipes+1] = drillData.surface.create_entity{
          name="entity-ghost",
          position = vectorAdd(drillData.position, {x,y}),
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
    pipes[#pipes+1] = drillData.surface.create_entity{
          name="entity-ghost",
          position = vectorAdd(drillData.position, {x,y}),
          force=drillData.force,
          inner_name=pipeType,
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


function pipeutil.build_pipes(drill, pipeType)

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
  
  -- With the new API, only one check is needed to get the coordinates of each fluidbox that is connected to any fluidbox (including ghosts and undergrounds!)
  local pipes_to_build = {}
  for k, connection in pairs(drill.fluidbox.get_pipe_connections(1)) do
    if connection.connection_type == "normal" and connection.target then
      table.insert(pipes_to_build, vectorSub(connection.position, drillData.position))
    end
  end
  
  -- Only build pipes if we found more than 1 connecting point
  if #pipes_to_build > 1 then
    for k, pipe_target in pairs(pipes_to_build) do
      local newpipes = build_pipe(drillData, pipeType, pipe_target)
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
    debug_message_with_position(drill, "connected pipes to "..tostring(#pipes_to_build).." neighbors")
  else
    debug_message_with_position(drill, "can't find fluid connectors pointing toward any neighbors")
  end
  
  return pipes
end


return pipeutil
