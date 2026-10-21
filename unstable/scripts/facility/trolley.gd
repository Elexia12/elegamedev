class_name Trolley
extends Prop
## Platform trolley that handles like a shopping cart. [E] takes the handle
## (up to two crew), [E] again lets go. While you hold it, it's held rigidly
## in front of you: walk and it goes where you walk, turn and it turns with
## you. Your hands only have so much in them (`push_force`, `push_torque`):
## an empty trolley follows at once, a loaded one is slow to get going, slow to
## turn and slow to stop, and it holds you back (CrewMember._tether_to).
##
## A rolling approximation rather than simulated wheels:
##   - the body rests on frictionless wheel spheres
##   - the fixed wheels at the handle end (FixedAxle) grip sideways, up to
##     `skid_friction`, so a hard turn with a heavy load skids
##   - the casters at the far end swivel freely, so it pivots near your hands
##   - rolling resistance is low and constant: let go and it rolls on a little
## Cargo resting on the deck (CargoArea) sticks to it (static friction: a
## joint, so the two move as one with no contact jitter). Brake, ram or corner
## harder than `deck_friction` × g and it comes unstuck and slides; it sticks
## again once it settles. The hoist or a crew member lifting it unsticks it. The wheels spin and
## the casters swivel to match (visual, every peer).

@export_group("Pushing")
## Most force (N) and twisting torque (N·m) one crew member's hands can apply.
@export var push_force := 1100.0
@export var push_torque := 1400.0
## How stiffly the trolley is held in your hands (1/s): position and turning.
@export var hold_stiffness := 12.0
@export var turn_stiffness := 14.0
## Where the handle sits in front of the pusher (m), and how far the trolley
## can get from where you're holding it before you lose it.
@export var handle_reach := 0.8
@export var release_distance := 1.6
@export var max_pushers := 2
@export_group("Wheels")
## Sideways grip of the fixed axle (1/s) and the skid limit (× load on it).
@export var axle_grip := 20.0
@export var skid_friction := 0.9
## Casters swivel, but resist a sudden sideways shove a little until they do
## (1/s, and the limit × load on them).
@export var caster_grip := 4.0
@export var caster_friction := 0.25
## Rolling resistance (× weight) and air/bearing drag (1/s).
@export var rolling_resistance := 0.06
@export var drag := 0.1
@export var wheel_radius := 0.12
@export_group("Cargo")
## Friction coefficient between the deck and cargo.
@export var deck_friction := 0.85

## Peer ids holding the handle (replicated).
var pushers: Array = []
var _pusher_last := {}
var _spin := 0.0
var _caster_yaw := 0.0
var _last_pos := Vector3.ZERO
## Host: cargo stuck to the deck -> its joint; the deck's (smoothed) acceleration.
var _joints := {}
var _deck_last_v := Vector3.ZERO
var _deck_accel := Vector3.ZERO
## Host: stuck cargo's velocity last step (what it would keep if it broke loose).
var _cargo_last_v := {}

@onready var cargo_area: Area3D = $CargoArea
@onready var deck: CollisionShape3D = $Deck
@onready var fixed_axle: Marker3D = $FixedAxle
@onready var handle_point: Marker3D = $HandlePoint
@onready var fixed_wheels: Array[Node3D] = [$Wheels/FixedLeft, $Wheels/FixedRight]
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
	return "[E] push the trolley"


## Aiming at the Grip point (the generous aim zone around the thin handle).
func prompt_for(crew: CrewMember, _target: Node) -> String:
	return use_prompt(crew)


## [E]: take the handle, or let go of it.
func use(player: CrewMember, _target: Node) -> String:
	var id := player.get_multiplayer_authority()
	if id in pushers:
		pushers.erase(id)
	elif pushers.size() < max_pushers:
		pushers.append(id)
		_pusher_last[id] = [player.global_position, player.global_rotation.y]
	return ""


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if mission == null or not multiplayer.is_server() or freeze:
		return
	_cargo(delta)
	var total := mass + cargo_mass()
	_push(delta)
	_wheels(total)


