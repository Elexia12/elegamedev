class_name OverheadHoist
extends Node3D
## Fixed overhead hoist: a carriage on a rail (this node's local X axis) with
## a hook on a chain. One crew member takes the controls at the Pendant ([E])
## and drives it with the movement keys: A/D run the carriage along the rail,
## W raises the hook, S lowers it. Anyone can hook a load ([E] on the hook or
## on a prop's LiftingEye when the hook is next to it) and unhook it once it's
## resting on something.
##
## States: IDLE (nobody on the controls) -> ATTACHED (a load on the hook) ->
## OPERATING (someone driving it) -> back to IDLE.
##
## The chain is a stiff one-sided spring, so the load is a real pendulum: the
## carriage accelerates gently but brakes hard, and a hard stop (or hitting
## the end of the rail) sets the load swinging. Teammates can grab the load to
## steady it. Simulated on the host; clients draw it from the replicated state.

@export var display_name := "Overhead hoist"
## Rail length (m), centred on this node.
@export var rail_length := 12.0
@export var max_speed := 1.5
@export var acceleration := 0.9
## Deceleration when you let go or reverse: higher than acceleration, so
## stopping is abrupt and the load swings on.
@export var braking := 3.5
@export var lift_speed := 0.7
@export var min_length := 0.8
@export var max_length := 5.8
## Rope spring per kg of load (1/s²) and damping (1/s).
@export var stiffness := 300.0
@export var damping := 25.0
## Damping of the load's swing relative to the carriage (1/s). Low = swingy.
@export var sway_damping := 0.45
## How close (m) the hook must be to a LiftingEye to hook on.
@export var hook_reach := 1.3
## Rated load (kg). The chain tension readout turns red above it.
@export var capacity := 800.0
## Unhooking needs the load mostly supported: tension below this share of its weight.
@export var unhook_share := 0.35
@export var start_x := 0.0
@export var start_length := 2.0

var x := 0.0
var vx := 0.0
var length := 2.0
## Peer id holding the pendant controls (0 = nobody).
var operator := 0
## Latest drive input from the operator: x = A/D, y = W (+1) / S (-1).
var input := Vector3.ZERO
## Mission-relative path of the hooked prop ("" = empty hook) and the eye's
## point in its local space.
var load_path := ""
var eye_local := Vector3.ZERO
var tension := 0.0
var mission: Mission
var _hook_visual := Vector3.ZERO

@onready var carriage: Node3D = $Carriage
@onready var carriage_label: Label3D = $Carriage/Label
@onready var chain: MeshInstance3D = $Chain
@onready var hook: Node3D = $Hook
@onready var hook_point: InteractPoint = $Hook/Point
@onready var pendant: Node3D = $Pendant
@onready var pendant_point: InteractPoint = $Pendant/Point
@onready var pendant_label: Label3D = $Pendant/Label


func _ready() -> void:
	add_to_group("net")
	add_to_group("machines")
	mission = Mission.of(self)
	x = start_x
	length = start_length
	chain.top_level = true
	hook.top_level = true
	_hook_visual = anchor_position() + Vector3.DOWN * length


# --- Queries -------------------------------------------------------------------

func operator_id() -> int:
	return operator


func load_prop() -> Prop:
	if load_path == "":
		return null
	return mission.get_node_or_null(load_path) as Prop


## Where the chain leaves the carriage (world).
func anchor_position() -> Vector3:
	return to_global(Vector3(x, -0.35, 0.0))


func hook_position() -> Vector3:
	var p := load_prop()
	if p:
		return p.to_global(eye_local)
	return anchor_position() + Vector3.DOWN * length


func state_name() -> String:
	if operator != 0:
		return "OPERATING"
	if load_path != "":
		return "ATTACHED"
	return "IDLE"


## The LiftingEye nearest the hook, if one is within reach.
func eye_in_reach() -> LiftingEye:
	var best: LiftingEye = null
	var best_d := hook_reach
	for e in get_tree().get_nodes_in_group("lifting_eyes"):
		if e is LiftingEye and mission.is_ancestor_of(e) and e.visible:
			var d: float = e.global_position.distance_to(hook_position())
			if d < best_d:
				best = e
				best_d = d
	return best


func _member_name(id: int) -> String:
	var c := mission.crew.member(id)
	return c.display_name if c else "Someone"


# --- Player actions (host) ---------------------------------------------------------

## [E] on the pendant, the hook, or a LiftingEye (which forwards here).
func use(player: CrewMember, target: Node) -> String:
	var id := player.get_multiplayer_authority()
	if target == pendant_point:
		if operator == 0:
			operator = id
			input = Vector3.ZERO
			return ""
		if operator == id:
			return release(player)
		return "%s is on the hoist controls" % _member_name(operator)
	# The hook end.
	var p := load_prop()
	if p:
		var weight := p.mass * 9.8
		if tension > weight * unhook_share:
			return "The hoist is still carrying the %s — lower it onto something first" % p.display_name
		load_path = ""
		tension = 0.0
		return "Unhooked the %s" % p.display_name
	var eye := eye_in_reach()
	if eye == null:
		return "Bring the hook next to a lifting eye first (it's %.1f m away)" % _nearest_eye_distance()
	var prop := eye.get_parent() as Prop
	load_path = str(mission.get_path_to(prop))
	eye_local = prop.to_local(eye.global_position)
	return "Hooked onto the %s" % prop.display_name


