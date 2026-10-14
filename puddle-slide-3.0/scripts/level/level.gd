class_name Level
extends Node2D
## Root of a level scene. Expects:
##   Ground   - TileMapLayer painted with res://tiles/tileset.tres (ground, one-way planks, vapor vents)
##   Player   - an instance of res://scenes/player/droplet.tscn
## Every other object (enemies, modifiers, breakables, dew, checkpoints, spikes, goal) can be
## dropped anywhere under the level, usually inside the folder nodes.

@onready var ground: TileMapLayer = $Ground
@onready var player: Droplet = $Player

var pixel_size := Vector2.ZERO
var dew_count := 0
var _breakables := {}  # Vector2i -> Breakable


func _ready() -> void:
	var used := ground.get_used_rect()
	pixel_size = Vector2(used.end) * GameConst.TILE
	player.fall_limit = pixel_size.y + 200.0
	player.set_camera_limits(Rect2(Vector2.ZERO, pixel_size))

	for b: Breakable in get_tree().get_nodes_in_group("breakable"):
		b.cell = Vector2i((b.global_position / GameConst.TILE).floor())
		b.level = self
		_breakables[b.cell] = b
	dew_count = get_tree().get_nodes_in_group("dew").size()


func break_cluster(start: Vector2i) -> void:
	# Flood-fill connected breakables; stagger them for a crumbling effect.
	var queue: Array[Vector2i] = [start]
	var seen := {start: 0}
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		var b: Breakable = _breakables.get(cell)
		if b == null:
			continue
		b.break_now(seen[cell] * 0.05)
		_breakables.erase(cell)
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = cell + d
			if _breakables.has(n) and not seen.has(n):
				seen[n] = seen[cell] + 1
				queue.append(n)
