class_name ExtractionLever
extends Node3D
## Calls (or cancels) the extraction lift. State lives in the Mission.

@export var display_name := "Extraction lever"

var mission: Mission

@onready var handle: Node3D = $Handle
@onready var label: Label3D = $Label


func _ready() -> void:
	mission = Mission.of(self)


func _process(delta: float) -> void:
	if mission == null:
		return
	var calling := mission.extract_timer >= 0.0
	handle.rotation.x = lerpf(handle.rotation.x, -0.9 if calling else 0.6, 1.0 - exp(-8.0 * delta))
	if calling:
		label.text = "LIFT DEPARTS IN %d\n[E] cancel" % ceili(mission.extract_timer)
		label.modulate = Color(1.0, 0.85, 0.2)
	else:
		label.text = "CALL EXTRACTION\n[E]"
		label.modulate = Color(0.5, 1.0, 0.6)
