class_name Cable
extends Node3D
## One winch cable (the Toolkit holds a fixed pool of these). A cable links any
## two points in the world. Each end is either on a body (stored in that body's
## local space, so it moves and rotates with it) or on static geometry (stored
## in world space). Off-centre pulls tip and spin things.
##
## The host simulates a one-sided spring (cables only pull). Force goes to both
## ends, so pulling two crates together moves both. A motor reels the rest
## length in or out. An end on a Support's column strains that support.
## Overloaded cables snap and whip anyone standing next to the line.
## The EndA/EndB children are what players aim at to reel or detach.

@export var stiffness := 6000.0
@export var damping := 900.0
## The motor stalls (stops reeling in) above this tension.
@export var stall_force := 3800.0
## Sustained tension above this snaps the cable.
@export var break_force := 5200.0
@export var break_time := 0.4
@export var reel_speed := 1.1
@export var max_length := 26.0
## Crew within this distance of the line when it snaps get whipped.
@export var whip_radius := 1.3

var active := false
## Per end: mission-relative path of the body ("" = static world) and the
## point in that body's local space (or world space when static).
var paths := ["", ""]
var locals := [Vector3.ZERO, Vector3.ZERO]
var rest := 0.0
var tension := 0.0
## +1 reeling in, -1 paying out, 0 holding.
var reel := 0
var mission: Mission
var _overload := 0.0
var _mat: StandardMaterial3D
var _flash := 0.0

@onready var line: MeshInstance3D = $Line
@onready var ends: Array[InteractPoint] = [$EndA, $EndB]


func _ready() -> void:
	add_to_group("net")
	add_to_group("cables")
	mission = Mission.of(self)
	_mat = StandardMaterial3D.new()
	_mat.emission_enabled = true
	line.material_override = _mat
	line.top_level = true
	for e in ends:
		e.top_level = true


## Node an end is attached to (a body or structure), or null for static world.
func end_node(i: int) -> Node3D:
	if paths[i] == "":
		return null
	return mission.get_node_or_null(paths[i]) as Node3D


func end_position(i: int) -> Vector3:
	var n := end_node(i)
	if n:
		return n.to_global(locals[i])
	return locals[i]


## Simulated body at an end, or null if it's static or frozen.
func end_body(i: int) -> RigidBody3D:
	var b := end_node(i) as RigidBody3D
	return b if b and not b.freeze else null


## Support whose structure an end is attached to (e.g. a column).
func end_support(i: int) -> Support:
	var n: Node = end_node(i)
	while n and n != mission:
		if n is Support:
			return n
		n = n.get_parent()
	return null


func describe_end(i: int) -> String:
	var n: Node = end_node(i)
	while n and n != mission:
		if "display_name" in n:
			return n.display_name
		n = n.get_parent()
	return "the structure"


## Host: rig the cable between two points ({path, local} per end).
func attach(path_a: String, local_a: Vector3, path_b: String, local_b: Vector3) -> void:
	active = true
	paths = [path_a, path_b]
	locals = [local_a, local_b]
	rest = end_position(0).distance_to(end_position(1))
	tension = 0.0
	reel = 0
	_overload = 0.0


func detach() -> void:
	active = false
	paths = ["", ""]
	tension = 0.0
	reel = 0


func _physics_process(delta: float) -> void:
	if active and multiplayer.is_server() and mission.running():
		_simulate(delta)


func _simulate(delta: float) -> void:
	for i in 2:
		if paths[i] != "" and end_node(i) == null:
			detach()
			return
	var p0 := end_position(0)
	var p1 := end_position(1)
	var d := p1 - p0
	var dist := d.length()
	if dist > max_length + 2.0:
		_snap("ripped loose")
		return
	if dist < 0.01:
		return
	var dir := d / dist
	if reel > 0 and tension < stall_force:
		rest -= reel_speed * delta
	elif reel < 0:
		rest += reel_speed * delta
	rest = clampf(rest, 0.4, minf(max_length, dist + 1.5))

	var b0 := end_body(0)
	var b1 := end_body(1)
	tension = 0.0
	var stretch := dist - rest
	if stretch > 0.0:
		# Positive when the ends are flying apart.
		var separating := (_point_velocity(b1, p1) - _point_velocity(b0, p0)).dot(dir)
		tension = maxf(0.0, stiffness * stretch + damping * separating)
		var f := dir * tension
		if b0:
			b0.sleeping = false
			b0.apply_force(f, p0 - b0.global_position)
		if b1:
			b1.sleeping = false
			b1.apply_force(-f, p1 - b1.global_position)
		for i in 2:
			var n := end_node(i)
			if n and n.has_method("register_pull"):
				n.register_pull(f if i == 0 else -f)

	if tension > break_force:
		_overload += delta
		if _overload > break_time:
			_snap("SNAPPED")
	else:
		_overload = maxf(0.0, _overload - delta)


func _point_velocity(b: RigidBody3D, p: Vector3) -> Vector3:
	if b == null:
		return Vector3.ZERO
	return b.linear_velocity + b.angular_velocity.cross(p - b.global_position)


## Host: break the cable, whipping crew near the line.
func _snap(how: String) -> void:
	var p0 := end_position(0)
	var p1 := end_position(1)
	mission.incident_log.incident("Winch cable %s (%s ↔ %s)" % [how, describe_end(0), describe_end(1)])
	for c in mission.crew.members():
		var near := Geometry3D.get_closest_point_to_segment(c.global_position + Vector3.UP, p0, p1)
		var off := c.global_position + Vector3.UP - near
		if off.length() < whip_radius:
			var push := off.normalized() if off.length() > 0.01 else Vector3.UP
			c.knock(push * 7.0 + Vector3.UP * 3.0, 0.8)
	mission.tremors.jolt(0.35)
	detach()
	_flash = 1.0


func _process(delta: float) -> void:
	for i in 2:
		ends[i].visible = active
		ends[i].active = active
		if active:
			ends[i].global_position = end_position(i)
	line.visible = active
	if not active:
		return
	var p0 := end_position(0)
	var p1 := end_position(1)
	var axis := p1 - p0
	var length := axis.length()
	if length < 0.01:
		line.visible = false
		return
	var y := axis / length
	var x := y.cross(Vector3.UP if absf(y.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	# A taut cable vibrates a little; a slack one droops (fake, visual only).
	var mid := (p0 + p1) / 2.0
	var load_ratio := clampf(tension / break_force, 0.0, 1.0)
	if tension <= 0.0:
		mid += Vector3.DOWN * clampf(rest - length, 0.0, 1.5) * 0.3
	elif load_ratio > 0.6:
		mid += x * randf_range(-0.02, 0.02) * load_ratio
	line.global_transform = Transform3D(Basis(x, y * length, z), mid)
	var c := Color(0.55, 0.5, 0.3) if tension <= 0.0 else Color(1.0, 0.85, 0.1).lerp(Color(1.0, 0.1, 0.05), load_ratio)
	_mat.albedo_color = c
	_mat.emission = c * (0.2 + load_ratio)
	_flash = maxf(0.0, _flash - delta)


func net_get() -> Array:
	return [active, paths[0], paths[1], locals[0], locals[1], rest, tension, reel]


func net_set(s: Array) -> void:
	active = s[0]
	paths = [s[1], s[2]]
	locals = [s[3], s[4]]
	rest = s[5]
	tension = s[6]
	reel = s[7]
