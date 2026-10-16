class_name ExtractionLever
extends Node3D
## Calls (or cancels) the lift of `zone` when a player uses it.

@export var display_name := "Extraction lever"
@export var zone: ExtractionZone

@onready var handle: Node3D = $Handle
@onready var label: Label3D = $Label


func _process(delta: float) -> void:
	if zone == null:
		return
	var calling := zone.is_counting()
	handle.rotation.x = lerpf(handle.rotation.x, -0.9 if calling else 0.6, 1.0 - exp(-8.0 * delta))
	if calling:
		label.text = "LIFT DEPARTS IN %d\n[E] cancel" % ceili(zone.timer)
		label.modulate = Color(1.0, 0.85, 0.2)
	else:
		label.text = "CALL EXTRACTION\n[E]"
		label.modulate = Color(0.5, 1.0, 0.6)
