class_name Support
extends Node3D
## Authored structural support: STABLE -> STRAINED -> CRITICAL -> FAILED.
## Everything under this node is its structure: the Column, plus anything the
## level parents to it (a beam, a frame header). It decays with facility
## instability, tremors, and the tension of any winch cable attached to its
## structure. A Brace post standing in its BraceZone slows the decay (and
## slowly reverses it). The brace itself wears out under the load.
## On failure the column topples, cables on the structure snap, and `failed`
## fires. The level connects that signal to whatever else should fall.

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
## Health lost per second (%) per 1000 N of cable tension on the structure.
@export var load_decay := 2.0
## Decay multiplier while braced.
@export var braced_factor := 0.2
## Health regained per second (%) while braced and (almost) unloaded, up to 70.
@export var braced_recovery := 0.35
## Which way the column falls when it fails (world space, horizontal).
@export var topple_direction := Vector3(1, 0, 0)

var health := 100.0
var mission: Mission
var _mat: StandardMaterial3D

@onready var column: Prop = $Column
@onready var column_mesh: MeshInstance3D = $Column/Mesh
@onready var brace_zone: Area3D = $BraceZone
@onready var label: Label3D = $Label


func _ready() -> void:
	add_to_group("net")
	add_to_group("supports")
	mission = Mission.of(self)
	_mat = column_mesh.get_active_material(0).duplicate()
	column_mesh.material_override = _mat


func state() -> State:
	if health <= 0.0:
		return State.FAILED
	if health < 35.0:
		return State.CRITICAL
	if health < 70.0:
		return State.STRAINED
	return State.STABLE


## The Brace currently propping this support, if any.
func bracing_brace() -> Brace:
	for b in brace_zone.get_overlapping_bodies():
		if b is Brace and b.is_bracing():
			return b
	return null


## Host: take damage directly (tremors, impacts).
func damage(amount: float) -> void:
	if health > 0.0 and multiplayer.is_server():
		health = maxf(0.0, health - amount)
		if health <= 0.0:
			_fail()


func _physics_process(delta: float) -> void:
	if mission and multiplayer.is_server() and mission.running() and health > 0.0:
		_simulate(delta)
	_update_visual()


func _simulate(delta: float) -> void:
	var load_n := mission.toolkit.load_on(self)
	var rate := base_decay + instability_decay * mission.clock.instability() + load_decay * load_n / 1000.0
	var brace := bracing_brace()
	if brace:
		brace.apply_load(rate * 0.8 * delta)
		rate *= braced_factor
		if load_n < 200.0 and health < 70.0:
			rate -= braced_recovery
	health = clampf(health - rate * delta, 0.0, 100.0)
	if health <= 0.0:
		_fail()


func _fail() -> void:
	health = 0.0
	mission.incident_log.incident("%s FAILED" % display_name)
	mission.toolkit.snap_cables_on(self)
	column.wake()
	# Shove the top of the column so it topples instead of standing there.
	var top := column.global_basis.y * 4.5
	column.apply_impulse(topple_direction.normalized() * column.mass * 1.5, top)
	mission.tremors.jolt(0.6)
	failed.emit()


func _update_visual() -> void:
	var s := state()
	_mat.albedo_color = STATE_COLORS[s]
	label.text = "%s\n%s  %d%%%s" % [display_name.to_upper(), STATE_NAMES[s], ceili(health),
		"\nBRACED" if s != State.FAILED and bracing_brace() else ""]
	label.modulate = STATE_COLORS[s].lightened(0.3)
	label.visible = s != State.FAILED
	# The weaker it gets, the harder it shudders.
	var shudder := 0.0
	if s == State.CRITICAL:
		shudder = 0.05
	elif s == State.STRAINED:
		shudder = 0.012
	shudder += mission.tremors.shake * 0.06 if mission else 0.0
	column_mesh.position = Vector3(randf_range(-shudder, shudder), 2.5, randf_range(-shudder, shudder))


func net_get() -> Array:
	return [health]


func net_set(s: Array) -> void:
	health = s[0]
