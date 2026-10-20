class_name CrewMember
extends CharacterBody3D
## First-person crew member. The child nodes do most of the work:
##   Head/Camera3D/InteractRay  finds InteractPoints (cable ends, valves, lever)
##   Head/Camera3D/GrabRay      finds the surface you're looking at: props to
##                              grab, anything to hook a winch cable to
##   Tools/Winch, Pressure      the CrewTools (child order = hotkeys 1-2)
##   Hands                      grab, carry, drag, throw, turn things upright
##   Vitals                     breath and knockouts
##   Sync                       replicates transform, aim, tool and knocked
## This script does movement, mouse look, aiming and input routing. It also
## takes hits: knock() shoves and stuns you (falling rubble, a snapped cable, a
## crate a teammate threw), and tremors and water jets push you around.
##
## The owning peer moves this body (client-authoritative movement). Anything
## that changes the facility goes to the host through Mission.send().

const AIM_REACH := 6.0

@export var walk_speed := 4.5
@export var sprint_speed := 7.0
@export var jump_velocity := 4.6
@export var mouse_sensitivity := 0.0025
## Speed multiplier when wading (water above the knees).
@export var water_slow := 0.55
## Camera shake (radians) at full tremor strength.
@export var max_shake := 0.05

## Index of the selected tool (replicated).
var tool := 0
var display_name := ""
var mission: Mission
## Owner: what the crosshair is on (an InteractPoint, a Prop, or null).
var aim_target: Node = null
var aim_point := Vector3.ZERO

var _held_button := ""
var _stun := 0.0
var _hit_shake := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _tool_mat := StandardMaterial3D.new()
var tools: Array[CrewTool] = []

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var interact_ray: RayCast3D = $Head/Camera3D/InteractRay
@onready var grab_ray: RayCast3D = $Head/Camera3D/GrabRay
@onready var tool_model: MeshInstance3D = $Head/ToolModel
@onready var body_mesh: MeshInstance3D = $Body
@onready var name_label: Label3D = $NameLabel
@onready var hands: Hands = $Hands
@onready var vitals: Vitals = $Vitals


func _enter_tree() -> void:
	set_multiplayer_authority(str(name).to_int())
	display_name = "Crew %d" % (str(name).to_int() % 1000)


func _ready() -> void:
	mission = Mission.of(self)
	tools.assign($Tools.get_children())
	var id := get_multiplayer_authority()
	name_label.text = display_name
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color.from_hsv(fmod(id * 0.618034, 1.0), 0.55, 0.9)
	body_mesh.material_override = body_mat
	_tool_mat.emission_enabled = true
	tool_model.material_override = _tool_mat
	grab_ray.add_exception(self)
	var mine := is_multiplayer_authority()
	camera.current = mine
	interact_ray.enabled = mine
	grab_ray.enabled = mine
	if mine:
		global_position = mission.crew.spawn_position(id)
		mission.incident_log.client_event.connect(func(kind: String, text: String) -> void:
			if kind == "release":
				hands.on_dropped(text))


func current_tool() -> CrewTool:
	return tools[tool]


func knocked() -> bool:
	return vitals.knocked


## Stunned or knocked out: no control.
func helpless() -> bool:
	return vitals.knocked or _stun > 0.0


## Host: something hit this crew member. Their own machine applies it.
func knock(impulse: Vector3, stun: float) -> void:
	_receive_knock.rpc_id(get_multiplayer_authority(), impulse, stun)


@rpc("any_peer", "call_local", "reliable")
func _receive_knock(impulse: Vector3, stun: float) -> void:
	velocity += impulse
	_stun = maxf(_stun, stun)
	_hit_shake = maxf(_hit_shake, clampf(stun, 0.3, 1.0))
	if stun >= 2.0 and not vitals.knocked:
		vitals.knock_out("%s got flattened" % display_name)


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
	if not captured or knocked() or not mission.running():
		return
	for i in tools.size():
		if event.is_action_pressed("tool_%d" % (i + 1)):
			select_tool(i)
	if event.is_action_pressed("tool_next"):
		select_tool((tool + 1) % tools.size())
	elif event.is_action_pressed("tool_prev"):
		select_tool((tool + tools.size() - 1) % tools.size())
	elif event.is_action_pressed("interact"):
		_interact()
	elif event.is_action_pressed("tool_primary"):
		if hands.holding:
			hands.throw()
		else:
			current_tool().primary(aim_target as InteractPoint)
	elif event.is_action_pressed("tool_secondary"):
		if not hands.holding:
			current_tool().secondary(aim_target as InteractPoint)
	elif event.is_action_pressed("remove"):
		_remove()


func select_tool(i: int) -> void:
	if i == tool:
		return
	_release_hold(_held_button)
	current_tool().deselected()
	tool = i


func _interact() -> void:
	if hands.holding:
		hands.release()
		return
	var t := aim_target
	if t is InteractPoint:
		match t.kind:
			"lever":
				mission.send("lever", path_to(t))
			"valve":
				toast("Valves are turned with the Pressure tool [2]")
		return
	if t is Prop:
		hands.grab(t, aim_point, camera.global_position.distance_to(aim_point))


## R: turn what you're holding (free → upright → flat), or detach a cable end.
func _remove() -> void:
	if hands.holding:
		hands.cycle_align()
		return
	var t := aim_target as InteractPoint
	if t and mission.toolkit.cable_at(t):
		mission.send("winch_detach", path_to(t))


## Owner: ask the host to run a continuous action until the button is released.
func start_hold(button: String, kind: String, target: Node, dir: float) -> void:
	_held_button = button
	mission.send("hold", kind, path_to(target) if target else "", Vector3(dir, 0, 0))


