class_name CrewMember
extends CharacterBody3D
## First-person crew member. The owning peer moves it (client-authoritative
## movement) and picks targets; every effect on the facility is a request the
## host resolves through Mission.request(). Continuous actions (grab, reel,
## pressure blast) are "holds" the host applies each physics frame using this
## player's replicated aim.

enum Tool { WINCH, BRACE, PRESSURE }

const TOOL_NAMES := ["WINCH", "BRACE", "PRESSURE"]
const TOOL_COLORS := [Color(1.0, 0.78, 0.1), Color(1.0, 0.45, 0.1), Color(0.2, 0.85, 1.0)]
const TOOL_SHAPES := [Vector3(0.1, 0.1, 0.3), Vector3(0.05, 0.05, 0.5), Vector3(0.08, 0.08, 0.4)]
## Aim distance for interact points (generous on purpose).
const AIM_REACH := 6.0
## Max distance to grab a body.
const GRAB_REACH := 4.0

@export var walk_speed := 4.5
@export var sprint_speed := 7.0
@export var jump_velocity := 4.6
@export var mouse_sensitivity := 0.0025
## Speed multiplier when wading (water above the knees).
@export var water_slow := 0.55
@export var breath_max := 10.0
@export var knockout_time := 5.0
@export_group("Grab")
## Max force one crew member can apply to a grabbed body (N). A 300 kg
## reactor core needs two people (or a winch).
@export var grab_force := 950.0
@export var grab_stiffness := 60.0
@export var grab_damping := 12.0

## Replicated (owner -> everyone).
var tool: int = Tool.WINCH
var knocked := false

var display_name := ""
var mission: Mission

# Owner-only state.
var aim_target: Node = null
var aim_point := Vector3.ZERO
var pending_hook: InteractPoint = null
var grabbing: Prop = null
var breath := 10.0
var _knock_timer := 0.0
var _held_button := ""

# Host-only state.
var hold_kind := ""
var hold_path := ""
var hold_offset := Vector3.ZERO
var hold_distance := 2.0
var _hold_cable: Cable = null

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _tool_mat := StandardMaterial3D.new()

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var tool_mesh: MeshInstance3D = $Head/Tool
@onready var body_mesh: MeshInstance3D = $Body
@onready var name_label: Label3D = $NameLabel


func _enter_tree() -> void:
	set_multiplayer_authority(str(name).to_int())
	display_name = "Crew %d" % (str(name).to_int() % 1000)


func _ready() -> void:
	mission = Mission.of(self)
	var id := get_multiplayer_authority()
	name_label.text = display_name
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color.from_hsv(fmod(id * 0.618034, 1.0), 0.55, 0.9)
	body_mesh.material_override = body_mat
	_tool_mat.emission_enabled = true
	tool_mesh.material_override = _tool_mat
	breath = breath_max
	camera.current = is_multiplayer_authority()
	if is_multiplayer_authority():
		global_position = mission.spawn_position(id)
		mission.client_event.connect(func(kind: String, text: String) -> void:
			if kind == "release":
				on_released(text))


func _exit_tree() -> void:
	if _hold_cable:
		_hold_cable.reel = 0


# --- Owner input -------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or mission == null:
		return
	if event.is_action_released("tool_primary"):
		_release_hold("primary")
	elif event.is_action_released("tool_secondary"):
		_release_hold("secondary")
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and captured:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clampf(head.rotation.x, -1.45, 1.45)
		return
	if not captured or knocked or not mission.running():
		return
	if event.is_action_pressed("tool_1"):
		_select_tool(Tool.WINCH)
	elif event.is_action_pressed("tool_2"):
		_select_tool(Tool.BRACE)
	elif event.is_action_pressed("tool_3"):
		_select_tool(Tool.PRESSURE)
	elif event.is_action_pressed("tool_next"):
		_select_tool((tool + 1) % 3)
	elif event.is_action_pressed("tool_prev"):
		_select_tool((tool + 2) % 3)
	elif event.is_action_pressed("interact"):
		_interact()
	elif event.is_action_pressed("tool_primary"):
		_primary()
	elif event.is_action_pressed("tool_secondary"):
		_secondary()
	elif event.is_action_pressed("remove"):
		_remove()


func _select_tool(t: int) -> void:
	if t == tool:
		return
	_release_hold(_held_button)
	tool = t
	if tool != Tool.WINCH:
		pending_hook = null


func _interact() -> void:
	if grabbing:
		_let_go()
		return
	var t := aim_target
	if t is InteractPoint:
		match t.kind:
			"lever":
				mission.send("lever", _p(t))
				return
			"valve":
				_toast("Valves are turned with the Pressure tool [3]")
				return
			"hook":
				t = t.receiver()
	if t is Prop and _can_grab(t):
		grabbing = t
		var dist := camera.global_position.distance_to(aim_point)
		var at: Vector3 = aim_point if aim_target is not InteractPoint else aim_target.global_position
		mission.send("hold", "grab", _p(t), t.to_local(at), clampf(dist, 1.3, 3.0))


