class_name InteractPoint
extends Area3D
## Forgiving aim target for things you operate rather than push around: a
## cable end, a valve, a lever, a hoist pendant or hook, a lifting eye, the
## bolts of a mounting, a truck's ignition. The parent node owns the
## behaviour: [E] calls its use(), and its prompt_for() says what [E] does
## (a point can override both itself, like LiftingEye). Physical objects need
## no InteractPoint: you grab them, winch them or blast them directly.

## Kinds that get a coloured ring so you can spot them.
const MARKER_COLORS := {
	"cable": Color(1.0, 0.8, 0.1),
	"eye": Color(1.0, 0.55, 0.1),
	"bolts": Color(1.0, 0.4, 0.15),
}

@export_enum("cable", "valve", "lever", "pendant", "hook", "eye", "bolts", "ignition", "handle") var kind := "valve"

@onready var marker: MeshInstance3D = $Marker


func _ready() -> void:
	# Only some kinds get a ring; valves, levers and pendants have their own visuals.
	marker.visible = MARKER_COLORS.has(kind)
	if marker.visible:
		var mat := marker.get_active_material(0).duplicate() as StandardMaterial3D
		mat.albedo_color = MARKER_COLORS[kind]
		mat.emission = MARKER_COLORS[kind] * 0.5
		marker.material_override = mat


## The node that handles [E] here: this point if it has use(), else the
## nearest ancestor with use() or prompt_for() (a hoist's Pendant/Point
## belongs to the hoist), else the direct parent.
func handler() -> Node:
	if has_method("use"):
		return self
	var n := get_parent()
	while n and not n is Mission:
		if n.has_method("use") or n.has_method("prompt_for"):
			return n
		n = n.get_parent()
	return get_parent()


## Human-readable name for prompts.
func describe() -> String:
	var n := get_parent()
	if n is Cable:
		return "Cable"
	if n and "display_name" in n:
		return n.display_name
	return kind.capitalize()
