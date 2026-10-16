class_name CrewTool
extends Node
## Base class for the hand tools. They are children of the player's Tools node,
## and their order there is the 1/2/3 hotkey order.
##
## Owner side: primary() and secondary() turn clicks on the aimed InteractPoint
## into Mission requests.
## Host side: host_start() and host_stop() run continuous effects (reeling,
## blasting) using the crew member's replicated aim.

@export var display_name := "TOOL"
@export var color := Color.WHITE
## Size of the box the player holds (the Head/ToolModel mesh is scaled to it).
@export var model_size := Vector3(0.1, 0.1, 0.3)
## InteractPoint kinds this tool works on (used for "switch to …" hints).
@export var handles: PackedStringArray = []

var crew: CrewMember


func _ready() -> void:
	crew = get_parent().get_parent() as CrewMember


func handles_point(target: InteractPoint) -> bool:
	return target != null and target.kind in handles


## Owner: LMB pressed. `target` is the aimed InteractPoint or null.
func primary(_target: InteractPoint) -> void:
	pass


## Owner: RMB pressed.
func secondary(_target: InteractPoint) -> void:
	pass


## Owner: HUD text for a target this tool handles.
func prompt(_target: InteractPoint) -> String:
	return ""


## Owner: the player switched to another tool.
func deselected() -> void:
	pass


## Host: begin a continuous effect requested by this player.
func host_start(_path: String, _v: Vector3, _f: float) -> void:
	pass


## Host: end it.
func host_stop() -> void:
	pass
