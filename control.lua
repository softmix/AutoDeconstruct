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

script.on_event(defines.events.on_resource_depleted , function(event)
    local _, err = pcall(autodeconstruct.on_resource_depleted, event)
    if err then msg_all({"autodeconstruct-err-specific", "on_resource_depleted", err}) end
end)
