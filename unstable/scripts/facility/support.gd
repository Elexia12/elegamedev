class_name Support
extends Node3D
## Authored structural support: STABLE -> STRAINED -> CRITICAL -> FAILED.
## Decays with facility instability and with cable tension on anchors bolted to
## it. A brace slows decay (and slowly reverses it while unloaded). On failure
## it snaps the cables on its anchors and emits `failed`. The level connects
## that signal to whatever should happen next (drop a beam, cut a jack).

signal failed

enum State { STABLE, STRAINED, CRITICAL, FAILED }

const STATE_NAMES := ["STABLE", "STRAINED", "CRITICAL", "FAILED"]
const STATE_COLORS := [
	Color(0.35, 0.8, 0.4), Color(1.0, 0.8, 0.15), Color(1.0, 0.35, 0.1), Color(0.45, 0.1, 0.1)
]

@export var display_name := "Support"
## Health lost per second (%) at zero instability.
@export var base_decay := 0.02
## Extra health lost per second (%) at full instability.
@export var instability_decay := 0.22
## Health lost per second (%) per 1000 N of cable tension on bolted anchors.
@export var load_decay := 2.0
## Decay multiplier while braced.
@export var braced_factor := 0.2
## Health regained per second (%) while braced and (almost) unloaded, up to 70.
@export var braced_recovery := 0.35

var health := 100.0
var mission: Mission
var _last_state := State.STABLE
var _mat: StandardMaterial3D

@onready var socket: BraceSocket = $BraceSocket
@onready var column: Node3D = $Column
@onready var label: Label3D = $Label


func _ready() -> void:
	add_to_group("net")
	mission = Mission.of(self)
	var mesh: MeshInstance3D = $Column/Mesh
	_mat = mesh.get_active_material(0).duplicate()
	mesh.material_override = _mat


func state() -> State:
	if health <= 0.0:
		return State.FAILED
	if health < 35.0:
		return State.CRITICAL
	if health < 70.0:
		return State.STRAINED
	return State.STABLE


func load_newtons() -> float:
	var total := 0.0
	for a: Anchor in get_tree().get_nodes_in_group("anchors"):
		if a.support() == self:
			total += a.tension
	return total


func _physics_process(delta: float) -> void:
	if mission and multiplayer.is_server() and mission.running() and health > 0.0:
		_simulate(delta)
	_update_visual(delta)


func _simulate(delta: float) -> void:
	var load_n := load_newtons()
	var rate := base_decay + instability_decay * mission.clock.instability() + load_decay * load_n / 1000.0
	if socket.braced:
		socket.apply_load(rate * 0.8, delta)
		rate *= braced_factor
		if load_n < 200.0 and health < 70.0:
			rate -= braced_recovery
	health = clampf(health - rate * delta, 0.0, 100.0)
	var s := state()
	if s != _last_state:
		if s > _last_state and s != State.FAILED:
			mission.incident_log.broadcast("%s is %s" % [display_name, STATE_NAMES[s]], "warn")
		_last_state = s
	if health <= 0.0:
		_fail()


func _fail() -> void:
	health = 0.0
	_last_state = State.FAILED
	mission.incident_log.incident("%s FAILED" % display_name)
	for a: Anchor in get_tree().get_nodes_in_group("anchors"):
		if a.support() == self:
			mission.toolkit.snap_cable(a.point, "torn loose")
	# What else breaks is wired in the level: see this node's `failed`
	# connections in the Node dock (e.g. Gantry strut -> GantryBeam.wake).
	failed.emit()


func _update_visual(delta: float) -> void:
	var s := state()
	_mat.albedo_color = STATE_COLORS[s]
	label.text = "%s\n%s  %d%%" % [display_name.to_upper(), STATE_NAMES[s], ceili(health)]
	label.modulate = STATE_COLORS[s].lightened(0.3)
	var lean := 0.18 if s == State.FAILED else 0.0
	column.rotation.z = lerpf(column.rotation.z, lean, 1.0 - exp(-3.0 * delta))
	# Critical supports visibly shudder.
	column.position.x = randf_range(-0.03, 0.03) if s == State.CRITICAL else 0.0


func net_get() -> Array:
	return [health]


func net_set(s: Array) -> void:
	health = s[0]
