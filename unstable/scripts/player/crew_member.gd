class_name CrewMember
extends CharacterBody3D
## First-person crew member. The child nodes do most of the work:
##   Head/Camera3D/InteractRay  finds InteractPoints (cable ends, valves, lever)
##   Head/Camera3D/GrabRay      finds the surface you're looking at: props to
##                              grab, anything to hook a winch cable to
##   Tools/Winch, Pressure, Wrench  the CrewTools (child order = hotkeys). The
##                              level's Crew roster `loadout` picks which ones
##                              this mission hands out.
##   Hands                      grab, carry, drag, throw, turn things upright
##   Vitals                     breath and knockouts
##   Sync                       replicates transform, aim, tool and knocked
## This script does movement, mouse look, aiming and input routing. [E] on a
## facility thing (a hoist pendant, a hook, an ignition) asks that thing to
## handle it (its use()), and its prompt_for() says what [E] will do. While
## you hold a machine's controls (group "machines"), your movement keys drive
## the machine instead of your legs. You also take hits: knock() shoves and
## stuns you (falling rubble, a snapped cable, a swinging motor), and tremors
## and water jets push you around.
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

## Tests (and later, bot crew) can drive this crew member: a Vector2 of
## movement input (like the move keys). null = read the keyboard.
var bot_input = null
var _held_button := ""
## Owner: the last drive input sent to the machine we operate.
var _drive_sent := Vector3.ZERO
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
	var loadout := mission.crew.loadout
	for t in $Tools.get_children():
		if not loadout.is_empty() and not str(t.name) in loadout:
			$Tools.remove_child(t)
			t.queue_free()
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
		var spawn := mission.crew.spawn_marker(id)
		global_position = spawn.global_position
		rotation.y = spawn.global_rotation.y
		mission.incident_log.client_event.connect(func(kind: String, text: String) -> void:
			if kind == "release":
				hands.on_dropped(text)
			elif kind == "hold_ended":
				_held_button = ""
				if text != "":
					toast(text))


func current_tool() -> CrewTool:
	return tools[tool]


## The trolley (group "pushables") this crew member is pushing, if any.
func pushing() -> Node:
	for t in get_tree().get_nodes_in_group("pushables"):
		if mission.is_ancestor_of(t) and t.is_pushed_by(self):
			return t
	return null


## The machine whose controls this crew member holds, if any.
func operated_machine() -> Node:
	for m in mission.machines():
		if m.operator_id() == get_multiplayer_authority():
			return m
	return null


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
	if operated_machine():
		# Hands are on the controls: [E] lets go, nothing else.
		if event.is_action_pressed("interact"):
			mission.send("release_controls")
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
	var pushed := pushing()
	if pushed:
		mission.send("use", path_to(pushed))
		return
	var t := aim_target
	if t is InteractPoint:
		if t.kind == "lever" and mission.extraction:
			mission.send("lever", path_to(t))
		elif t.handler().has_method("use"):
			mission.send("use", path_to(t))
		else:
			for i in tools.size():
				if tools[i].handles_point(t):
					toast("Use the %s on that [%d]" % [tools[i].display_name, i + 1])
		return
	if t is Prop:
		if t.has_method("use_prompt") and t.use_prompt(self) != "":
			mission.send("use", path_to(t))
		else:
			hands.grab(t, aim_point, camera.global_position.distance_to(aim_point))


## R: turn what you're holding (free → upright → flat), or detach a cable end.
func _remove() -> void:
	if hands.holding:
		hands.cycle_align()
		return
	var t := aim_target as InteractPoint
	if t and mission.toolkit and mission.toolkit.cable_at(t):
		mission.send("winch_detach", path_to(t))


## Owner: ask the host to run a continuous action until the button is released.
func start_hold(button: String, kind: String, target: Node, dir: float) -> void:
	_held_button = button
	mission.send("hold", kind, path_to(target) if target else "", Vector3(dir, 0, 0))


func _release_hold(button: String) -> void:
	if button != "" and _held_button == button:
		_held_button = ""
		mission.send("hold", "")


## Owner: stop whatever continuous action is running (e.g. the aim moved off).
func cancel_hold() -> void:
	_release_hold(_held_button)


func is_holding_button() -> bool:
	return _held_button != ""


func path_to(n: Node) -> String:
	return str(mission.get_path_to(n))


func toast(text: String) -> void:
	mission.incident_log.local_toast(text)


