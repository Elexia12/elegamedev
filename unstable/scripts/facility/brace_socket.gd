class_name BraceSocket
extends Node3D
## A valid brace point. Bracing a Support slows its decay; bracing a Gate stops
## it closing below its current height. Braces have a visible load limit and
## snap (and are lost) when it runs out.

@export var target_path: NodePath
## Visual length of the brace when holding a support.
@export var brace_length := 3.2
@export var min_gate_height := 1.0

var braced := false
var integrity := 100.0
var mission: Mission
var _mat: StandardMaterial3D

@onready var point: InteractPoint = $Point
@onready var brace_mesh: MeshInstance3D = $Brace


func _ready() -> void:
	add_to_group("net")
	mission = Mission.of(self)
	_mat = StandardMaterial3D.new()
	brace_mesh.material_override = _mat


func target() -> Node:
	return get_node_or_null(target_path)


## Empty string when a brace can go here, otherwise the reason it can't.
func block_reason() -> String:
	var t := target()
	if braced:
		return "Already braced"
	if t is Gate and t.height < min_gate_height:
		return "Gate too low to brace — open it past %.1f m first" % min_gate_height
	if t is Support and t.health <= 0.0:
		return "%s has already failed" % t.display_name
	return ""


func place() -> void:
	braced = true
	integrity = 100.0
	var t := target()
	if t is Gate:
		t.brace_min = t.height


func remove() -> void:
	braced = false
	var t := target()
	if t is Gate:
		t.brace_min = -1.0


## Host: wear the brace. `per_second` is integrity lost per second.
func apply_load(per_second: float, delta: float) -> void:
	if not braced:
		return
	integrity -= per_second * delta
	if integrity <= 0.0:
		var t := target()
		mission.log_incident("Brace on %s snapped under load" % (t.display_name if t else "?"))
		remove()


func _process(_delta: float) -> void:
	brace_mesh.visible = braced
	if not braced:
		return
	var length := brace_length
	var t := target()
	if t is Gate:
		length = maxf(t.brace_min, 0.05)
	brace_mesh.scale = Vector3(0.22, length, 0.22)
	brace_mesh.position.y = length / 2.0
	_mat.albedo_color = Color(0.9, 0.2, 0.1).lerp(Color(1.0, 0.55, 0.1), integrity / 100.0)


func net_get() -> Array:
	return [braced, integrity]


func net_set(s: Array) -> void:
	braced = s[0]
	integrity = s[1]
