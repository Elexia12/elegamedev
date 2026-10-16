@tool
class_name FloodVolume
extends Node3D
## One area a FloodZone fills: a footprint `size` (X by Z) centred on this node.
## The Water child is a unit box stretched to the footprint and the parent
## zone's current level. It previews in the editor too (try changing `level`
## on the FloodZone).

@export var size := Vector2(4.0, 4.0)

@onready var water: MeshInstance3D = $Water


func covers(p: Vector3) -> bool:
	var l := to_local(p)
	return absf(l.x) <= size.x / 2.0 and absf(l.z) <= size.y / 2.0


func _process(_delta: float) -> void:
	var zone := get_parent()
	var level: float = zone.get("level") if zone and zone.get("level") != null else 0.0
	water.visible = level > 0.01
	water.scale = Vector3(size.x, maxf(level, 0.01), size.y)
	water.position.y = level / 2.0