## HUD prompt for whatever the crosshair is on.
func prompt() -> String:
	if helpless():
		return ""
	var machine := operated_machine()
	if machine:
		return machine.operator_prompt()
	if hands.holding:
		return hands.prompt()
	if pushing():
		return "Pushing the trolley · walk to push, turn to steer · [E] let go"
	var t := aim_target
	if t is InteractPoint:
		if t.kind == "lever" and mission.extraction:
			if mission.extraction.is_rising():
				return "The lift is rising"
			return "[E] %s" % ("cancel extraction" if mission.extraction.is_counting() else "call extraction")
		if current_tool().handles_point(t):
			return current_tool().prompt(t)
		var h: Node = t.handler()
		if h.has_method("prompt_for"):
			return h.prompt_for(self, t)
		for i in tools.size():
			if tools[i].handles_point(t):
				return "%s — switch to %s [%d]" % [t.describe(), tools[i].display_name, i + 1]
		return ""
	var surface := current_tool().surface_prompt()
	if t is Prop:
		var use: String = t.use_prompt(self) if t.has_method("use_prompt") else ""
		if use != "":
			return use
		if t.is_grabbable():
			var grab := "[E] %s %s" % ["carry" if hands.can_lift(t) else "drag", t.display_name]
			if t.note != "":
				grab += " · " + t.note
			return grab + ("   ·   " + surface if surface != "" else "")
		if t.note != "":
			return "%s · %s" % [t.display_name, t.note]
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
	if operated_machine():
		mission.send("release_controls")
	for t in tools:
		t.deselected()
	mission.send("report", reason)


func _on_recovered() -> void:
	global_position = mission.crew.spawn_position(get_multiplayer_authority())
	velocity = Vector3.ZERO


# --- Host: holds ---------------------------------------------------------------

## Host: start/stop a continuous action for this player ("" stops everything).
## "grab" goes to Hands; anything else to the tool that runs that hold kind.
func set_hold(kind: String, path: String, v: Vector3, f: float) -> void:
	hands.host_stop()
	for t in tools:
		t.host_stop()
	if kind == "grab":
		hands.host_start(path, v, f)
		return
	for t in tools:
		if kind in t.hold_kinds():
			t.host_start(path, v, f)


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
	var can_act := not helpless() and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or bot_input != null)

	var input := Vector2.ZERO
	if can_act:
		input = bot_input if bot_input != null else Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var machine := operated_machine()
	if machine:
		_drive(machine, input)
		input = Vector2.ZERO
	elif _drive_sent != Vector3.ZERO:
		_drive_sent = Vector3.ZERO
	if pushing():
		# Hands on a cart: A/D turn it instead of side-stepping.
		rotate_y(-input.x * deg_to_rad(70.0) * delta)
		input.x = 0.0
	var dir := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	var speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	if depth > 0.4:
		speed *= water_slow
	if hands.holding:
		speed *= 0.7
	var pushed := pushing()
	if pushed:
		speed *= pushed.push_speed_factor()
	# Stunned bodies slide; standing ones grip the floor.
	var accel := (12.0 if is_on_floor() else 3.0) * (0.15 if helpless() else 1.0)
	velocity.x = move_toward(velocity.x, dir.x * speed, accel * speed * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, accel * speed * delta)

	# The world pushes back: water jets, and the floor bucking in a tremor.
	var jet := mission.jet_push_at(global_position + Vector3.UP)
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

	if pushed:
		_tether_to(pushed)

	if global_position.y < -20.0:
		_on_recovered()
	_shake_camera(delta)


## Owner: your hands are on the trolley's handle. You can't walk away from it,
## and you can't turn faster than it does: if it lags (it's heavy, it's stuck)
## it holds you back. Looking up and down stays free.
func _tether_to(pushed: Node) -> void:
	var cart_yaw: float = pushed.heading() - PI / 2.0
	var off_yaw := angle_difference(cart_yaw, rotation.y)
	var max_off := deg_to_rad(12.0)
	if absf(off_yaw) > max_off:
		rotation.y = cart_yaw + clampf(off_yaw, -max_off, max_off)
	var fwd := (-global_basis.z * Vector3(1, 0, 1)).normalized()
	var stand: Vector3 = pushed.handle_for(self) - fwd * pushed.handle_reach
	var off := (global_position - stand) * Vector3(1, 0, 1)
	# Sideways: you line up behind the handle. These corrections are moves,
	# not teleports: a trolley swinging next to a wall can't shove you through it.
	var side := fwd.cross(Vector3.UP)
	var lateral := off.dot(side)
	_shift(-side * lateral * 0.5)
	velocity -= side * velocity.dot(side)
	# Forward: walking into a trolley that won't go stops you. (If it rolls
	# ahead, you don't get dragged after it: your hands hold it back.)
	var ahead := off.dot(fwd)
	var slack := 0.3
	if ahead > slack:
		_shift(-fwd * (ahead - slack))
		velocity -= fwd * maxf(0.0, velocity.dot(fwd))


## Nudge the body by `motion` unless a wall is in the way (checked from a
## little above the floor, so the floor you stand on doesn't count).
func _shift(motion: Vector3) -> void:
	if not test_move(global_transform.translated(Vector3.UP * 0.08), motion):
		global_position += motion


## Owner: movement keys drive the machine. x = A/D, y = W (+1) / S (-1).
## Sent only when it changes (reliable), so holding a key costs nothing.
func _drive(machine: Node, input: Vector2) -> void:
	var v := Vector3(input.x, -input.y, 0.0).round()
	if v != _drive_sent:
		_drive_sent = v
		mission.send("drive", path_to(machine), "", v)


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
