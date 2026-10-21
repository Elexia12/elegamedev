class_name Trolley
extends Prop
## Platform trolley. [E] takes the handle (up to two crew), [E] again lets go.
## While you hold it you just walk: the handle is pushed to where you are, so
## walking pushes it and turning your body swings the handle and steers it.
##
## A rolling approximation rather than simulated wheels:
##   - the body rests on frictionless wheel spheres
##   - the fixed wheels at the far end (FrontAxle) grip sideways, up to
##     `skid_friction`, so a hard turn with a heavy load skids
##   - the casters at the handle end swivel freely
##   - rolling resistance is low and constant, so a loaded trolley carries
##     its momentum and coasts a little after you let go
## Cargo on the deck (CargoArea) is held by deck friction only: brake, ram or
## turn harder than `deck_friction` × g and it slides off. The wheels spin and
## the casters swivel to match (visual, every peer).

@export_group("Pushing")
## Most force one crew member puts into the handle (N).
@export var push_force := 1100.0
## Handle spring toward the pusher (N per m) and damping (N per m/s).
@export var push_stiffness := 2500.0
@export var push_damping := 700.0
## Where the handle sits in front of the pusher (m), and how far it can get
## from there before they lose it.
@export var handle_reach := 0.8
@export var release_distance := 1.6
@export var max_pushers := 2
@export_group("Wheels")
## Sideways grip of the fixed axle (1/s) and the skid limit (× load on it).
@export var axle_grip := 30.0
@export var skid_friction := 0.9
## Rolling resistance (× weight) and air/bearing drag (1/s).
@export var rolling_resistance := 0.06
@export var drag := 0.1
@export var wheel_radius := 0.12
@export_group("Cargo")
## Friction coefficient between the deck and cargo.
@export var deck_friction := 0.45

## Peer ids holding the handle (replicated).
var pushers: Array = []
var _pusher_last := {}
var _spin := 0.0
var _caster_yaw := 0.0
var _last_pos := Vector3.ZERO

@onready var cargo_area: Area3D = $CargoArea
@onready var front_axle: Marker3D = $FrontAxle
@onready var handle_point: Marker3D = $HandlePoint
@onready var front_wheels: Array[Node3D] = [$Wheels/FrontLeft, $Wheels/FrontRight]
@onready var casters: Array[Node3D] = [$Wheels/CasterLeft, $Wheels/CasterRight]


func _ready() -> void:
	super._ready()
	add_to_group("pushables")
	_last_pos = global_position


func cargo() -> Array[RigidBody3D]:
	var out: Array[RigidBody3D] = []
	for b in cargo_area.get_overlapping_bodies():
		if b is RigidBody3D and b != self and not b.freeze:
			out.append(b)
	return out


func cargo_mass() -> float:
	var m := 0.0
	for b in cargo():
		m += b.mass
	return m


## You push it by the handle, you don't pick it up.
func is_grabbable() -> bool:
	return false


func is_pushed_by(crew: CrewMember) -> bool:
	return crew.get_multiplayer_authority() in pushers


## Owner: how much a crew member slows down while pushing (walk 4.5 m/s ->
## ~2.2 m/s empty, ~1.6 m/s with the motor on).
func push_speed_factor() -> float:
	return 0.5 if cargo_mass() < 50.0 else 0.35


## The point on the handle this crew member holds (two pushers share it).
func handle_for(crew: CrewMember) -> Vector3:
	var i := pushers.find(crew.get_multiplayer_authority())
	var spread := 0.0 if pushers.size() < 2 else 0.3
	return handle_point.global_position + global_basis.z * (spread if i <= 0 else -spread)


func use_prompt(crew: CrewMember) -> String:
	if is_pushed_by(crew):
		return "[E] let go of the trolley"
	if pushers.size() >= max_pushers:
		return "Two people are already pushing the trolley"
	return "[E] push the trolley (walk to push, turn to steer)"


