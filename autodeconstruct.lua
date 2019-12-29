require "defines"
require "util"

autodeconstruct = {
    drills = {},
	ranges = {},
	known_positions = {},
	to_be_forgotten = {},
}

require "config"

local function find_resource_at(surface, position, range)
    local top_left = {x = position.x - range, y = position.y - range}
    local bottom_right = {x = position.x + range, y = position.y + range}

    local stuff = surface.find_entities_filtered{area={top_left, bottom_right}, type='resource'}
	solid = {}
	for i = 1, #stuff do
		if stuff[i].prototype.resource_category == 'basic-solid' then
			solid[#solid + 1] = stuff[i]
		end
	end
    return solid
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

function autodeconstruct.init_globals()
	drill_entities = find_all_entities('mining-drill')
	for _, drill_entity in pairs(drill_entities) do
		if autodeconstruct.ranges[drill_entity.name] then
			local where = util.positiontostr(drill_entity.position)
			if autodeconstruct.known_positions[where] then else
				autodeconstruct.known_positions[where] = true
				autodeconstruct.add_drill(drill_entity)
			end
		end
	end
	known_positions = {}
end

function autodeconstruct.on_built_entity(event)
	if event.created_entity.type ~= 'mining-drill' then return end
	autodeconstruct.add_drill(event.created_entity)
end

function autodeconstruct.add_drill(new_entity)
	local range = autodeconstruct.ranges[new_entity.name]
	drill = {
		entity = new_entity,
		resources = find_resource_at(new_entity.surface, new_entity.position, range)
	}
	table.insert(autodeconstruct.drills, drill)
end

function autodeconstruct.update_drills(event)
    local drill_to_update = 1 + event.tick % #autodeconstruct.drills
	
	drill = autodeconstruct.drills[drill_to_update]
	if drill.entity and drill.entity.valid then
		autodeconstruct.update_drill(drill, update_cycle)
	else
		autodeconstruct.to_be_forgotten[drill_to_update] = true
	end
	
	if drill_to_update == 1 then
		for i = #autodeconstruct.drills, 1, -1 do
			if autodeconstruct.to_be_forgotten[i] then
				table.remove(autodeconstruct.drills, i)
			end
		end
		autodeconstruct.to_be_forgotten = {}
	end
end

function autodeconstruct.update_drill(drill, update_cycle)
	local amount = 0
	for i = #drill.resources, 1, -1 do
		if drill.resources[i].valid then return end -- if any of the resource nodes are valid we don't need to continue checking
	end
	if amount == 0 then
		autodeconstruct.order_deconstruction(drill)
	end
end

function autodeconstruct.order_deconstruction(drill)
	if drill.entity.to_be_deconstructed(drill.entity.force) then return end
	
	local deconstruct = false
	
	if autodeconstruct.wait_for_robots then
		logistic_network = drill.entity.surface.find_logistic_network_by_position(drill.entity.position, drill.entity.force.name)
		if logistic_network ~= nil then
			if logistic_network.available_construction_robots > 0 then
				deconstruct = true
			end
		end
	else
		deconstruct = true
	end
	
	if deconstruct == true then
		drill.entity.order_deconstruction(drill.entity.force)
	end
end

function autodeconstruct.on_tick(event)
	if #autodeconstruct.drills > 0 then
		autodeconstruct.update_drills(event)
	end
end
