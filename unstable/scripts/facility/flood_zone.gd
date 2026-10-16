class_name FloodZone
extends Node3D
## Controlled flooding (no fluid simulation): one water level shared by all of
## its FloodVolume children. Water leaks in by itself (`inflow`), drains away
## slowly (`sump`), and other nodes move water with add_water(): the
## DrainPump, or a pressure burst.

@export var display_name := "Flood zone"
@export var max_level := 2.0
@export var level := 0.0
## Level gained per second at zero / full instability (a leaking breach).
@export var inflow := 0.0
@export var inflow_unstable := 0.0
## Level lost per second through floor drains.
@export var sump := 0.0

var mission: Mission


func _ready() -> void:
	add_to_group("net")
	add_to_group("floods")
	mission = Mission.of(self)


func volumes() -> Array[FloodVolume]:
	var out: Array[FloodVolume] = []
	for c in get_children():
		if c is FloodVolume:
			out.append(c)
	return out


func add_water(amount: float) -> void:
	level = clampf(level + amount, 0.0, max_level)


func covers(p: Vector3) -> bool:
	for v in volumes():
		if v.covers(p):
			return true
	return false


## World Y of the surface above `p`, or -INF if this zone isn't wet there.
func surface_at(p: Vector3) -> float:
	if level > 0.01 and covers(p):
		return global_position.y + level
	return -INF


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or not mission.running():
		return
	add_water((inflow + inflow_unstable * mission.clock.instability() - sump) * delta)


func net_get() -> Array:
	return [level]


func net_set(s: Array) -> void:
	level = s[0]
