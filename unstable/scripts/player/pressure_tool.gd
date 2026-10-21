class_name PressureTool
extends CrewTool
## Pressure tool. LMB or RMB on a valve opens or closes it by 25%. Aimed
## anywhere else, holding LMB blasts and holding RMB pulls loose props: a
## bounded force in a cone in front of the player (host-side).

@export var blast_force := 650.0
@export var blast_range := 7.0
## Half-angle of the blast cone (radians).
@export var blast_cone := 0.45

## Host: +1 blasting, -1 pulling, 0 idle.
var _blast := 0.0


func primary(target: InteractPoint) -> void:
	if handles_point(target):
		crew.mission.send("valve", crew.path_to(target), "", Vector3(0.25, 0, 0))
	else:
		crew.start_hold("primary", "blast", null, 1.0)


func secondary(target: InteractPoint) -> void:
	if handles_point(target):
		crew.mission.send("valve", crew.path_to(target), "", Vector3(-0.25, 0, 0))
	else:
		crew.start_hold("secondary", "blast", null, -1.0)


func prompt(target: InteractPoint) -> String:
	var valve := target.get_parent() as Valve
	if valve == null:
		return "%s · LMB open · RMB close" % target.describe()
	var drives := " (drives %s)" % valve.feeds if valve.feeds != "" else ""
	return "%s valve%s · %d%% open · LMB open 25%% · RMB close 25%%" % [
		valve.display_name, drives, roundi(valve.opening * 100.0)]


func hold_kinds() -> PackedStringArray:
	return ["blast"]


func host_start(_path: String, v: Vector3, _f: float) -> void:
	_blast = signf(v.x)


func host_stop() -> void:
	_blast = 0.0


func _physics_process(_delta: float) -> void:
	if _blast == 0.0:
		return
	var origin := crew.head.global_position
	var dir := -crew.head.global_basis.z
	for p in crew.mission.props():
		if p.freeze:
			continue
		var to := p.global_position - origin
		var d := to.length()
		if d > blast_range or d < 0.1 or dir.angle_to(to) > blast_cone:
			continue
		if _blast < 0.0 and d < 1.4:
			continue
		p.sleeping = false
		p.apply_central_force(to / d * blast_force * (1.0 - d / blast_range) * _blast)


func surface_prompt() -> String:
	return "hold LMB blast · hold RMB pull"
