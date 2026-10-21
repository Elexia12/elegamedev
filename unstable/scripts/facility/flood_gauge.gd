class_name FloodGauge
extends Label3D
## Wall sign that reads a room's water: depth above `floor_y` and its state.
##   DRY       nothing to worry about
##   SHALLOW   slower movement
##   DEEP      electronics get wrecked, wading is hard
##   CRITICAL  over your head: hold your breath or get out
## The Contract lists every gauge (group "flood_gauges") on the HUD.

const STATES := ["DRY", "SHALLOW", "DEEP", "CRITICAL"]
const COLORS := [Color(0.6, 1.0, 0.7), Color(0.6, 0.85, 1.0), Color(1.0, 0.8, 0.25), Color(1.0, 0.35, 0.25)]

@export var zone: FloodZone
@export var room_name := "Room"
## World Y of this room's floor.
@export var floor_y := 0.0
## Depths (m) where SHALLOW, DEEP and CRITICAL begin.
@export var thresholds := PackedFloat32Array([0.1, 0.6, 1.5])


func _ready() -> void:
	add_to_group("flood_gauges")


func depth() -> float:
	if zone == null:
		return 0.0
	return maxf(0.0, zone.global_position.y + zone.level - floor_y)


func state() -> int:
	var s := 0
	for t in thresholds:
		if depth() >= t:
			s += 1
	return s


func state_name() -> String:
	return STATES[state()]


func _process(_delta: float) -> void:
	text = "%s\nWATER %.1f m · %s" % [room_name.to_upper(), depth(), state_name()]
	modulate = COLORS[state()]
