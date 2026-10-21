class_name Hands
extends Node
## Hands-on physics. Owner side:
##   [E]       grab or let go of the aimed Prop (at the exact point you aimed)
##   LMB       throw what you're carrying
##   [R]       turn it: free → upright → flat (stand a brace post up, lay a beam down)
## Host side: a capped spring pulls the grab point toward a spot in front of
## your face. Light props get carried. Heavy props only get dragged: a 300 kg
## reactor core needs two people, or the winch. Grab a long object by its end
## and it swings.

enum Align { FREE, UPRIGHT, FLAT }
const ALIGN_NAMES := ["free", "upright", "flat"]

## Max distance to start a grab.
@export var reach := 4.0
## Max force one crew member applies (N).
@export var grab_force := 950.0
@export var stiffness := 60.0
@export var damping := 12.0
## Grab breaks when the prop is this far from where the player holds it.
@export var break_distance := 3.0
## Max throw speed (m/s); heavier things fly slower.
@export var throw_speed := 10.0
## Impulse budget for a throw (N·s), shared by speed and mass.
@export var throw_impulse := 380.0
## Torque strength used to turn held objects upright or flat.
@export var align_strength := 40.0

## Owner: what we asked the host to hold, and how we want it turned.
var holding: Prop = null
var align: int = Align.FREE
var crew: CrewMember
# Host-side grab state.
var _prop: Prop = null
var _offset := Vector3.ZERO
var _distance := 2.0
var _align: int = Align.FREE


func _ready() -> void:
	crew = get_parent() as CrewMember


## Can this player lift `p` off the ground, or only drag it?
func can_lift(p: Prop) -> bool:
	return p.mass * 9.8 <= grab_force * 0.6


## Owner: grab `p` at world point `at`, `dist` metres from the camera.
func grab(p: Prop, at: Vector3, dist: float) -> void:
	if not p.is_grabbable() or dist > reach:
		return
	holding = p
	align = Align.FREE
	crew.mission.send("hold", "grab", crew.path_to(p), p.to_local(at), clampf(dist, 1.3, 3.0))


## Owner: let go.
func release() -> void:
	holding = null
	crew.mission.send("hold", "")


## Owner: throw what we're carrying (light things only).
func throw() -> void:
	if holding == null:
		return
	if not can_lift(holding):
		crew.toast("Too heavy to throw")
		return
	holding = null
	crew.mission.send("throw")


## Owner: cycle free → upright → flat.
func cycle_align() -> void:
	align = (align + 1) % 3
	crew.mission.send("align", "", "", Vector3.ZERO, align)
	crew.toast("Holding it %s" % ALIGN_NAMES[align])


## Owner: the host dropped our grab.
func on_dropped(msg: String) -> void:
	holding = null
	if msg != "":
		crew.toast(msg)


func prompt() -> String:
	var t := "[E] let go of %s · [R] turn (%s)" % [holding.display_name, ALIGN_NAMES[align]]
	if can_lift(holding):
		t += " · LMB throw"
	if holding.fragility > 0.0:
		t += "\nFragile: look down before letting go to set it down gently"
	return t


func host_start(path: String, offset: Vector3, distance: float) -> void:
	_prop = crew.mission.get_node_or_null(path) as Prop
	_offset = offset
	_distance = distance
	_align = Align.FREE


func host_stop() -> void:
	_prop = null


func host_align(mode: int) -> void:
	_align = mode


## Host: fling the held prop along the player's aim.
func host_throw() -> void:
	if _prop == null or not can_lift(_prop):
		return
	var p := _prop
	host_stop()
	var dir := -crew.head.global_basis.z
	var speed := minf(throw_speed, throw_impulse / p.mass)
	p.sleeping = false
	p.linear_velocity = crew.velocity * 0.5 + (dir + Vector3.UP * 0.15).normalized() * speed


func _physics_process(_delta: float) -> void:
	if _prop == null:
		return
	if not is_instance_valid(_prop) or _prop.freeze:
		_drop("")
		return
	var target := crew.head.global_position - crew.head.global_basis.z * _distance
	# With the object turned, hold it by its centre so it doesn't swing around.
	var gp := _prop.to_global(_offset if _align == Align.FREE else Vector3.ZERO)
	if gp.distance_to(target) > break_distance + (1.0 if _align != Align.FREE else 0.0):
		_drop("Lost your grip on %s" % _prop.display_name)
		return
	var force := ((target - gp) * stiffness - _prop.point_velocity(gp) * damping) * _prop.mass
	if can_lift(_prop):
		force += Vector3.UP * _prop.mass * 9.8
	else:
		force.y = minf(force.y, 0.0)
	force = force.limit_length(grab_force)
	_prop.sleeping = false
	_prop.apply_force(force, gp - _prop.global_position)
	_prop.apply_torque(-_prop.angular_velocity * _prop.mass * 0.5)
	if _align != Align.FREE:
		var want := Vector3.UP if _align == Align.UPRIGHT else crew.head.global_basis.x
		var up := _prop.global_basis.y
		# Pick whichever end is closer so "flat" doesn't flip it end over end.
		if _align == Align.FLAT and up.dot(want) < 0.0:
			want = -want
		var torque := up.cross(want) * align_strength * _prop.mass - _prop.angular_velocity * _prop.mass * 2.0
		_prop.apply_torque(torque.limit_length(grab_force * 1.5))


func _drop(msg: String) -> void:
	_prop = null
	crew.mission.incident_log.release_grab(crew.get_multiplayer_authority(), msg)
