# spruce's PortMaster hooks

PortMaster identifies a firmware and then runs that firmware's `control.txt`,
`PortMaster.txt` and `mod_<CFW>.txt`. For spruce those three files are kept
deliberately small and each ends by sourcing one file from this folder:

| PortMaster file (upstream `PortMaster/spruce/`, staged today from `App/PortMaster/`) | sources | runs in |
|---|---|---|
| `control.txt` | `spruce/portmaster/control.txt` | every port's own shell, before the game starts |
| `PortMaster.txt` | `spruce/portmaster/portmaster.txt` | the PortMaster GUI launch, before pugwash |
| `mod_spruce.txt` | `spruce/portmaster/mod.txt` | every port's shell, right after control.txt |

The split is the point. Upstream owns "what spruce is and where it lives":
paths, the bundled Python, the ports folder. spruce owns "what this board
needs": which SDL2 a device's ports get, library paths, pad maps, the
Anbernic two-SDL2 juggling. That side changes as we learn and nobody
upstream can test it, so it never has to go through a PortMaster PR again.

Everything here can assume `$PLATFORM` (each hook sources helperFunctions.sh
if it is missing) and must stay safe to source more than once.