func _nearest_eye_distance() -> float:
	var d := INF
	for e in get_tree().get_nodes_in_group("lifting_eyes"):
		if mission.is_ancestor_of(e):
			d = minf(d, e.global_position.distance_to(hook_position()))
	return d


func drive(_player: CrewMember, v: Vector3) -> void:
	input = v.clamp(-Vector3.ONE, Vector3.ONE)


func release(_player: CrewMember) -> String:
	operator = 0
	input = Vector3.ZERO
	return ""


# --- Prompts (owner side) ----------------------------------------------------------

func prompt_for(crew: CrewMember, target: Node) -> String:
	if target == pendant_point:
		if operator == 0:
			return "Hoist pendant · %s · [E] take the controls" % state_name()
		return "%s is on the hoist controls" % _member_name(operator)
	var p := load_prop()
	if p:
		if tension > p.mass * 9.8 * unhook_share:
			return "Hoist is carrying the %s · lower it onto something before unhooking" % p.display_name
		return "[E] unhook the %s" % p.display_name
	var eye := eye_in_reach()
	if eye:
		return "[E] hook onto the %s" % eye.get_parent().display_name
	if target is LiftingEye:
		return "Lifting eye · bring the hoist hook here (pendant: A/D along the rail, S lowers)"
	return "Hoist hook · lower it next to a lifting eye (pendant: S lowers)"


func operator_prompt() -> String:
	var p := load_prop()
	var what := "hook empty" if p == null else "%s %d kg · %.1f kN" % [p.display_name, roundi(p.mass), tension / 1000.0]
	return "HOIST CONTROLS · A/D run along the rail · W raise · S lower · [E] let go\nhook %.1f m below the rail · %s" % [length, what]


# --- Simulation (host) -------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if mission and multiplayer.is_server() and mission.running():
		_simulate(delta)


func _simulate(delta: float) -> void:
	if operator != 0:
		var c := mission.crew.member(operator)
		if c == null or c.knocked():
			release(null)
	# Carriage: gentle acceleration, abrupt braking.
	var target_v := input.x * max_speed
	var speeding_up := absf(target_v) > absf(vx) and signf(target_v) == signf(vx) or vx == 0.0
	vx = move_toward(vx, target_v, (acceleration if speeding_up else braking) * delta)
	x += vx * delta
	var half := rail_length / 2.0
	if absf(x) > half:
		x = clampf(x, -half, half)
		if absf(vx) > 0.3:
			mission.tremors.jolt(0.15)
		vx = 0.0
	var old_length := length
	length = clampf(length - input.y * lift_speed * delta, min_length, max_length)
	# How fast the chain is being paid out (+) or reeled in (-).
	var payout := (length - old_length) / delta

	var p := load_prop()
	tension = 0.0
	if p == null:
		return
	if not is_instance_valid(p) or p.is_locked():
		load_path = ""
		return
	if p.freeze:
		return
	var a := anchor_position()
	var at := p.to_global(eye_local)
	var d := at - a
	var dist := d.length()
	if dist <= length or dist < 0.01:
		return
	var n := d / dist
	var carriage_v := global_basis.x * vx
	var rel := p.point_velocity(at) - carriage_v
	var stretch := dist - length
	# Damp how fast the stretch changes (the load moving along the chain minus
	# the chain being paid out), so lowering at a steady speed isn't resisted.
	var stretch_rate := rel.dot(n) - payout
	tension = maxf(0.0, p.mass * (stiffness * stretch + damping * stretch_rate))
	tension = minf(tension, capacity * 9.8 * 4.0)
	p.sleeping = false
	p.apply_force(-n * tension, at - p.global_position)
	var sway := rel - n * rel.dot(n)
	p.apply_central_force(-sway * p.mass * sway_damping)


# --- Visuals (every peer) ---------------------------------------------------------

func _process(delta: float) -> void:
	carriage.position.x = x
	var a := anchor_position()
	var target := hook_position()
	# An empty hook trails a little behind the carriage (visual only).
	if load_path == "":
		_hook_visual = _hook_visual.lerp(target, 1.0 - exp(-6.0 * delta))
		target = _hook_visual
	else:
		_hook_visual = target
	hook.global_position = target
	var axis := target - a
	var len := axis.length()
	chain.visible = len > 0.05
	if chain.visible:
		var y := axis / len
		var bx := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT).normalized()
		chain.global_transform = Transform3D(Basis(bx, y * len, bx.cross(y)), (a + target) / 2.0)
	var p := load_prop()
	var over := p != null and tension > capacity * 9.8
	carriage_label.visible = p != null and mission.local_distance(carriage.global_position) < 16.0
	carriage_label.text = "%.1f kN" % (tension / 1000.0)
	carriage_label.modulate = Color(1.0, 0.35, 0.25) if over else Color(1.0, 0.85, 0.3)
	pendant_label.visible = mission.local_distance(pendant.global_position) < 8.0
	pendant_label.text = "HOIST CONTROLS" if operator == 0 else "HOIST · %s" % _member_name(operator)


func net_get() -> Array:
	return [x, vx, length, operator, input, load_path, eye_local, tension]


func net_set(s: Array) -> void:
	x = s[0]
	vx = s[1]
	length = s[2]
	operator = s[3]
	input = s[4]
	load_path = s[5]
	eye_local = s[6]
	tension = s[7]
