class_name Hands
extends Node
## Grabbing. Owner: [E] toggles a grab on the aimed Prop. Host: pulls the grab
## point toward a spot in front of the player's face with a capped force.
## Light props get carried. Heavy props only get dragged: a 300 kg reactor core
## needs two people, or the winch.

## Max distance to start a grab.
@export var reach := 4.0
## Max force one crew member applies (N).
@export var grab_force := 950.0
@export var stiffness := 60.0
@export var damping := 12.0
## Grab breaks when the prop is this far from where the player holds it.
@export var break_distance := 3.0

## Owner: what we asked the host to hold.
var holding: Prop = null
var crew: CrewMember
# Host-side grab state.
var _prop: Prop = null
var _offset := Vector3.ZERO
var _distance := 2.0


func _ready() -> void:
	crew = get_parent() as CrewMember


## Can this player lift `p` off the ground, or only drag it?
func can_lift(p: Prop) -> bool:
	return p.mass * 9.8 <= grab_force * 0.6


## Owner: grab `p` at world point `at`, `dist` metres from the camera.
func grab(p: Prop, at: Vector3, dist: float) -> void:
	if not p.is_grabbable():
		crew.toast("%s is bolted in place" % p.display_name)
		return
	if dist > reach:
		return
	holding = p
	crew.mission.send("hold", "grab", crew.path_to(p), p.to_local(at), clampf(dist, 1.3, 3.0))


## Owner: let go.
func release() -> void:
	holding = null
	crew.mission.send("hold", "")


## Owner: the host dropped our grab.
func on_dropped(msg: String) -> void:
	holding = null
	if msg != "":
		crew.toast(msg)


func prompt() -> String:
	return "[E] let go of %s" % holding.display_name


func host_start(path: String, offset: Vector3, distance: float) -> void:
	_prop = crew.mission.get_node_or_null(path) as Prop
	_offset = offset
	_distance = distance


func host_stop() -> void:
	_prop = null


func _physics_process(_delta: float) -> void:
	if _prop == null:
		return
	if not is_instance_valid(_prop) or _prop.freeze:
		_drop("")
		return
	var target := crew.head.global_position - crew.head.global_basis.z * _distance
	var gp := _prop.to_global(_offset)
	if gp.distance_to(target) > break_distance:
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


func _drop(msg: String) -> void:
	_prop = null
	crew.mission.incident_log.release_grab(crew.get_multiplayer_authority(), msg)
