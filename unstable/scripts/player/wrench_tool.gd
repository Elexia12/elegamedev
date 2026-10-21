class_name WrenchTool
extends CrewTool
## Adjustable wrench. Hold LMB on a Mounting's bolts to undo them (stay on
## them: look away and you stop). Hold LMB on a valve wheel to crank it shut,
## RMB to crank it open. Two wrenches on the same bolts work twice as fast.
## A tremor knocks the wrench off the bolts.

## Owner: the point we're working on while the button is held.
var _target: InteractPoint = null
## Host: what this player's wrench is on, and which way a valve turns.
var _point: InteractPoint = null
var _dir := 0.0


func primary(target: InteractPoint) -> void:
	if not handles_point(target):
		return
	var m := target.get_parent() as Mounting
	if m and m.released:
		return
	_target = target
	crew.start_hold("primary", "wrench", target, -1.0)


func secondary(target: InteractPoint) -> void:
	if not handles_point(target) or not target.get_parent() is Valve:
		return
	_target = target
	crew.start_hold("secondary", "wrench", target, 1.0)


func prompt(target: InteractPoint) -> String:
	var m := target.get_parent() as Mounting
	if m:
		var item := m.item.display_name if m.item else "it"
		return "%s · hold LMB to unbolt %s (%d%%) · two wrenches = twice as fast" % [
			m.display_name, item, roundi(m.progress * 100.0)]
	var v := target.get_parent() as Valve
	if v:
		var drives := " (drives %s)" % v.feeds if v.feeds != "" else ""
		return "%s%s %d%% open · hold LMB crank shut · hold RMB crank open" % [
			v.display_name, drives, roundi(v.opening * 100.0)]
	return ""


func deselected() -> void:
	_target = null


func hold_kinds() -> PackedStringArray:
	return ["wrench"]


func _process(_delta: float) -> void:
	# Owner: the wrench only works while you keep it on the bolts.
	if _target and crew.is_multiplayer_authority():
		if not crew.is_holding_button():
			_target = null
		elif crew.aim_target != _target:
			_target = null
			crew.cancel_hold()


func host_start(path: String, v: Vector3, _f: float) -> void:
	_point = crew.mission.get_node_or_null(path) as InteractPoint
	_dir = v.x


func host_stop() -> void:
	_point = null


func _physics_process(delta: float) -> void:
	if _point == null or not multiplayer.is_server():
		return
	if crew.head.global_position.distance_to(_point.global_position) > CrewMember.AIM_REACH + 1.0:
		_end("Too far away")
		return
	var owner_node := _point.get_parent()
	if owner_node is Mounting:
		if not owner_node.work(delta):
			_end("" if owner_node.released else "The wrench slipped off the bolts!")
	elif owner_node is Valve:
		owner_node.crank(_dir, delta)


func _end(msg: String) -> void:
	_point = null
	crew.mission.incident_log.end_hold(crew.get_multiplayer_authority(), msg)
