class_name Gate
extends Node3D
## Heavy, jammed sliding gate. Not a free rigid body: the host integrates one
## height value from cable pull, hydraulic jack force (from the pressure
## network), gravity and rail friction. Controlled, readable, cheap to sync.
## When its frame support fails, frame_failed() (wired to Support.failed in the
## level) cuts the jack.

@export var display_name := "Reactor gate"
@export var max_height := 3.8
@export var mass := 220.0
## Static friction of the bent rails (N). Forces below this don't move it.
@export var jam_force := 600.0
## Jack force at 100% pressure with its valve fully open (N).
@export var jack_max_force := 3600.0
@export var jack_valve: Valve
@export var pressure_network: PressureNetwork
## Network pressure spent per metre the jack lifts the gate.
@export var jack_pressure_cost := 5.0

var height := 0.0
var vel := 0.0
## Lowest height while a brace holds the gate (-1 = no brace).
var brace_min := -1.0
var jack_enabled := true
var mission: Mission
var _cable_force := 0.0

@onready var door: AnimatableBody3D = $Door
@onready var jack_rod: Node3D = $JackRod
@onready var socket: BraceSocket = $BraceSocket
@onready var label: Label3D = $Label


func _ready() -> void:
	add_to_group("net")
	mission = Mission.of(self)
	# Cables (priority 0) push their force in before the gate integrates.
	process_physics_priority = 10


func add_cable_force(force: Vector3, _at: Vector3) -> void:
	_cable_force += force.y


func point_velocity(_at: Vector3) -> Vector3:
	return Vector3(0.0, vel, 0.0)


func jack_force() -> float:
	if not jack_enabled or jack_valve == null or pressure_network == null:
		return 0.0
	return jack_valve.opening * pressure_network.pressure / 100.0 * jack_max_force


func frame_failed() -> void:
	if jack_enabled:
		jack_enabled = false
		mission.incident_log.incident("Gate hydraulics severed — the gate is coming down")


func _physics_process(delta: float) -> void:
	if mission and multiplayer.is_server() and mission.running():
		_simulate(delta)
	_cable_force = 0.0
	door.position.y = 2.0 + height
	var rod := 0.2 + height
	jack_rod.scale.y = rod
	jack_rod.position.y = 1.8 + rod / 2.0
	label.text = "%s\n%.1f m%s" % [display_name.to_upper(), height,
		"" if jack_enabled else "\nJACK OFFLINE"]


func _simulate(delta: float) -> void:
	var jack := jack_force()
	var net := _cable_force + jack - mass * 9.8
	var floor_h := maxf(0.0, brace_min)
	if brace_min >= 0.0 and height <= brace_min + 0.01 and net < 0.0:
		# Resting on the brace: it carries whatever the cable and jack don't.
		height = brace_min
		vel = 0.0
		socket.apply_load(-net / (mass * 9.8), delta)
		return
	if absf(vel) < 0.02 and absf(net) <= jam_force:
		vel = 0.0
		return
	var moving_dir := signf(vel) if absf(vel) >= 0.02 else signf(net)
	vel += (net - jam_force * 0.6 * moving_dir) / mass * delta
	vel = clampf(vel, -7.0, 2.0)
	var impact := vel
	height += vel * delta
	if vel > 0.0 and jack > 0.0:
		var share := jack / maxf(jack + maxf(_cable_force, 0.0), 1.0)
		pressure_network.spend(share * vel * delta * jack_pressure_cost)
	if height <= floor_h:
		height = floor_h
		vel = 0.0
		if impact < -2.0:
			if brace_min >= 0.0:
				socket.apply_load(-impact * 10.0, 1.0)
			else:
				mission.incident_log.incident("%s slammed shut" % display_name)
	elif height >= max_height:
		height = max_height
		vel = minf(vel, 0.0)


func net_get() -> Array:
	return [height, brace_min, jack_enabled]


func net_set(s: Array) -> void:
	height = s[0]
	brace_min = s[1]
	jack_enabled = s[2]
