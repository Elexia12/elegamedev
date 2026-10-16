class_name Anchor
extends Node3D
## Authored cable end point. If bolted to a Support, cable tension strains that
## support ("poor attachment choices may shift weight dangerously").

@export var display_name := "Anchor"
@export var support_path: NodePath
@export var show_post := true

## Set by the attached cable every host physics frame.
var tension := 0.0

@onready var point: InteractPoint = $Point


func _ready() -> void:
	add_to_group("anchors")
	if not show_post:
		$Post.queue_free()
		point.position = Vector3.ZERO


func support() -> Support:
	return get_node_or_null(support_path) as Support