func _primary() -> void:
	if grabbing:
		_toast("Hands full — [E] to let go")
		return
	var t := aim_target as InteractPoint
	match tool:
		Tool.WINCH:
			if t == null or t.kind not in ["hook", "anchor"]:
				return
			if mission.cable_at(t):
				_start_hold("primary", "reel", t, 1.0)
			elif t.kind == "hook":
				pending_hook = t
				_toast("Hook set on %s — now LMB an anchor point" % t.describe())
			elif pending_hook:
				mission.send("winch_attach", _p(pending_hook), _p(t))
				pending_hook = null
			else:
				_toast("Pick a hook on cargo or the gate first")
		Tool.BRACE:
			if t and t.kind == "brace":
				mission.send("brace_place", _p(t))
		Tool.PRESSURE:
			if t and t.kind == "valve":
				mission.send("valve", _p(t), "", Vector3(0.25, 0, 0))
			else:
				_start_hold("primary", "blast", null, 1.0)


func _secondary() -> void:
	if grabbing:
		return
	var t := aim_target as InteractPoint
	match tool:
		Tool.WINCH:
			if t and mission.cable_at(t):
				_start_hold("secondary", "reel", t, -1.0)
			elif pending_hook:
				pending_hook = null
				_toast("Hook selection cleared")
		Tool.BRACE:
			if t and t.kind == "brace":
				mission.send("brace_remove", _p(t))
		Tool.PRESSURE:
			if t and t.kind == "valve":
				mission.send("valve", _p(t), "", Vector3(-0.25, 0, 0))
			else:
				_start_hold("secondary", "blast", null, -1.0)


func _remove() -> void:
	var t := aim_target as InteractPoint
	if t and mission.cable_at(t):
		mission.send("winch_detach", _p(t))
	elif t and t.kind == "brace":
		mission.send("brace_remove", _p(t))
	elif pending_hook:
		pending_hook = null


func _start_hold(button: String, kind: String, target: Node, dir: float) -> void:
	_held_button = button
	mission.send("hold", kind, _p(target) if target else "", Vector3(dir, 0, 0))


func _release_hold(button: String) -> void:
	if button != "" and _held_button == button:
		_held_button = ""
		mission.send("hold", "")


func _let_go() -> void:
	grabbing = null
	mission.send("hold", "")


func _can_grab(p: Prop) -> bool:
	if not p.is_grabbable():
		_toast("%s is bolted in place" % p.display_name)
		return false
	if camera.global_position.distance_to(aim_point) > GRAB_REACH:
		return false
	return true


func _p(n: Node) -> String:
	return str(mission.get_path_to(n))


func _toast(text: String) -> void:
	mission.client_event.emit("toast", text)


## HUD prompt for whatever the crosshair is on.
func prompt() -> String:
	if knocked:
		return ""
	if grabbing:
		return "[E] let go of %s" % grabbing.display_name
	var t := aim_target
	if t is Prop:
		if not t.is_grabbable():
			return t.display_name
		var heavy: bool = t.mass * 9.8 > grab_force * 0.6
		return "[E] %s %s%s" % ["drag" if heavy else "carry", t.display_name,
			"  (heavy — get help or use the winch)" if t.mass > 150 else ""]
	if not t is InteractPoint:
		return ""
	var what: String = t.describe()
	var cable := mission.cable_at(t)
	match t.kind:
		"hook", "anchor":
			if tool != Tool.WINCH:
				return "%s — switch to WINCH [1]" % what
			if cable:
				return "%s · hold LMB reel in · hold RMB pay out · [R] detach" % what
			if t.kind == "hook":
				return "%s · LMB select hook" % what
			if pending_hook:
				return "%s · LMB attach cable from %s" % [what, pending_hook.describe()]
			return "%s anchor · select a hook first" % what
		"brace":
			var socket := t.get_parent() as BraceSocket
			if socket.braced:
				return "%s brace %d%% · RMB/[R] recover brace" % [what, roundi(socket.integrity)]
			if tool != Tool.BRACE:
				return "%s brace point — switch to BRACE [2]" % what
			var why := socket.block_reason()
			return "%s · %s" % [what, why if why != "" else "LMB place brace (%d left)" % mission.braces_left]
		"valve":
			if tool != Tool.PRESSURE:
				return "%s — switch to PRESSURE [3]" % what
			return "%s · LMB open · RMB close" % what
		"lever":
			return "[E] %s" % ("cancel extraction" if mission.extract_timer >= 0.0 else "call extraction")
	return ""


# --- Simulation --------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if mission == null:
		return
	if is_multiplayer_authority():
		_owner_physics(delta)
	if multiplayer.is_server():
		_process_hold()
	_update_visuals()


