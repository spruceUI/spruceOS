# PortMaster hooks

PortMaster's spruce files (`control.txt`, `PortMaster.txt`, `mod_spruce.txt`)
stay minimal and each sources one file here. Device-specific settings go
here, not upstream.

| hook | sourced by | runs in |
|---|---|---|
| `control.txt` | spruce control.txt | every port's shell |
| `portmaster.txt` | spruce PortMaster.txt, App/PortMaster/launch.sh | the GUI launch |
| `mod.txt` | mod_spruce.txt | every port's shell, after control.txt |

Hooks may assume `$PLATFORM` (they source helperFunctions.sh if unset) and
must be safe to source twice.
