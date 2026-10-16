class_name ExtractionZone
extends Node3D
## The extraction lift. When the lever is pulled, a countdown runs, then the
## Platform (a moving physics body) rises out of the facility. Whatever is
## physically standing on it rides up with it, crew and cargo alike. Once the
## ride finishes, `departed` fires and the Mission scores whatever is on board.
## The ExtractionLever calls and cancels the lift.

## Emitted on the host when the platform reaches the top.
signal departed

## Footprint of the platform (X, Z) and how high above it counts as on board.
@export var size := Vector3(10.0, 3.0, 5.0)
@export var countdown := 8.0
@export var lift_height := 9.0
@export var lift_time := 6.0

enum Phase { IDLE, COUNTING, RISING, GONE }

var phase := Phase.IDLE
## Countdown seconds left (while COUNTING).
var timer := -1.0
## Platform rise 0..1.
var rise := 0.0
var mission: Mission

@onready var platform: AnimatableBody3D = $Platform


func _ready() -> void:
	add_to_group("net")
	mission = Mission.of(self)


## On the platform right now (footprint, and not far above its deck).
func contains(p: Vector3) -> bool:
	var l := to_local(p)
	var deck := platform.position.y
	return absf(l.x) <= size.x / 2.0 and absf(l.z) <= size.y / 2.0 \
		and l.y >= deck - 0.5 and l.y <= deck + size.y


func is_counting() -> bool:
	return phase == Phase.COUNTING


func is_rising() -> bool:
	return phase == Phase.RISING


## Host: start the countdown, or cancel it if it's running.
func toggle(by: String) -> void:
	if phase == Phase.COUNTING:
		phase = Phase.IDLE
		timer = -1.0
		mission.incident_log.broadcast("%s cancelled extraction" % by, "info")
	elif phase == Phase.IDLE:
		phase = Phase.COUNTING
		timer = countdown
		mission.incident_log.broadcast("%s called the lift — %d s. Get on the pad!" % [by, roundi(countdown)], "phase")


func _physics_process(delta: float) -> void:
	if multiplayer.is_server() and mission.running():
		match phase:
			Phase.COUNTING:
				timer -= delta
				if timer <= 0.0:
					phase = Phase.RISING
					timer = -1.0
			Phase.RISING:
				rise = minf(1.0, rise + delta / lift_time)
				if rise >= 1.0:
					phase = Phase.GONE
					departed.emit()
	# Smoothstep so the lift lurches into motion and eases at the top.
	platform.position.y = lift_height * rise * rise * (3.0 - 2.0 * rise)


func net_get() -> Array:
	return [phase, timer, rise]


func net_set(s: Array) -> void:
	phase = s[0]
	timer = s[1]
	rise = s[2]
