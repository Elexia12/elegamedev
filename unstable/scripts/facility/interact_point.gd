class_name InteractPoint
extends Area3D
## Forgiving aim target for the tools and the interact key. Players aim at this
## generous sphere instead of at exact meshes. The parent owns the behaviour:
## an Anchor, BraceSocket, Valve or ExtractionLever. For hooks it's the nearest
## ancestor that accepts cable force (a Prop or the Gate).

const MARKER_COLORS := {
	"hook": Color(1.0, 0.8, 0.1),
	"anchor": Color(1.0, 0.8, 0.1),
}

@export_enum("hook", "anchor", "brace", "valve", "lever") var kind := "hook"

@onready var marker: MeshInstance3D = $Marker


func _ready() -> void:
	# Only cable points get the yellow ring; other kinds have their own visuals.
	marker.visible = MARKER_COLORS.has(kind)
	if marker.visible:
		var mat := marker.get_active_material(0).duplicate() as StandardMaterial3D
		mat.albedo_color = MARKER_COLORS[kind]
		mat.emission = MARKER_COLORS[kind] * 0.5
		marker.material_override = mat


## For hooks: the node that receives cable force (has add_cable_force()).
func receiver() -> Node:
	var n := get_parent()
	while n and not n.has_method("add_cable_force"):
		n = n.get_parent()
	return n


## Human-readable name for prompts.
func describe() -> String:
	var n: Node = receiver() if kind == "hook" else get_parent()
	if n is BraceSocket:
		var t: Node = n.target()
		return t.display_name if t else "Brace point"
	if n and "display_name" in n:
		return n.display_name
	return kind.capitalize()
