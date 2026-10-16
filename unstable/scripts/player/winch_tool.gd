class_name WinchTool
extends CrewTool
## Industrial winch. LMB a hook (cargo, gate, beam), then LMB an anchor to rig a
## cable from the Toolkit's pool. Hold LMB or RMB on either end to reel in or
## out. R (handled by the crew member) detaches.

## Owner: hook picked, waiting for an anchor.
var pending_hook: InteractPoint = null
## Host: the cable this player is reeling.
var _reeling: Cable = null


func primary(target: InteractPoint) -> void:
	if not handles_point(target):
		return
	if crew.mission.toolkit.cable_at(target):
		crew.start_hold("primary", "reel", target, 1.0)
	elif target.kind == "hook":
		pending_hook = target
		crew.toast("Hook set on %s — now LMB an anchor point" % target.describe())
	elif pending_hook:
		crew.mission.send("winch_attach", crew.path_to(pending_hook), crew.path_to(target))
		pending_hook = null
	else:
		crew.toast("Pick a hook on cargo or the gate first")


func secondary(target: InteractPoint) -> void:
	if target and crew.mission.toolkit.cable_at(target):
		crew.start_hold("secondary", "reel", target, -1.0)
	elif pending_hook:
		pending_hook = null
		crew.toast("Hook selection cleared")


func deselected() -> void:
	pending_hook = null


func prompt(target: InteractPoint) -> String:
	var what := target.describe()
	if crew.mission.toolkit.cable_at(target):
		return "%s · hold LMB reel in · hold RMB pay out · [R] detach" % what
	if target.kind == "hook":
		return "%s · LMB select hook" % what
	if pending_hook:
		return "%s · LMB attach cable from %s" % [what, pending_hook.describe()]
	return "%s anchor · select a hook first" % what


func host_start(path: String, v: Vector3, _f: float) -> void:
	_reeling = crew.mission.toolkit.cable_at(crew.mission.get_node_or_null(path))
	if _reeling:
		_reeling.reel = int(signf(v.x))


func host_stop() -> void:
	if _reeling:
		_reeling.reel = 0
		_reeling = null


func _physics_process(_delta: float) -> void:
	if _reeling and not _reeling.active:
		_reeling = null


func _exit_tree() -> void:
	host_stop()