## Host: cargo on the deck either STICKS (static friction) or SLIDES.
## Stuck cargo is locked to the trolley with a joint: they move and turn as
## one rigid body, with no contact jitter between them. It comes unstuck when
## friction couldn't hold it any more (the deck accelerating harder than
## `deck_friction` × g: a ram, a dead stop, a hard corner) or when something
## lifts it (the hoist, someone's hands). Sliding cargo gets kinetic friction
## from the deck until it settles and sticks again.
func _cargo(delta: float) -> void:
	# The deck's horizontal acceleration (smoothed: one-frame spikes are noise).
	var accel := (linear_velocity - _deck_last_v) / delta * Vector3(1, 0, 1)
	_deck_last_v = linear_velocity
	_deck_accel = _deck_accel.lerp(accel, 0.35)
	# A crash is not noise: a huge one-frame change counts at once.
	var jolt := accel.length() > deck_friction * 9.8 * 3.0
	var bodies := cargo()
	for b in _joints.keys():
		if not is_instance_valid(b) or b.freeze or not b in bodies or _lifted(b):
			release_cargo(b)
	var deck_y := deck.global_position.y + 0.05
	var hold := deck_friction * 9.8
	for b in bodies:
		var on_deck := Vector3(b.global_position.x, deck_y, b.global_position.z)
		var r := on_deck - global_position
		if _joints.has(b):
			# What friction would have to supply to keep it riding along.
			var need := (accel if jolt else _deck_accel) + angular_velocity.cross(angular_velocity.cross(r)) * Vector3(1, 0, 1)
			if need.length() <= hold:
				_cargo_last_v[b] = b.linear_velocity
				continue
			release_cargo(b)
			# The joint already dragged it along with the trolley this step;
			# friction could only have taken `hold` × delta off its speed, so
			# give it back the rest of its momentum: it slides on.
			var before: Vector3 = _cargo_last_v.get(b, b.linear_velocity)
			var change := (b.linear_velocity - before) * Vector3(1, 0, 1)
			b.linear_velocity -= change - change.limit_length(hold * delta)
		var rel := (b.linear_velocity - point_velocity(on_deck)) * Vector3(1, 0, 1)
		var spin := b.angular_velocity.y - angular_velocity.y
		if rel.length() < 0.12 and absf(spin) < 0.3 and b.get_contact_count() > 0 and not _lifted(b):
			_stick(b)
			continue
		# Sliding: kinetic friction, measured and applied where it meets the deck.
		var reduced := b.mass * mass / (b.mass + mass)
		var f := (-rel * reduced * 20.0).limit_length(deck_friction * b.mass * 9.8)
		b.apply_force(f, on_deck - b.global_position)
		apply_force(-f, on_deck - global_position)


## Is something lifting this cargo off the deck (the hoist, a crew member)?
func _lifted(b: Prop) -> bool:
	for h in mission.machines():
		if h is OverheadHoist and h.load_prop() == b and h.tension > b.mass * 9.8 * 0.15:
			return true
	for c in mission.crew.members():
		if c.hands._prop == b:
			return true
	return false


func _stick(b: Prop) -> void:
	var j := Generic6DOFJoint3D.new()
	j.name = "Grip_%s" % b.name
	add_child(j)
	j.global_position = b.global_position
	# Every axis is locked by default (limits on, zero range), and the two
	# bodies stop colliding with each other while joined.
	j.node_a = j.get_path_to(self)
	j.node_b = j.get_path_to(b)
	_joints[b] = j


## Host: let go of a piece of cargo (it slides, it's lifted, it's handed over).
func release_cargo(b: Node) -> void:
	var j: Node = _joints.get(b)
	_joints.erase(b)
	_cargo_last_v.erase(b)
	if is_instance_valid(j):
		j.free()


## Mass and yaw inertia of the trolley plus everything stuck to it: what the
## pushers and the wheels actually move (kg, kg·m²).
func _rigid_mass() -> float:
	var m := mass
	for b: Node in _joints:
		if is_instance_valid(b):
			m += (b as Prop).mass
	return m


func _rigid_yaw_inertia() -> float:
	var inertia := _own_yaw_inertia()
	for node: Node in _joints:
		if not is_instance_valid(node):
			continue
		var b := node as Prop
		var inv := PhysicsServer3D.body_get_direct_state(b.get_rid()).inverse_inertia
		var r := (b.global_position - global_position) * Vector3(1, 0, 1)
		inertia += (1.0 / inv.y if inv.y > 0.0 else 0.0) + b.mass * r.length_squared()
	return inertia


