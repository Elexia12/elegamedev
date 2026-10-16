extends Node
## Session flow: menu -> (solo | host | join) -> mission -> results -> restart.
## The screens under UI are their own scenes and their buttons are wired to
## the handlers below in main.tscn. The host instantiates the mission under
## World, and MissionSpawner replicates it to clients, late joiners included.
## Command-line user args for testing: `-- --solo`, `-- --host`, `-- --join=IP`.

@export var mission_scene: PackedScene

var _mission_count := 0

@onready var world: Node3D = $World
@onready var menu: Control = %MainMenu
@onready var results: Control = %ResultsScreen
@onready var pause: Control = %PauseMenu


func _ready() -> void:
	Net.session_ended.connect(_on_session_ended)
	multiplayer.connected_to_server.connect(func() -> void: menu.set_status("Connected — waiting for the mission…"))
	for arg in OS.get_cmdline_user_args():
		if arg == "--solo":
			start_solo()
		elif arg == "--host":
			start_host()
		elif arg.begins_with("--join="):
			start_join(arg.trim_prefix("--join="))


func mission() -> Mission:
	for c in world.get_children():
		if c is Mission and not c.is_queued_for_deletion():
			return c
	return null


# --- Session -----------------------------------------------------------------

func start_solo() -> void:
	Net.solo()
	start_mission()


func start_host() -> void:
	var err := Net.host()
	if err != OK:
		menu.set_status("Could not host on port %d (error %d)" % [Net.DEFAULT_PORT, err])
		return
	start_mission()


func start_join(address: String) -> void:
	var err := Net.join(address)
	menu.set_status("Connecting to %s…" % address if err == OK else "Could not start connection (error %d)" % err)


## Host only: (re)start the mission. Freeing the old one despawns it everywhere.
func start_mission() -> void:
	for c in world.get_children():
		c.queue_free()
	_mission_count += 1
	var m := mission_scene.instantiate()
	m.name = "Mission%d" % _mission_count
	world.add_child(m, true)
	_on_mission_started()


## Also wired to MissionSpawner.spawned, so clients get here too.
func _on_mission_started(_node: Node = null) -> void:
	menu.visible = false
	results.visible = false
	pause.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func leave() -> void:
	Net.leave()
	_back_to_menu("")


func quit() -> void:
	get_tree().quit()


func _on_session_ended(reason: String) -> void:
	_back_to_menu(reason)


func _back_to_menu(status: String) -> void:
	for c in world.get_children():
		c.queue_free()
	menu.visible = true
	results.visible = false
	pause.visible = false
	menu.set_status(status)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# --- Results and pause ---------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func show_results(data: Dictionary) -> void:
	pause.visible = false
	results.show_results(data, multiplayer.is_server())
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func resume() -> void:
	pause.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if menu.visible or mission() == null:
		return
	if event.is_action_pressed("pause") and not results.visible:
		if pause.visible:
			resume()
		else:
			pause.open(multiplayer.is_server())
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and not pause.visible and not results.visible \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
