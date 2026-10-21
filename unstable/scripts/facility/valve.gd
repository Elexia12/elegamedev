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

@onready var wheel: Node3D = $Wheel/Mesh
@onready var label: Label3D = $Label


func _ready() -> void:
	add_to_group("net")
	add_to_group("valves")


## Host: open (positive) or close (negative) by `step`, snapped to 25%.
func turn(step: float) -> void:
	opening = clampf(snappedf(opening + step, 0.25), 0.0, 1.0)


## Host: crank it open (dir > 0) or shut (dir < 0) for `delta` seconds.
func crank(dir: float, delta: float) -> void:
	opening = clampf(opening + signf(dir) * delta / crank_time, 0.0, 1.0)


func _process(delta: float) -> void:
	wheel.rotation.y = lerp_angle(wheel.rotation.y, opening * TAU * turns, 1.0 - exp(-8.0 * delta)) \
		if turns <= 1.0 else opening * TAU * turns
	label.text = "%s\n%d%% OPEN" % [display_name.to_upper(), roundi(opening * 100.0)]
	if feeds != "":
		label.text += "\n→ %s" % feeds.to_upper()


func net_get() -> Array:
	return [opening]


func net_set(s: Array) -> void:
	opening = s[0]
