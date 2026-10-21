class_name ProximityLabel
extends Label3D
## A sign that only shows when your crew member is within `show_within`
## metres, so the station isn't covered in text.

@export var show_within := 8.0

var _mission: Mission


func _ready() -> void:
	_mission = Mission.of(self)


func _process(_delta: float) -> void:
	if _mission:
		visible = _mission.local_distance(global_position) <= show_within
