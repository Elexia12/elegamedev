class_name Gate
extends RigidBody3D
## Heavy sliding gate: a real 300 kg rigid body locked to vertical travel. It
## starts JAMMED (frozen) and breaks free with a lurch once the lift on it
## (winch cables + hydraulic jack) beats its weight plus `jam_force`. One
## winch alone can't do that; two can, and so can a winch plus jack pressure.
## Once free it slides under real forces. It falls on whatever is underneath
## it: crates, the core, a brace post, a crew member.
## frame_failed() is wired to the gate frame Support's `failed` signal.

@export var display_name := "Reactor gate"
@export var max_height := 3.8
## Extra lift needed beyond its weight to unjam it (N).
@export var jam_force := 900.0
## Jack force at 100% pressure with its valve fully open (N).
@export var jack_max_force := 4000.0
@export var jack_valve: Valve
@export var pressure_network: PressureNetwork
## Network pressure spent per metre the jack lifts the gate.
@export var jack_pressure_cost := 5.0
## How fast a resting gate wears out the brace under it (integrity/s at full weight).
@export var brace_wear := 1.2

var jammed := true
var jack_enabled := true
var mission: Mission
var _base_y := 0.0
var _pull := Vector3.ZERO
var _fall_speed := 0.0
var _net_y := 0.0

@onready var jack_housing: Node3D = $JackHousing
@onready var jack_rod: Node3D = $JackRod
@onready var label: Label3D = $Label


func _ready() -> void:
	add_to_group("net")
	mission = Mission.of(self)
	_base_y = global_position.y
	_net_y = _base_y
	# Cables (priority 0) report their pull before the gate reads it.
	process_physics_priority = 10
	for n in [jack_housing, jack_rod, label]:
		var t: Transform3D = n.global_transform
		n.top_level = true
		n.global_transform = t
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC if not multiplayer.is_server() else RigidBody3D.FREEZE_MODE_STATIC
	freeze = true
	if multiplayer.is_server():
		contact_monitor = true
		max_contacts_reported = 6


func height() -> float:
	return global_position.y - _base_y


## Called by cables attached to the gate (host).
func register_pull(force: Vector3) -> void:
	_pull += force


func jack_force() -> float:
	if not jack_enabled or jack_valve == null or pressure_network == null:
		return 0.0
	return jack_valve.opening * pressure_network.pressure / 100.0 * jack_max_force


func frame_failed() -> void:
	if jack_enabled:
		jack_enabled = false
		mission.incident_log.incident("Gate hydraulics severed")


func _physics_process(delta: float) -> void:
	if mission and multiplayer.is_server() and mission.running():
		_simulate(delta)
	elif not multiplayer.is_server():
		global_position.y = lerpf(global_position.y, _net_y, 1.0 - exp(-18.0 * delta))
	_pull = Vector3.ZERO
	var rod := 0.2 + height()
	jack_rod.scale.y = rod
	jack_rod.global_position.y = _base_y + 1.8 + rod / 2.0
	label.text = "%s\n%s" % [display_name.to_upper(), "JAMMED" if jammed else "%.1f m" % height()]
	if not jack_enabled:
		label.text += "\nJACK OFFLINE"


func _simulate(delta: float) -> void:
	var weight := mass * 9.8
	var jack := jack_force()
	if jammed:
		if _pull.y + jack > weight + jam_force:
			jammed = false
			freeze = false
			apply_central_impulse(Vector3.UP * mass * 0.8)
			mission.incident_log.incident("%s broke free" % display_name)
			mission.tremors.jolt(0.4)
		return
	if jack > 0.0:
		apply_central_force(Vector3.UP * jack)
		if linear_velocity.y > 0.0:
			var share := jack / maxf(jack + maxf(_pull.y, 0.0), 1.0)
			pressure_network.spend(share * linear_velocity.y * delta * jack_pressure_cost)

	var vy := linear_velocity.y
	for body in get_colliding_bodies():
		if body is CrewMember and vy < -1.0:
			# Pinned under a falling gate: shove them out, hard.
			var out: Vector3 = (body.global_position - global_position) * Vector3(0, 0, 1)
			body.knock(out.normalized() * 6.0 + Vector3.UP, 2.5)
		elif body is Brace and absf(vy) < 0.05:
			var unsupported := weight - jack - maxf(_pull.y, 0.0)
			if unsupported > 0.0:
				body.apply_load(unsupported / weight * brace_wear * delta)

	if _fall_speed < -3.0 and absf(vy) < 0.5:
		mission.incident_log.incident("%s slammed down" % display_name)
		mission.tremors.jolt(0.5)
	_fall_speed = vy


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	# Rails: travel only between closed and fully open.
	var t := state.transform
	var lo := _base_y
	var hi := _base_y + max_height
	if t.origin.y < lo:
		t.origin.y = lo
		state.linear_velocity.y = maxf(state.linear_velocity.y, 0.0)
	elif t.origin.y > hi:
		t.origin.y = hi
		state.linear_velocity.y = minf(state.linear_velocity.y, 0.0)
	state.transform = t


func net_get() -> Array:
	return [global_position.y, jammed, jack_enabled]


func net_set(s: Array) -> void:
	_net_y = s[0]
	jammed = s[1]
	jack_enabled = s[2]
