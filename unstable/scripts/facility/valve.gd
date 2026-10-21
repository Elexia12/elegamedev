class_name Valve
extends Node3D
## A valve wheel. Two ways to turn it:
##   turn(step)   in 25% steps (the Flooded Reactor's Pressure tool)
##   crank(dir)   continuously, while someone holds a wrench on it (Blackwater
##                Station). A full turn from open to shut takes `crank_time`
##                seconds for one person; the wheel spins `turns` times.
## Consumers reference the valve that controls them (the Gate jack, the
## DrainPump, a WaterMain). `channel` is just a label for the HUD and tests.

@export var display_name := "Valve"
@export_enum("jack", "drain", "inlet") var channel := "jack"
@export_range(0.0, 1.0, 0.05) var opening := 0.0
## What this valve drives, shown on its label and in the aim prompt.
@export var feeds := ""
## Seconds of cranking to go from fully open to fully shut.
@export var crank_time := 8.0
## Wheel revolutions from shut to fully open (visual).
@export var turns := 0.75
## Only show the label within this distance (m) of your crew member (0 = always).
@export var show_within := 0.0

var _mission: Mission

@onready var wheel: Node3D = $Wheel/Mesh
@onready var label: Label3D = $Label
@onready var crank_sound: LoopSound = get_node_or_null("CrankSound")
var _heard_opening := -1.0
var _crank_hold := 0.0


func _ready() -> void:
	add_to_group("net")
	add_to_group("valves")
	_mission = Mission.of(self)


## Host: open (positive) or close (negative) by `step`, snapped to 25%.
func turn(step: float) -> void:
	opening = clampf(snappedf(opening + step, 0.25), 0.0, 1.0)


## Host: crank it open (dir > 0) or shut (dir < 0) for `delta` seconds.
func crank(dir: float, delta: float) -> void:
	opening = clampf(opening + signf(dir) * delta / crank_time, 0.0, 1.0)


func _process(delta: float) -> void:
	# The wheel ratchets while it's being turned (every peer, from `opening`).
	if _heard_opening >= 0.0 and absf(opening - _heard_opening) > 0.0001:
		_crank_hold = 0.25
	_heard_opening = opening
	_crank_hold -= delta
	if crank_sound:
		crank_sound.level = 1.0 if _crank_hold > 0.0 else 0.0
	wheel.rotation.y = lerp_angle(wheel.rotation.y, opening * TAU * turns, 1.0 - exp(-8.0 * delta)) \
		if turns <= 1.0 else opening * TAU * turns
	label.visible = show_within <= 0.0 or _mission == null or _mission.local_distance(global_position) <= show_within
	label.text = "%s\n%d%% OPEN" % [display_name.to_upper(), roundi(opening * 100.0)]
	if feeds != "":
		label.text += "\n→ %s" % feeds.to_upper()


func net_get() -> Array:
	return [opening]


func net_set(s: Array) -> void:
	opening = s[0]
