-- Unhide space pipe setting if space-exploration is loaded
if mods["space-exploration"] then
  data.raw["string-setting"]["autodeconstruct-space-pipe-name"].hidden = false
end
