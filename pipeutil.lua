require "util"

pipeutil = {}


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

function pipeutil.build_pipes(drill, pipeType)
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


return pipeutil