## [E]: take the handle, or let go of it.
func use(player: CrewMember, _target: Node) -> String:
	var id := player.get_multiplayer_authority()
	if id in pushers:
		pushers.erase(id)
	elif pushers.size() < max_pushers:
		pushers.append(id)
		_pusher_last[id] = player.global_position
	return ""


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if mission == null or not multiplayer.is_server() or freeze:
		return
	var total := mass + cargo_mass()
	_push(delta)
	_wheels(total)
	# Deck friction on cargo, and its reaction on the trolley.
	for b in cargo():
		var rel := (b.linear_velocity - point_velocity(b.global_position)) * Vector3(1, 0, 1)
		var f := (-rel * b.mass * 10.0).limit_length(deck_friction * b.mass * 9.8)
		b.apply_central_force(f)
		apply_force(-f, b.global_position - global_position)


## Host: each pusher drives the handle toward a spot just in front of them.
func _push(delta: float) -> void:
	for i in range(pushers.size() - 1, -1, -1):
		var id: int = pushers[i]
		var c := mission.crew.member(id)
		if c == null or c.knocked():
			pushers.remove_at(i)
			continue
		var fwd := (-c.global_basis.z * Vector3(1, 0, 1)).normalized()
		var spot := c.global_position + fwd * handle_reach
		var at := handle_for(c)
		var err := (spot - at) * Vector3(1, 0, 1)
		if err.length() > release_distance:
			pushers.remove_at(i)
			mission.incident_log.tell(id, "You lost hold of the trolley")
			continue
		var pusher_v: Vector3 = (c.global_position - _pusher_last.get(id, c.global_position)) / delta
		_pusher_last[id] = c.global_position
		var rel := (pusher_v - point_velocity(at)) * Vector3(1, 0, 1)
		var f := (err * push_stiffness + rel * push_damping).limit_length(push_force)
		sleeping = false
		# Purely horizontal, at the height of the centre of mass: no pitching.
		apply_force(f, Vector3(at.x, global_position.y, at.z) - global_position)


## Host: fixed-axle grip, rolling resistance.
func _wheels(total: float) -> void:
	var weight := total * 9.8
	var axle := front_axle.global_position
	var axle_at := Vector3(axle.x, global_position.y, axle.z)
	var side := global_basis.z
	var slip := point_velocity(axle_at).dot(side)
	var grip := clampf(-slip * total * axle_grip * 0.5, -skid_friction * weight * 0.5, skid_friction * weight * 0.5)
	apply_force(side * grip, axle_at - global_position)
	var v := linear_velocity * Vector3(1, 0, 1)
	var speed := v.length()
	if speed > 0.001:
		# Constant rolling resistance, faded in near standstill so it doesn't jitter.
		apply_central_force(-v / speed * rolling_resistance * weight * clampf(speed / 0.1, 0.0, 1.0))
	apply_central_force(-v * total * drag)


func _process(delta: float) -> void:
	super._process(delta)
	# Wheels spin with the rolling speed; the casters swing to trail the motion.
	var v := linear_velocity if multiplayer.is_server() else (global_position - _last_pos) / maxf(delta, 0.0001)
	_last_pos = global_position
	var forward := global_basis.x
	_spin += v.dot(forward) * delta / wheel_radius
	for w in front_wheels:
		w.rotation.z = -_spin
	var rear := casters[0].global_position
	var local_v := global_basis.inverse() * (v + angular_velocity.cross(rear - global_position) if multiplayer.is_server() else v)
	var flat := Vector2(local_v.x, local_v.z)
	if flat.length() > 0.15:
		_caster_yaw = lerp_angle(_caster_yaw, atan2(-flat.y, flat.x), 1.0 - exp(-8.0 * delta))
	for c in casters:
		c.rotation.y = _caster_yaw
		c.get_child(0).rotation.z = -_spin


func _label_text() -> String:
	var names: Array[String] = []
	for b in cargo_area.get_overlapping_bodies():
		if b is Prop and b != self and b.is_salvage():
			names.append(b.display_name)
	return "TROLLEY" + ("\n" + ", ".join(names) if not names.is_empty() else "")


func net_get() -> Array:
	return super.net_get() + [pushers]


func net_set(s: Array) -> void:
	super.net_set(s)
	pushers = s[s.size() - 1]
