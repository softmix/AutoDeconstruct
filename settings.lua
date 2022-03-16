data:extend({
  {
    type = "bool-setting",
    name = "autodeconstruct-remove-target",
    setting_type = "runtime-global",
    default_value = true,
    order = "ad-a",
  },
  {
    type = "bool-setting",
    name = "autodeconstruct-remove-fluid-drills",
    setting_type = "runtime-global",
    default_value = true,
    order = "ad-b",
  },
  {
    type = "bool-setting",
    name = "autodeconstruct-build-pipes",
    setting_type = "runtime-global",
    default_value = true,
    order = "ad-c",
  },
  {
    type = "string-setting",
    name = "autodeconstruct-pipe-name",
    setting_type = "runtime-global",
    default_value = "pipe",
    order = "ad-d",
  },
  {
    type = "string-setting",
    name = "autodeconstruct-space-pipe-name",
    setting_type = "runtime-global",
    default_value = "se-space-pipe",
    hidden = true,
    order = "ad-e",
  }
})
