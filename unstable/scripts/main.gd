extends Node
## Session flow: menu -> (solo | host | join) -> mission -> results -> restart.
## The host instantiates the mission under World; MissionSpawner replicates it
## to clients (including late joiners). Command-line user args for testing:
## `-- --solo`, `-- --host`, `-- --join=127.0.0.1`.

const MISSION_SCENE := preload("res://scenes/facility/flooded_reactor.tscn")

var _mission_count := 0
var _menu: Control
var _address: LineEdit
var _status: Label
var _results: Control
var _results_text: RichTextLabel
var _restart_button: Button
var _pause: Control
var _pause_restart: Button

@onready var world: Node3D = $World
@onready var spawner: MultiplayerSpawner = $MissionSpawner
@onready var ui: CanvasLayer = $UI


func _ready() -> void:
	_build_ui()
	Net.session_ended.connect(_on_session_ended)
	multiplayer.connected_to_server.connect(func() -> void: _status.text = "Connected — waiting for the mission…")
	spawner.spawned.connect(func(_n: Node) -> void: _on_mission_started())
	for arg in OS.get_cmdline_user_args():
		if arg == "--solo":
			_start_solo()
		elif arg == "--host":
			_start_host()
		elif arg.begins_with("--join="):
			_address.text = arg.trim_prefix("--join=")
			_start_join()


func mission() -> Mission:
	for c in world.get_children():
		if c is Mission and not c.is_queued_for_deletion():
			return c
	return null


# --- Session -----------------------------------------------------------------

func _start_solo() -> void:
	Net.solo()
	start_mission()


func _start_host() -> void:
	var err := Net.host()
	if err != OK:
		_status.text = "Could not host on port %d (error %d)" % [Net.DEFAULT_PORT, err]
		return
	start_mission()


func _start_join() -> void:
	var err := Net.join(_address.text.strip_edges())
	_status.text = "Connecting to %s…" % _address.text if err == OK else "Could not start connection (error %d)" % err


## Host only: (re)start the mission. Freeing the old one despawns it everywhere.
func start_mission() -> void:
	for c in world.get_children():
		c.queue_free()
	_mission_count += 1
	var m := MISSION_SCENE.instantiate()
	m.name = "Mission%d" % _mission_count
	world.add_child(m, true)
	_on_mission_started()


func _on_mission_started() -> void:
	_menu.visible = false
	_results.visible = false
	_pause.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _leave() -> void:
	Net.leave()
	for c in world.get_children():
		c.queue_free()
	_show_menu("")


func _on_session_ended(reason: String) -> void:
	for c in world.get_children():
		c.queue_free()
	_show_menu(reason)


func _show_menu(status: String) -> void:
	_menu.visible = true
	_results.visible = false
	_pause.visible = false
	_status.text = status
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# --- Results -----------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func show_results(data: Dictionary) -> void:
	_pause.visible = false
	_results.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var colors := {
		"FULL RECOVERY": "#5dff9a", "SUCCESSFUL RECOVERY": "#9dff5d",
		"PARTIAL RECOVERY": "#ffd24d", "FAILURE": "#ff6a55",
	}
	var t := "[center][font_size=40][color=%s]%s[/color][/font_size]\n" % [colors.get(data.outcome, "#ffffff"), data.outcome]
	if data.collapsed:
		t += "[color=#ff6a55]The facility collapsed before the lift left.[/color]\n"
	t += "\n[font_size=26]Cargo value  $%d[/font_size]\n" % data.value
	t += "Duration  %s[/center]\n\n" % Mission.clock(data.duration)
	t += "[b]Objectives[/b]\n"
	t += "  %s  Primary: reactor core\n" % ("✔" if data.primary else "✘")
	t += "  %s  Optional: bonus container\n" % ("✔" if data.optional else "✘")
	if not data.cargo.is_empty():
		t += "\n[b]Extracted[/b]\n  " + "\n  ".join(data.cargo) + "\n"
	t += "\n[b]Major incidents[/b]\n"
	t += ("  " + "\n  ".join(data.incidents)) if not data.incidents.is_empty() else "  None. Suspiciously competent."
	_results_text.text = t
	_restart_button.visible = multiplayer.is_server()
	_restart_button.text = "Try again"


# --- Input -------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _menu.visible or mission() == null:
		return
	if event.is_action_pressed("pause") and not _results.visible:
		_pause.visible = not _pause.visible
		_pause_restart.visible = multiplayer.is_server()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _pause.visible else Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and not _pause.visible and not _results.visible \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


# --- UI construction -----------------------------------------------------------

func _build_ui() -> void:
	# Main menu.
	_menu = _screen(Color(0.04, 0.05, 0.06, 1.0))
	var box := _card(_menu, 520)
	var title := Label.new()
	title.text = "UNSTABLE"
	title.add_theme_font_size_override("font_size", 64)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var tag := Label.new()
	tag.text = "The facility is collapsing. The cargo is worth a fortune.\nYour team is barely qualified."
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.modulate = Color(0.3, 0.8, 0.8)
	box.add_child(tag)
	box.add_child(HSeparator.new())
	_button(box, "Play solo", _start_solo)
	_button(box, "Host online game (port %d)" % Net.DEFAULT_PORT, _start_host)
	var join_row := HBoxContainer.new()
	box.add_child(join_row)
	_address = LineEdit.new()
	_address.text = "127.0.0.1"
	_address.placeholder_text = "Host IP address"
	_address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(_address)
	_button(join_row, "Join", _start_join)
	_button(box, "Quit", func() -> void: get_tree().quit())
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.modulate = Color(1.0, 0.8, 0.4)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	var help := Label.new()
	help.text = "Mission: THE FLOODED REACTOR — prototype build\nWinch [1] · Brace [2] · Pressure [3] · E grab/use · R detach/recover"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.modulate = Color(1, 1, 1, 0.5)
	box.add_child(help)

	# Results.
	_results = _screen(Color(0.0, 0.0, 0.0, 0.75))
	var rbox := _card(_results, 640)
	_results_text = RichTextLabel.new()
	_results_text.bbcode_enabled = true
	_results_text.fit_content = true
	_results_text.custom_minimum_size = Vector2(600, 200)
	rbox.add_child(_results_text)
	_restart_button = _button(rbox, "Try again", start_mission)
	_button(rbox, "Leave to menu", _leave)
	_results.visible = false

	# Pause.
	_pause = _screen(Color(0.0, 0.0, 0.0, 0.5))
	var pbox := _card(_pause, 360)
	var pl := Label.new()
	pl.text = "PAUSED (the facility isn't)"
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pbox.add_child(pl)
	_button(pbox, "Resume", func() -> void:
		_pause.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	_pause_restart = _button(pbox, "Restart mission", start_mission)
	_button(pbox, "Leave to menu", _leave)
	_pause.visible = false


func _screen(bg: Color) -> Control:
	var c := ColorRect.new()
	c.color = bg
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(c)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.add_child(center)
	return c


func _card(screen: Control, width: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.11, 0.13, 0.95)
	style.border_color = Color(0.95, 0.75, 0.1)
	style.border_width_top = 4
	style.set_content_margin_all(24)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size.x = width
	screen.get_child(0).add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	return box


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 40
	b.pressed.connect(cb)
	parent.add_child(b)
	return b
