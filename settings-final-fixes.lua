-- Add se-space-pipe to list of defaults if Space Exploration is loaded
if mods["space-exploration"] then
  data.raw["string-setting"]["autodeconstruct-pipe-name"].default_value = data.raw["string-setting"]["autodeconstruct-pipe-name"].default_value..",se-space-pipe"
end