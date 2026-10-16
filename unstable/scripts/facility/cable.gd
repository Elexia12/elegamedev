class_name Cable
extends Node3D
## One winch cable slot (the level authors a fixed pool of these). The host
## simulates a one-sided spring between a hook and an anchor — cables only
## pull — with a motor that reels the rest length in or out. Everyone renders
## the line from the replicated endpoints; colour shows tension.

@export var stiffness := 6000.0
@export var damping := 900.0
## The motor stalls (stops reeling in) above this tension.
@export var stall_force := 3800.0
## Sustained tension above this snaps the cable.
@export var break_force := 5200.0
@export var break_time := 0.4
@export var reel_speed := 1.1
@export var max_length := 26.0

var active := false
## Mission-relative paths of the two InteractPoints.
var hook_path := ""
var anchor_path := ""
var rest := 0.0
var tension := 0.0
## +1 reeling in, -1 paying out, 0 holding.
var reel := 0
var mission: Mission
var _overload := 0.0
var _mat: StandardMaterial3D

@onready var line: MeshInstance3D = $Line


func _ready() -> void:
	add_to_group("net")
	add_to_group("cables")
	mission = Mission.of(self)
	_mat = StandardMaterial3D.new()
	_mat.emission_enabled = true
	line.material_override = _mat
	line.top_level = true
	line.visible = false


func hook() -> InteractPoint:
	return mission.get_node_or_null(hook_path) as InteractPoint if active else null


func anchor_point() -> InteractPoint:
	return mission.get_node_or_null(anchor_path) as InteractPoint if active else null


func uses(point_path: String) -> bool:
	return active and (hook_path == point_path or anchor_path == point_path)


func attach(h: InteractPoint, a: InteractPoint) -> void:
	active = true
	hook_path = str(mission.get_path_to(h))
	anchor_path = str(mission.get_path_to(a))
	rest = h.global_position.distance_to(a.global_position)
	tension = 0.0
	reel = 0
	_overload = 0.0


func detach() -> void:
	var a := anchor_point()
	if a and a.get_parent() is Anchor:
		a.get_parent().tension = 0.0
	active = false
	hook_path = ""
	anchor_path = ""
	tension = 0.0
	reel = 0


func _physics_process(delta: float) -> void:
	if active and multiplayer.is_server() and mission.running():
		_simulate(delta)


func _simulate(delta: float) -> void:
	var h := hook()
	var ap := anchor_point()
	var recv: Node = h.receiver() if h else null
	if recv == null or ap == null:
		detach()
		return
	var hp := h.global_position
	var d := ap.global_position - hp
	var dist := d.length()
	if dist > max_length + 2.0:
		mission.incident_log.incident("Cable on %s ripped loose" % recv.display_name)
		detach()
		return
	if dist < 0.01:
		return
	var dir := d / dist
	if reel > 0 and tension < stall_force:
		rest -= reel_speed * delta
	elif reel < 0:
		rest += reel_speed * delta
	rest = clampf(rest, 0.5, minf(max_length, dist + 1.5))
	var stretch := dist - rest
	tension = 0.0
	if stretch > 0.0:
		var pv: Vector3 = recv.point_velocity(hp)
		tension = maxf(0.0, stiffness * stretch - damping * pv.dot(dir))
		recv.add_cable_force(dir * tension, hp)
	var anchor := ap.get_parent() as Anchor
	if anchor:
		anchor.tension = tension
	if tension > break_force:
		_overload += delta
		if _overload > break_time:
			mission.incident_log.incident("Winch cable on %s SNAPPED" % recv.display_name)
			detach()
	else:
		_overload = maxf(0.0, _overload - delta)


func _process(_delta: float) -> void:
	var h := hook()
	var a := anchor_point()
	line.visible = h != null and a != null
	if not line.visible:
		return
	var p0 := h.global_position
	var p1 := a.global_position
	var axis := p1 - p0
	var length := axis.length()
	if length < 0.01:
		line.visible = false
		return
	var y := axis / length
	var x := y.cross(Vector3.UP if absf(y.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	line.global_transform = Transform3D(Basis(x, y * length, z), (p0 + p1) / 2.0)
	var load_ratio := clampf(tension / break_force, 0.0, 1.0)
	var c := Color(0.55, 0.5, 0.3) if tension <= 0.0 else Color(1.0, 0.85, 0.1).lerp(Color(1.0, 0.1, 0.05), load_ratio)
	_mat.albedo_color = c
	_mat.emission = c * (0.2 + load_ratio)


func net_get() -> Array:
	return [active, hook_path, anchor_path, rest, tension, reel]


func net_set(s: Array) -> void:
	active = s[0]
	hook_path = s[1]
	anchor_path = s[2]
	rest = s[3]
	tension = s[4]
	reel = s[5]
