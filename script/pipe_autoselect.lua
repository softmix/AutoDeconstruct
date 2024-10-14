
local function find_pipes_to_build(drill)
  -- Box with coordinates of entity grid boundary
  local box = snap_box_to_grid(drill.selection_box)
  -- Box with coordinates of pipes placed inside the entity boundary
  local pipe_box = {left_top =     vectorAdd(vectorSub(box.left_top, drill.position), {0.5,0.5}),
                    right_bottom = vectorSub(vectorSub(box.right_bottom, drill.position), {0.5,0.5}) }

  -- With the new API, only one check is needed to get the coordinates of each fluidbox that is connected to any fluidbox (including ghosts and undergrounds!)
  local pipes_to_build = {}
  for k, connection in pairs(drill.fluidbox.get_pipe_connections(1)) do
    if connection.connection_type == "normal" and connection.target then
      table.insert(pipes_to_build, vectorSub(connection.position, drillData.position))
    end
  end
  
  return pipes_to_build
end


local function get_available_pipes(drill)

  -- Check what pipes can be connected to this drill's neighbors
  

  
  
  local networks = drill.surface.find_logistic_networks_by_construction_area(pipe_box.left_top, drill.force)
  local networks2 = drill.surface.find_logistic_networks_by_construction_area(pipe_box.right_bottom, drill.force)
  for _,network in pairs(networks2) do
    local new = true
    for _,n in pairs(networks) do
      if n == network then
        new = false
        break
      end
    end
    if new then
      table.insert(networks, network)
    end
  end
  
  -- Now see what pipes are available in each network
end


function can_build_pipes(drillData)
  

end
