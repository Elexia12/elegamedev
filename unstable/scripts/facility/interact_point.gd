class_name InteractPoint
extends Area3D
## Forgiving aim target for things you operate rather than push around: a
## cable end (to reel or detach it), a valve, or the extraction lever. The
## parent node owns the behaviour. Physical objects need no InteractPoint: you
## grab them, winch them or blast them directly.

const MARKER_COLORS := {
	"cable": Color(1.0, 0.8, 0.1),
}

@export_enum("cable", "valve", "lever") var kind := "valve"

@onready var marker: MeshInstance3D = $Marker


func _ready() -> void:
	# Only cable ends get the yellow ring; valves and levers have their own visuals.
	marker.visible = MARKER_COLORS.has(kind)
	if marker.visible:
		var mat := marker.get_active_material(0).duplicate() as StandardMaterial3D
		mat.albedo_color = MARKER_COLORS[kind]
		mat.emission = MARKER_COLORS[kind] * 0.5
		marker.material_override = mat


## Human-readable name for prompts.
func describe() -> String:
	var n := get_parent()
	if n is Cable:
		return "Cable"
	if n and "display_name" in n:
		return n.display_name
	return kind.capitalize()