## Host: hold the trolley where (and how) the pushers hold it: handle just in
## front of them, pointing the way they face. A capped spring-damper on its
## position and on its heading, matched to how they're moving.
func _push(delta: float) -> void:
	if pushers.is_empty():
		return
	var n := float(pushers.size())
	# Gains are sized for what actually moves: the trolley plus any cargo stuck
	# to it (a heavy load answers more slowly; the hands' strength is capped by
	# push_force / push_torque).
	var rigid_mass := _rigid_mass()
	var rigid_inertia := _rigid_yaw_inertia()
	for i in range(pushers.size() - 1, -1, -1):
		var id: int = pushers[i]
		var c := mission.crew.member(id)
		if c == null or c.knocked():
			pushers.remove_at(i)
			continue
		var yaw := c.global_rotation.y + PI / 2.0
		var fwd := Vector3(cos(yaw), 0.0, -sin(yaw))
		# Where this trolley's origin should be for the handle to sit in this
		# pusher's hands, facing their way.
		var held := Basis(Vector3.UP, yaw)
		var grip_offset := handle_point.position + Vector3(0, 0, 0.0 if n < 2 else (0.3 if i == 0 else -0.3))
		var want := c.global_position + fwd * handle_reach - held * Vector3(grip_offset.x, 0.0, grip_offset.z)
		var err := (want - global_position) * Vector3(1, 0, 1)
		if err.length() > release_distance:
			pushers.remove_at(i)
			mission.incident_log.tell(id, "You lost hold of the trolley")
			continue
		var last: Array = _pusher_last.get(id, [c.global_position, c.global_rotation.y])
		var pusher_v: Vector3 = (c.global_position - last[0]) / delta * Vector3(1, 0, 1)
		var pusher_w := angle_difference(last[1], c.global_rotation.y) / delta
		_pusher_last[id] = [c.global_position, c.global_rotation.y]
		# Position: critically damped, as accelerations, capped by the hands.
		# Only along the trolley's length: like a cart, you can push it and
		# turn it, not shove it sideways (you line up behind it instead).
		var k := hold_stiffness
		var along := global_basis.x
		var accel := (err * k * k + (pusher_v - linear_velocity * Vector3(1, 0, 1)) * 2.0 * k).dot(along)
		var f := (along * accel * rigid_mass / n).limit_length(push_force)
		# Heading: same on the yaw.
		var heading := heading()
		var yaw_err := angle_difference(heading, yaw)
		var kt := turn_stiffness
		var turn := (yaw_err * kt * kt + (pusher_w - angular_velocity.y) * 2.0 * kt) * rigid_inertia / n
		sleeping = false
		apply_central_force(f)
		apply_torque(Vector3.UP * clampf(turn, -push_torque, push_torque))


## The way the trolley points (its +X axis), as a yaw angle.
func heading() -> float:
	return atan2(-global_basis.x.z, global_basis.x.x)


## Yaw inertia of the trolley body (kg·m²), from the physics engine.
func _own_yaw_inertia() -> float:
	var inv := PhysicsServer3D.body_get_direct_state(get_rid()).inverse_inertia
	return 1.0 / inv.y if inv.y > 0.0 else mass * (1.8 * 1.8 + 1.1 * 1.1) / 12.0


## Host: fixed-axle grip, caster drag, rolling resistance.
## Their gains use what actually moves with the trolley (its body plus cargo
## stuck to it, not cargo sliding loose on top), or they overshoot every
## physics step and the wheels jitter instead of gripping. How much grip
## there is (the clamp) scales with the whole load.
func _wheels(total: float) -> void:
	var weight := total * 9.8
	var rigid := _rigid_mass()
	var axle := fixed_axle.global_position
	var axle_at := Vector3(axle.x, global_position.y, axle.z)
	var side := global_basis.z
	var slip := point_velocity(axle_at).dot(side)
	var grip := clampf(-slip * rigid * axle_grip, -skid_friction * weight * 0.5, skid_friction * weight * 0.5)
	apply_force(side * grip, axle_at - global_position)
	# On the centreline at the caster end.
	var caster_at := global_position + global_basis.x * casters[0].position.x
	var caster_slip := point_velocity(caster_at).dot(side)
	# Swivel casters barely resist turning: sized by the trolley alone.
	var caster_force := clampf(-caster_slip * mass * caster_grip, -caster_friction * weight * 0.5, caster_friction * weight * 0.5)
	apply_force(side * caster_force, caster_at - global_position)
	var v := linear_velocity * Vector3(1, 0, 1)
	var speed := v.length()
	if speed > 0.001:
		# Constant rolling resistance, faded in near standstill so it doesn't jitter.
		apply_central_force(-v / speed * rolling_resistance * weight * clampf(speed / 0.15, 0.0, 1.0))
	apply_central_force(-v * total * drag)
	# Static friction: left alone and nearly still, it stays put instead of
	# creeping (half the slip per step, up to what the wheels can hold).
	if pushers.is_empty() and speed < 0.1:
		var hold := (-v * rigid * 0.5 * Engine.physics_ticks_per_second).limit_length(rolling_resistance * 3.0 * weight)
		apply_central_force(hold)
		apply_torque(Vector3.UP * -angular_velocity.y * _rigid_yaw_inertia() * 0.5 * Engine.physics_ticks_per_second)


func _process(delta: float) -> void:
	super._process(delta)
	# Wheels spin with the rolling speed; the casters swing to trail the motion.
	var v := linear_velocity if multiplayer.is_server() else (global_position - _last_pos) / maxf(delta, 0.0001)
	_last_pos = global_position
	_spin += v.dot(global_basis.x) * delta / wheel_radius
	for w in fixed_wheels:
		w.rotation.z = -_spin
	var at := casters[0].global_position
	var point_v := v + angular_velocity.cross(at - global_position) if multiplayer.is_server() else v
	var local_v := global_basis.inverse() * point_v
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
