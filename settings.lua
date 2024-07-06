data:extend({
  {
    type = "bool-setting",
    name = "autodeconstruct-preserve-inserter-chains",
    setting_type = "runtime-global",
    default_value = true,
    order = "ad-a",
  },
  {
    type = "bool-setting",
    name = "autodeconstruct-remove-target",
    setting_type = "runtime-global",
    default_value = true,
    order = "ad-aa",
  },
  {
    type = "bool-setting",
    name = "autodeconstruct-remove-beacons",
    setting_type = "runtime-global",
    default_value = true,
    order = "ad-aa",
  },
  {
    type = "bool-setting",
    name = "autodeconstruct-remove-wired",
    setting_type = "runtime-global",
    default_value = false,
    order = "ad-ab",
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
  },
  {
    type = "string-setting",
    name = "autodeconstruct-blacklist",
    setting_type = "runtime-global",
    default_value = "",
    allow_blank = true,
    order = "ad-"
  }
})
