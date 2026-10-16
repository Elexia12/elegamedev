class_name Valve
extends Node3D
## Pressure-network valve, turned in 25% steps with the Pressure tool.
## The Mission reads valves by channel: "jack" feeds the gate's hydraulic jack,
## "drain" runs the flood pump (bleeds pressure, empties the bonus chamber,
## dumps that water into the lower facility).

@export var display_name := "Valve"
@export_enum("jack", "drain") var channel := "jack"
@export_range(0.0, 1.0, 0.25) var opening := 0.0

@onready var wheel: Node3D = $Wheel/Mesh
@onready var label: Label3D = $Label


func _ready() -> void:
	add_to_group("net")
	add_to_group("valves")


func _process(delta: float) -> void:
	wheel.rotation.y = lerp_angle(wheel.rotation.y, opening * TAU * 0.75, 1.0 - exp(-8.0 * delta))
	label.text = "%s\n%d%% OPEN" % [display_name.to_upper(), roundi(opening * 100.0)]


func net_get() -> Array:
	return [opening]


func net_set(s: Array) -> void:
	opening = s[0]