func _owner_physics(delta: float) -> void:
	var surface := mission.water_surface_at(global_position + Vector3.UP * 0.1)
	var depth := surface - global_position.y
	var head_under := mission.water_surface_at(head.global_position) > head.global_position.y

	if knocked:
		_knock_timer -= delta
		if _knock_timer <= 0.0:
			knocked = false
			breath = breath_max
			global_position = mission.spawn_position(get_multiplayer_authority())
			velocity = Vector3.ZERO
	elif head_under:
		breath -= delta
		if breath <= 0.0:
			_knock_out("%s blacked out underwater" % display_name)
	else:
		breath = minf(breath_max, breath + 2.5 * delta)

	var input := Vector2.ZERO
	if not knocked and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	var speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	if depth > 0.4:
		speed *= water_slow
	if grabbing:
		speed *= 0.7
	var accel := 12.0 if is_on_floor() else 3.0
	velocity.x = move_toward(velocity.x, dir.x * speed, accel * speed * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, accel * speed * delta)

	var swimming := depth > 1.2
	if swimming:
		velocity.y = maxf(velocity.y - _gravity * 0.3 * delta, -2.0)
		if Input.is_action_pressed("jump") and not knocked:
			velocity.y = 2.5
	elif not is_on_floor():
		velocity.y -= _gravity * delta
	elif Input.is_action_just_pressed("jump") and not knocked and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		velocity.y = jump_velocity
	move_and_slide()

	if global_position.y < -20.0:
		global_position = mission.spawn_position(get_multiplayer_authority())
		velocity = Vector3.ZERO
	_update_aim()


func _knock_out(reason: String) -> void:
	knocked = true
	_knock_timer = knockout_time
	pending_hook = null
	if grabbing or _held_button != "":
		grabbing = null
		_held_button = ""
		mission.send("hold", "")
	mission.send("report", reason)


func _update_aim() -> void:
	var space := get_world_3d().direct_space_state
	var from := camera.global_position
	var fwd := -camera.global_basis.z
	var qa := PhysicsRayQueryParameters3D.create(from, from + fwd * AIM_REACH, 8)
	qa.collide_with_areas = true
	qa.collide_with_bodies = false
	var hit_area := space.intersect_ray(qa)
	var qb := PhysicsRayQueryParameters3D.create(from, from + fwd * GRAB_REACH, 1 | 4, [get_rid()])
	var hit_body := space.intersect_ray(qb)
	aim_target = null
	aim_point = from + fwd * GRAB_REACH
	if hit_body:
		aim_point = hit_body.position
	if hit_area and (hit_body.is_empty() or from.distance_to(hit_area.position) <= from.distance_to(hit_body.position) + 0.6):
		aim_target = hit_area.collider
	elif hit_body and hit_body.collider is Prop:
		aim_target = hit_body.collider


## Host: start/stop a continuous action for this player.
func set_hold(kind: String, path: String, v: Vector3, f: float) -> void:
	if _hold_cable:
		_hold_cable.reel = 0
		_hold_cable = null
	hold_kind = kind
	hold_path = path
	hold_offset = v
	hold_distance = f
	if kind == "reel":
		_hold_cable = mission.cable_at(mission.get_node_or_null(path))
		if _hold_cable:
			_hold_cable.reel = int(signf(v.x))
		else:
			hold_kind = ""


func _process_hold() -> void:
	if hold_kind == "":
		return
	if knocked or not mission.running():
		set_hold("", "", Vector3.ZERO, 0.0)
		return
	match hold_kind:
		"grab":
			var p := mission.get_node_or_null(hold_path) as Prop
			if p == null or p.freeze:
				_drop_grab("")
				return
			var target := head.global_position - head.global_basis.z * hold_distance
			var gp := p.to_global(hold_offset)
			if gp.distance_to(target) > 3.0:
				_drop_grab("Lost your grip on %s" % p.display_name)
				return
			var force := ((target - gp) * grab_stiffness - p.point_velocity(gp) * grab_damping) * p.mass
			var lift := p.mass * _gravity
			if lift <= grab_force * 0.6:
				force += Vector3.UP * lift
			else:
				force.y = minf(force.y, 0.0)
			force = force.limit_length(grab_force)
			p.sleeping = false
			p.apply_force(force, gp - p.global_position)
			p.apply_torque(-p.angular_velocity * p.mass * 0.5)
		"blast":
			mission.pressure_blast(head.global_position, -head.global_basis.z, signf(hold_offset.x))
		"reel":
			if _hold_cable == null or not _hold_cable.active:
				set_hold("", "", Vector3.ZERO, 0.0)


func _drop_grab(msg: String) -> void:
	set_hold("", "", Vector3.ZERO, 0.0)
	mission.notify.rpc_id(get_multiplayer_authority(), "release", msg)


func on_released(msg: String) -> void:
	grabbing = null
	if msg != "":
		_toast(msg)


func _update_visuals() -> void:
	body_mesh.rotation.z = PI / 2.0 if knocked else 0.0
	body_mesh.position.y = 0.4 if knocked else 0.9
	_tool_mat.albedo_color = TOOL_COLORS[tool]
	_tool_mat.emission = TOOL_COLORS[tool] * 0.3
	tool_mesh.scale = TOOL_SHAPES[tool]
	name_label.visible = not is_multiplayer_authority()
