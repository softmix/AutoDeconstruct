require "script.autodeconstruct"

function msg_all(message)
  if message[1] == "autodeconstruct-debug" then
    table.insert(message, 2, debug.getinfo(2).name)
  end
  for _,p in pairs(game.players) do
    p.print(message)
  end
  log(message)
end


function debug_message_with_position(entity, msg)
  if not storage.debug then return end

  msg_all({"autodeconstruct-debug", util.positiontostr(entity.position) .. " " .. entity.name  .. " " .. msg})
end



local function on_nth_tick()
  local _, err = pcall(autodeconstruct.process_queue)
  if err then msg_all({"autodeconstruct-err-generic", err}) end
  if not next(storage.drill_queue) then
    script.on_nth_tick(17, nil)
  end
end

local function update_tick_event()
  if storage.drill_queue and next(storage.drill_queue) then
    -- Make sure event is enabled
    script.on_nth_tick(17, on_nth_tick)
  else
    -- Make sure event is disabled
    script.on_nth_tick(17, nil)
  end
end


-- Debug command
function cmd_debug(params)
  local cmd = params.parameter
  if cmd == "on" then
    storage.debug = true
    game.print("Autodeconstruct debug prints enabled")
  elseif cmd == "off" then
    storage.debug = false
    game.print("Autodeconstruct debug prints disabled")
  elseif cmd == "init" then
    game.print("Autodeconstruct stored state reset")
    autodeconstruct.init_globals()
    update_tick_event()
  elseif cmd == "print" then
    game.print("Autodeconstruct storage.max_radius = "..tostring(storage.max_radius))
  elseif cmd == "dump" then
    game.print(serpent.block(storage))
  elseif cmd == "dumplog" then
    log(serpent.block(storage))
    game.print("Autodeconstruct storage logged")
  else
    storage.debug = not storage.debug
    if storage.debug then
      game.print("Autodeconstruct debug prints enabled")
    else
      game.print("Autodeconstruct debug prints disabled")
    end
  end
end
commands.add_command("ad-debug", "Usage: ad-debug [on | off | init]", cmd_debug)



script.on_init(function()
  local _, err = pcall(autodeconstruct.init_globals)
  if err then msg_all({"autodeconstruct-err-generic", err}) end
  update_tick_event()
end)

script.on_load(function()
  update_tick_event()
end)

script.on_configuration_changed(function()
  -- Check the pipe settings for valid entity prototypes
  if not autodeconstruct.is_valid_pipe(settings.global["autodeconstruct-pipe-name"].value) then
    msg_all({"autodeconstruct-err-pipe-name", settings.global["autodeconstruct-pipe-name"].value})
  end
  if script.active_mods["space-exploration"] and 
     not autodeconstruct.is_valid_pipe(settings.global["autodeconstruct-space-pipe-name"].value) then
    msg_all({"autodeconstruct-err-pipe-name", settings.global["autodeconstruct-space-pipe-name"].value})
  end
  local _, err = pcall(autodeconstruct.init_globals)
  if err then msg_all({"autodeconstruct-err-generic", err}) end
  update_tick_event()
end)

script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
  if (event.setting == "autodeconstruct-pipe-name" or event.setting == "autodeconstruct-space-pipe-name") then
    if not autodeconstruct.is_valid_pipe(settings.global[event.setting].value) then
      msg_all({"autodeconstruct-err-pipe-name", settings.global[event.setting].value})
    end
  elseif (event.setting == "autodeconstruct-remove-fluid-drills" or 
          event.setting == "autodeconstruct-remove-wired" or
          event.setting == "autodeconstruct-blacklist") then
    local _, err = pcall(autodeconstruct.init_globals)
    if err then msg_all({"autodeconstruct-err-generic", err}) end
  end
  update_tick_event()
end)

script.on_event(defines.events.on_cancelled_deconstruction,
  function(event)
    local _, err = pcall(autodeconstruct.on_cancelled_deconstruction, event)
    if err then msg_all({"autodeconstruct-err-specific", "on_cancelled_deconstruction", err}) end
    update_tick_event()
  end,
  {{filter="type", type="mining-drill"}}
)

script.on_event(defines.events.on_resource_depleted, function(event)
  local _, err = pcall(autodeconstruct.on_resource_depleted, event)
  if err then msg_all({"autodeconstruct-err-specific", "on_resource_depleted", err}) end
  update_tick_event()
end)

------------------------------------------------------------------------------------
--                    FIND LOCAL VARIABLES THAT ARE USED GLOBALLY                 --
--                              (Thanks to eradicator!)                           --
------------------------------------------------------------------------------------
setmetatable(_ENV,{
  __newindex=function (self,key,value) --locked_global_write
    error('\n\n[ER Global Lock] Forbidden global *write*:\n'
      .. serpent.line{key=key or '<nil>',value=value or '<nil>'}..'\n')
    end,
  __index   =function (self,key) --locked_global_read
    error('\n\n[ER Global Lock] Forbidden global *read*:\n'
      .. serpent.line{key=key or '<nil>'}..'\n')
    end ,
  })

if script.active_mods["gvv"] then require("__gvv__.gvv")() end
