class_name JackPoint
extends Area3D
## Marked spot where a SupportJack can be extended to hold up the structure
## above. Stand the jack upright inside it and press [E] on the jack.
## `ram_height` is how far the ram extends from the top of the jack body to
## reach the structure.

@export var ram_height := 1.8


func _ready() -> void:
	add_to_group("jack_points")
