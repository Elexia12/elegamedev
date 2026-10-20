class_name Valve
extends Node3D
## Pressure-network valve, turned in 25% steps with the Pressure tool.
## Consumers reference the valve that controls them: the Gate (jack valve) and
## the DrainPump. `channel` is just a label for the HUD and tests.

@export var display_name := "Valve"
@export_enum("jack", "drain") var channel := "jack"
@export_range(0.0, 1.0, 0.25) var opening := 0.0
## What this valve drives, shown on its label and in the aim prompt.
@export var feeds := ""

@onready var wheel: Node3D = $Wheel/Mesh
@onready var label: Label3D = $Label


func _ready() -> void:
	add_to_group("net")
	add_to_group("valves")


## Host: open (positive) or close (negative) by `step`, snapped to 25%.
func turn(step: float) -> void:
	opening = clampf(snappedf(opening + step, 0.25), 0.0, 1.0)


func _process(delta: float) -> void:
	wheel.rotation.y = lerp_angle(wheel.rotation.y, opening * TAU * 0.75, 1.0 - exp(-8.0 * delta))
	label.text = "%s\n%d%% OPEN" % [display_name.to_upper(), roundi(opening * 100.0)]
	if feeds != "":
		label.text += "\n→ %s" % feeds.to_upper()


func net_get() -> Array:
	return [opening]


func net_set(s: Array) -> void:
	opening = s[0]
