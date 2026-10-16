class_name Vitals
extends Node
## Breath and knockouts, run by the owning peer. With your head underwater,
## breath drains, and at zero you black out. A hard enough hit (rubble, a
## falling gate) knocks you out too. After `knockout_time` you respawn at the
## lift. `knocked` is replicated so everyone sees you go down.

signal knocked_out(reason: String)
signal recovered

@export var breath_max := 10.0
## Breath regained per second above water.
@export var recovery_rate := 2.5
@export var knockout_time := 5.0

var breath := 10.0
var knocked := false
var crew: CrewMember
var _timer := 0.0


func _ready() -> void:
	crew = get_parent() as CrewMember
	breath = breath_max


## Owner: black out now.
func knock_out(reason: String) -> void:
	if knocked:
		return
	knocked = true
	_timer = knockout_time
	knocked_out.emit(reason)


func _physics_process(delta: float) -> void:
	if crew.mission == null or not crew.is_multiplayer_authority():
		return
	if knocked:
		_timer -= delta
		if _timer <= 0.0:
			knocked = false
			breath = breath_max
			recovered.emit()
		return
	var head := crew.head.global_position
	if crew.mission.water_surface_at(head) > head.y:
		breath -= delta
		if breath <= 0.0:
			knock_out("%s blacked out underwater" % crew.display_name)
	else:
		breath = minf(breath_max, breath + recovery_rate * delta)
