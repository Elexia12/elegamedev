class_name TruckDeparture
extends Node3D
## The crew's way out. [E] on the Ignition starts a countdown (and [E] again
## cancels it); when it runs out the truck leaves and `departed` fires, which
## ends the run. Crew inside the yard (`yard_size` around this node) leave
## with it; anyone else is left behind.

signal departed

@export var countdown := 10.0
## The yard (X, Y, Z box centred on this node) that counts as "with the truck".
@export var yard_size := Vector3(16.0, 6.0, 22.0)

enum Phase { PARKED, COUNTING, GONE }

var phase := Phase.PARKED
var timer := -1.0
var mission: Mission

@onready var ignition: InteractPoint = $Ignition
@onready var label: Label3D = $Label


func _ready() -> void:
	add_to_group("net")
	mission = Mission.of(self)


func is_counting() -> bool:
	return phase == Phase.COUNTING


func contains(p: Vector3) -> bool:
	var l := to_local(p)
	return absf(l.x) <= yard_size.x / 2.0 and absf(l.z) <= yard_size.z / 2.0 and absf(l.y) <= yard_size.y


func use(player: CrewMember, _target: Node) -> String:
	if phase == Phase.COUNTING:
		phase = Phase.PARKED
		timer = -1.0
		mission.incident_log.broadcast("%s cancelled the departure" % player.display_name, "info")
	elif phase == Phase.PARKED:
		phase = Phase.COUNTING
		timer = countdown
		mission.incident_log.broadcast("%s started the truck — leaving in %d s. Get to the yard!" % [player.display_name, roundi(countdown)], "phase")
	return ""


func prompt_for(_crew: CrewMember, _target: Node) -> String:
	if phase == Phase.COUNTING:
		return "[E] cancel the departure (%d s left)" % ceili(timer)
	return "[E] start the truck and leave · ends the run, secured salvage gets paid"


func _physics_process(delta: float) -> void:
	if mission and multiplayer.is_server() and mission.running() and phase == Phase.COUNTING:
		timer -= delta
		if timer <= 0.0:
			phase = Phase.GONE
			departed.emit()
	match phase:
		Phase.COUNTING:
			label.text = "TRUCK LEAVING IN %d\n[E] cancel" % ceili(timer)
			label.modulate = Color(1.0, 0.85, 0.2)
		Phase.GONE:
			label.text = "TRUCK GONE"
		_:
			label.text = "TRUCK\n[E] start and leave"
			label.modulate = Color(0.5, 1.0, 0.6)


func net_get() -> Array:
	return [phase, timer]


func net_set(s: Array) -> void:
	phase = s[0]
	timer = s[1]
