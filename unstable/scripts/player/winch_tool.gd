class_name WinchTool
extends CrewTool
## Industrial winch: no anchor points, hook it anywhere. LMB a surface (a
## crate's corner, the gate, a column, a wall), then LMB a second surface to
## run a cable between them. Where you hook it matters: off-centre pulls tip
## and spin things, and hooking a support's structure strains that support.
## Hold LMB or RMB on a cable end to reel in or out. [R] on an end detaches it.

## Owner: first end picked, waiting for the second ({path, local}).
var pending_path := ""
var pending_local := Vector3.ZERO
var has_pending := false
## Host: the cable this player is reeling.
var _reeling: Cable = null

@onready var marker: MeshInstance3D = $PendingMarker


func primary(target: InteractPoint) -> void:
	if target and crew.mission.toolkit.cable_at(target):
		crew.start_hold("primary", "reel", target, 1.0)
		return
	var hit := _surface()
	if hit.is_empty():
		return
	if not has_pending:
		pending_path = hit.path
		pending_local = hit.local
		has_pending = true
		crew.toast("Cable hooked to %s. Now LMB where the other end goes." % hit.name)
	else:
		crew.mission.send("winch_attach", pending_path, hit.path, pending_local, 0.0, hit.local)
		has_pending = false


func secondary(target: InteractPoint) -> void:
	if target and crew.mission.toolkit.cable_at(target):
		crew.start_hold("secondary", "reel", target, -1.0)
	elif has_pending:
		has_pending = false
		crew.toast("Cable unhooked")


func hold_kinds() -> PackedStringArray:
	return ["reel"]


func deselected() -> void:
	has_pending = false


func prompt(_target: InteractPoint) -> String:
	return "Cable end · hold LMB reel in · hold RMB pay out · [R] detach"


func surface_prompt() -> String:
	var hit := _surface()
	if hit.is_empty():
		return "RMB unhook cable" if has_pending else ""
	if has_pending:
		var d := pending_position().distance_to(hit.world)
		return "LMB run cable to %s (%.1f m) · RMB unhook" % [hit.name, d]
	return "LMB hook winch cable to %s" % hit.name


## Owner: where the pending end currently is in the world.
func pending_position() -> Vector3:
	if pending_path == "":
		return pending_local
	var n := crew.mission.get_node_or_null(pending_path) as Node3D
	return n.to_global(pending_local) if n else pending_local


## Owner: the surface under the crosshair as {path, local, world, name}.
## Bodies (props, gate, columns) store a body-local point so the end rides
## with them; static geometry stores a world point and an empty path.
func _surface() -> Dictionary:
	var ray := crew.grab_ray
	if not ray.is_colliding():
		return {}
	var col := ray.get_collider() as Node3D
	var p := ray.get_collision_point()
	if col is RigidBody3D:
		var nm: String = col.display_name if "display_name" in col else "it"
		return {"path": crew.path_to(col), "local": col.to_local(p), "world": p, "name": nm}
	return {"path": "", "local": p, "world": p, "name": "the structure"}


func _process(_delta: float) -> void:
	marker.visible = has_pending and crew != null and crew.is_multiplayer_authority()
	if marker.visible:
		marker.global_position = pending_position()


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
