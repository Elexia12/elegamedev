class_name ExtractionZone
extends Node3D
## The lift pad. It's a box volume (centred on X/Z, from this node's origin
## upwards) with a departure countdown. Cargo and crew inside when the lift
## leaves are extracted. The ExtractionLever calls and cancels the lift.

## Emitted on the host when the countdown reaches zero.
signal departed

@export var size := Vector3(10.0, 3.0, 5.0)
@export var countdown := 8.0

## Seconds until departure, or -1 when no lift has been called.
var timer := -1.0
var mission: Mission


func _ready() -> void:
	add_to_group("net")
	mission = Mission.of(self)


func contains(p: Vector3) -> bool:
	var l := to_local(p)
	return absf(l.x) <= size.x / 2.0 and absf(l.z) <= size.z / 2.0 and l.y >= -0.5 and l.y <= size.y


func is_counting() -> bool:
	return timer >= 0.0


## Host: start the countdown, or cancel it if it's already running.
func toggle(by: String) -> void:
	if is_counting():
		timer = -1.0
		mission.incident_log.broadcast("%s cancelled extraction" % by, "info")
	else:
		timer = countdown
		mission.incident_log.broadcast("%s called EXTRACTION — lift leaves in %d s. Cargo and crew onto the pad!" % [by, roundi(countdown)], "phase")


func _physics_process(delta: float) -> void:
	if not is_counting() or not multiplayer.is_server() or not mission.running():
		return
	timer -= delta
	if timer <= 0.0:
		timer = -1.0
		departed.emit()


func net_get() -> Array:
	return [timer]


func net_set(s: Array) -> void:
	timer = s[0]
