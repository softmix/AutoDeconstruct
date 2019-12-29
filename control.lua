require "autodeconstruct"

function msg_all(message)
    for _,p in pairs(game.players) do
        p.print(message)
    end
end

script.on_init(function()
    local _, err = pcall(autodeconstruct.init_globals)
    if err then msg_all({"autodeconstruct-err-generic", err}) end
end)

script.on_configuration_changed(function()
    local _, err = pcall(autodeconstruct.init_globals)
    if err then msg_all({"autodeconstruct-err-generic", err}) end
end)

script.on_event(defines.events.on_built_entity, function(event)
    local _, err = pcall(autodeconstruct.on_built_entity, event)
    if err then msg_all({"autodeconstruct-err-specific", "on_built_entity", err}) end
end)

script.on_event(defines.events.on_player_created, function(event)
    local _, err = pcall(autodeconstruct.init_globals, event)
    if err then msg_all({"autodeconstruct-err-specific", "on_player_created", err}) end
end)

script.on_event(defines.events.on_robot_built_entity, function(event)
    local _, err = pcall(autodeconstruct.on_built_entity, event)
    if err then msg_all({"autodeconstruct-err-specific", "on_robot_built_entity", err}) end
end)

script.on_event(defines.events.on_tick, function(event)
    local _, err = pcall(autodeconstruct.on_tick, event)
    if err then msg_all({"autodeconstruct-err-specific", "on_tick", err}) end
end)