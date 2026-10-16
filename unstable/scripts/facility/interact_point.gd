class_name InteractPoint
extends Area3D
## Forgiving aim target for the tools and the interact key. Players aim at
## these (generous sphere) instead of at exact meshes. The parent owns the
## behaviour: Anchor, BraceSocket, Valve, ExtractionLever, or for hooks the
## nearest ancestor that accepts cable force (Prop or Gate).

const MARKER_COLORS := {
	"hook": Color(1.0, 0.8, 0.1),
	"anchor": Color(1.0, 0.8, 0.1),
	"brace": Color(1.0, 0.45, 0.1),
	"valve": Color(0.2, 0.85, 1.0),
	"lever": Color(0.3, 1.0, 0.4),
}

@export_enum("hook", "anchor", "brace", "valve", "lever") var kind := "hook"
@export var show_marker := true


func _ready() -> void:
	if show_marker and (kind == "hook" or kind == "anchor"):
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.08
		torus.outer_radius = 0.16
		ring.mesh = torus
		var mat := StandardMaterial3D.new()
		mat.albedo_color = MARKER_COLORS[kind]
		mat.emission_enabled = true
		mat.emission = MARKER_COLORS[kind] * 0.5
		ring.material_override = mat
		ring.rotation.x = PI / 2
		add_child(ring)


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
