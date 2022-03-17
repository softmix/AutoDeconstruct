require "autodeconstruct"

function msg_all(message)
  if message[1] == "autodeconstruct-debug" then
    table.insert(message, 2, debug.getinfo(2).name)
  end
  for _,p in pairs(game.players) do
    p.print(message)
  end
end

global.debug = false
remote.add_interface("ad", {
  debug = function()
    global.debug = not global.debug
  end,
  init = function()
    autodeconstruct.init_globals()
  end
})

script.on_init(function()
  local _, err = pcall(autodeconstruct.init_globals)
  if err then msg_all({"autodeconstruct-err-generic", err}) end
end)

script.on_configuration_changed(function()
  if not autodeconstruct.is_valid_pipe(settings.global["autodeconstruct-pipe-name"].value) then
    msg_all({"autodeconstruct-err-pipe-name", settings.global["autodeconstruct-pipe-name"].value})
  end
  if game.active_mods["space-exploration"] and 
     not autodeconstruct.is_valid_pipe(settings.global["autodeconstruct-space-pipe-name"].value) then
    msg_all({"autodeconstruct-err-pipe-name", settings.global["autodeconstruct-space-pipe-name"].value})
  end
  local _, err = pcall(autodeconstruct.init_globals)
  if err then msg_all({"autodeconstruct-err-generic", err}) end
end)

script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
  if (event.setting == "autodeconstruct-pipe-name" or event.setting == "autodeconstruct-space-pipe-name") then
    if not autodeconstruct.is_valid_pipe(settings.global[event.setting].value) then
      msg_all({"autodeconstruct-err-pipe-name", settings.global[event.setting].value})
    end
  elseif (event.setting == "autodeconstruct-remove-fluid-drills" and
      settings.global['autodeconstruct-remove-fluid-drills'].value == true) then
    local _, err = pcall(autodeconstruct.init_globals)
    if err then msg_all({"autodeconstruct-err-generic", err}) end
  end
end)

script.on_event(defines.events.on_cancelled_deconstruction,
  function(event)
    local _, err = pcall(autodeconstruct.on_cancelled_deconstruction, event)
    if err then msg_all({"autodeconstruct-err-specific", "on_cancelled_deconstruction", err}) end
  end,
  {{filter="type", type="mining-drill"}}
)

script.on_event(defines.events.on_resource_depleted, function(event)
  local _, err = pcall(autodeconstruct.on_resource_depleted, event)
  if err then msg_all({"autodeconstruct-err-specific", "on_resource_depleted", err}) end
end)
