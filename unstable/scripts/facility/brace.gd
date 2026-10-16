class_name Brace
extends Prop
## A steel brace post you carry ([E]) and stand upright ([R] while holding).
## Wedge it under the gate to hold it open, or stand it in a support's
## BraceZone to prop the support up. Load wears it down: it turns red, then
## buckles. A buckled brace is shorter and bent, and no longer holds anything.

@export var max_integrity := 100.0
@export var bent_length := 1.2

var integrity := 100.0
var bent := false

@onready var mesh: MeshInstance3D = $Mesh
@onready var shape: CollisionShape3D = $Shape
var _mat: StandardMaterial3D


func _ready() -> void:
	super._ready()
	integrity = max_integrity
	_mat = mesh.get_active_material(0).duplicate()
	mesh.material_override = _mat
	shape.shape = shape.shape.duplicate()


## Standing roughly upright and settled, so it can carry load.
func is_bracing() -> bool:
	return not bent and global_basis.y.angle_to(Vector3.UP) < 0.6 and linear_velocity.length() < 0.6


## Host: wear the brace by `amount` integrity.
func apply_load(amount: float) -> void:
	if bent or not multiplayer.is_server():
		return
	integrity -= amount
	if integrity <= 0.0:
		buckle()


func buckle() -> void:
	bent = true
	integrity = 0.0
	mission.incident_log.incident("A brace buckled under the load")
	mission.tremors.jolt(0.25)
	_apply_shape()


func _apply_shape() -> void:
	var box := shape.shape as BoxShape3D
	box.size.y = bent_length if bent else height
	mesh.scale.y = (bent_length / height) if bent else 1.0
	mesh.rotation.z = 0.35 if bent else 0.0


func _process(delta: float) -> void:
	super._process(delta)
	_mat.albedo_color = Color(0.85, 0.15, 0.1).lerp(Color(1.0, 0.55, 0.1), integrity / max_integrity)


func net_get() -> Array:
	return super.net_get() + [integrity, bent]


func net_set(s: Array) -> void:
	super.net_set(s)
	integrity = s[s.size() - 2]
	var was_bent := bent
	bent = s[s.size() - 1]
	if bent != was_bent:
		_apply_shape()
