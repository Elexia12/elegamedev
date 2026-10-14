class_name GameConst
## Shared constants for PuddleSlide.

const TILE := 32

# Physics layer bit values (see Project Settings > Layer Names > 2D Physics)
const LAYER_WORLD := 1   # layer 1: solid ground, walls, one-way platforms, breakables
const LAYER_PLAYER := 2  # layer 2: the droplet
const LAYER_ENEMY := 4   # layer 3: enemies
const LAYER_MESH := 8    # layer 4: vapor vents (block everything except vapor)

enum Mod { COLD, HOT, SIZE }
