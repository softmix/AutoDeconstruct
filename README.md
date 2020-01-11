# Auto Deconstruct
Mod for Factorio that marks drills that have no more resources to mine for deconstruction.

Automatically marks your mining drills for deconstruction when they run out of resources to mine, send spent miners and their modules back to base instead of leaving them idling in the field.
Optionally removes the chest that the drill is outputting to (enabled by default).

https://mods.factorio.com/mod/AutoDeconstruct

 There are remote calls for debug and init.
 
     /c remote.call("ad","init")
     /c remote.call("ad","debug")

## Releasing
- Update `changelog.txt` with relevant information
- Bump version in `info.json`
- Run `make`
- Manually playtest by putting the resulting zip in the Factorio `mods/` folder.
- Upload to mod portal.