func _release_hold(button: String) -> void:
	if button != "" and _held_button == button:
		_held_button = ""
		mission.send("hold", "")


func path_to(n: Node) -> String:
	return str(mission.get_path_to(n))


func toast(text: String) -> void:
	mission.incident_log.local_toast(text)


## HUD prompt for whatever the crosshair is on.
func prompt() -> String:
	if helpless():
		return ""
	if hands.holding:
		return hands.prompt()
	var t := aim_target
	if t is InteractPoint:
		if t.kind == "lever":
			if mission.extraction.is_rising():
				return "The lift is rising"
			return "[E] %s" % ("cancel extraction" if mission.extraction.is_counting() else "call extraction")
		if current_tool().handles_point(t):
			return current_tool().prompt(t)
		for i in tools.size():
			if tools[i].handles_point(t):
				return "%s — switch to %s [%d]" % [t.describe(), tools[i].display_name, i + 1]
		return ""
	var surface := current_tool().surface_prompt()
	if t is Prop and t.is_grabbable():
		var grab := "[E] %s %s" % ["carry" if hands.can_lift(t) else "drag", t.display_name]
		return grab + ("   ·   " + surface if surface != "" else "")
	var gate := grab_ray.get_collider() as Gate
	if gate:
		return gate.hint() + ("\n" + surface if surface != "" else "")
	return surface


# --- Vitals (signals wired in player.tscn) -------------------------------------

func _on_knocked_out(reason: String) -> void:
	if hands.holding or _held_button != "":
		hands.holding = null
		_held_button = ""
		mission.send("hold", "")
	for t in tools:
		t.deselected()
	mission.send("report", reason)


func _on_recovered() -> void:
	global_position = mission.crew.spawn_position(get_multiplayer_authority())
	velocity = Vector3.ZERO


# --- Host: holds ---------------------------------------------------------------

## Host: start/stop a continuous action for this player ("" stops everything).
func set_hold(kind: String, path: String, v: Vector3, f: float) -> void:
	hands.host_stop()
	for t in tools:
		t.host_stop()
	match kind:
		"grab":
			hands.host_start(path, v, f)
		"reel":
			$Tools/Winch.host_start(path, v, f)
		"blast":
			$Tools/Pressure.host_start(path, v, f)


# --- Simulation ----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if mission == null:
		return
	if is_multiplayer_authority():
		_move(delta)
		_update_aim()
	if multiplayer.is_server() and (knocked() or not mission.running()):
		set_hold("", "", Vector3.ZERO, 0.0)
	_update_visuals()


func _move(delta: float) -> void:
	_stun = maxf(0.0, _stun - delta)
	var surface := mission.water_surface_at(global_position + Vector3.UP * 0.1)
	var depth := surface - global_position.y
	var can_act := not helpless() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

	var input := Vector2.ZERO
	if can_act:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	var speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	if depth > 0.4:
		speed *= water_slow
	if hands.holding:
		speed *= 0.7
	# Stunned bodies slide; standing ones grip the floor.
	var accel := (12.0 if is_on_floor() else 3.0) * (0.15 if helpless() else 1.0)
	velocity.x = move_toward(velocity.x, dir.x * speed, accel * speed * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, accel * speed * delta)

	# The world pushes back: water jets, and the floor bucking in a tremor.
	var jet := mission.pressure_network.jet_push_at(global_position + Vector3.UP)
	if jet.length() > 4.0:
		# Caught in the jet: you can't fight it, it carries you.
		velocity += jet * delta * 2.0
		_stun = maxf(_stun, 0.15)
	var shake := mission.tremors.shake
	if shake > 0.45 and is_on_floor():
		velocity += Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)) * shake * 9.0 * delta

	if depth > 1.2:
		velocity.y = maxf(velocity.y - _gravity * 0.3 * delta, -2.0)
		if can_act and Input.is_action_pressed("jump"):
			velocity.y = 2.5
	elif not is_on_floor():
		velocity.y -= _gravity * delta
	elif can_act and Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity
	move_and_slide()

	if global_position.y < -20.0:
		_on_recovered()
	_shake_camera(delta)


func _shake_camera(delta: float) -> void:
	_hit_shake = move_toward(_hit_shake, 0.0, delta * 1.5)
	var s := clampf(mission.tremors.shake + _hit_shake, 0.0, 1.0) * max_shake
	camera.rotation = Vector3(randf_range(-s, s), randf_range(-s, s), randf_range(-s, s) * 0.5)
	# Dazed: the view tilts while stunned.
	camera.rotation.z += 0.25 if helpless() else 0.0


func _update_aim() -> void:
	interact_ray.force_raycast_update()
	grab_ray.force_raycast_update()
	var from := camera.global_position
	aim_target = null
	aim_point = grab_ray.to_global(grab_ray.target_position)
	var body_dist := INF
	if grab_ray.is_colliding():
		aim_point = grab_ray.get_collision_point()
		body_dist = from.distance_to(aim_point)
	# Interact points win unless a wall is clearly in front of them.
	if interact_ray.is_colliding() and from.distance_to(interact_ray.get_collision_point()) <= body_dist + 0.6:
		aim_target = interact_ray.get_collider()
	elif grab_ray.get_collider() is Prop:
		aim_target = grab_ray.get_collider()


func _update_visuals() -> void:
	body_mesh.rotation.z = PI / 2.0 if knocked() else 0.0
	body_mesh.position.y = 0.4 if knocked() else 0.9
	var t := current_tool()
	_tool_mat.albedo_color = t.color
	_tool_mat.emission = t.color * 0.3
	tool_model.scale = t.model_size
	name_label.visible = not is_multiplayer_authority()
