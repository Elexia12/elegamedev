extends Node2D
## Game root: sets up input, background, level, player and HUD; tracks dew, time and the win state.

const ACTIONS := {
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"jump": [KEY_SPACE, KEY_Z, KEY_K],
	"attack": [KEY_J, KEY_X],
	"restart": [KEY_R],
}
const JOY_BUTTONS := {
	"jump": JOY_BUTTON_A,
	"attack": JOY_BUTTON_X,
	"move_left": JOY_BUTTON_DPAD_LEFT,
	"move_right": JOY_BUTTON_DPAD_RIGHT,
	"move_up": JOY_BUTTON_DPAD_UP,
	"move_down": JOY_BUTTON_DPAD_DOWN,
	"restart": JOY_BUTTON_START,
}

var level: Level
var player: Droplet
var hud: Hud


func _ready() -> void:
	add_to_group("game")
	_setup_input()
	_make_background()

	level = Level.new()
	add_child(level)
	level.build()

	player = Droplet.new()
	player.position = level.player_start
	level.add_child(player)
	player.fall_limit = level.pixel_size.y + 200.0
	player.set_camera_limits(Rect2(Vector2.ZERO, level.pixel_size))

	hud = Hud.new()
	hud.dew_total = level.dew_count
	add_child(hud)
	player.hp_changed.connect(_on_hp_changed)
	player.form_changed.connect(func(f): hud.form = f)
	player.meter_changed.connect(func(r): hud.meter = r)


func _on_hp_changed(hp: int, max_hp: int) -> void:
	hud.hp = hp
	hud.max_hp = max_hp


func _process(delta: float) -> void:
	if not hud.won:
		hud.elapsed += delta
	if Input.is_action_just_pressed("restart"):
		get_tree().reload_current_scene()


func on_dew_collected() -> void:
	hud.dew += 1


func on_goal_reached() -> void:
	hud.won = true
	player.frozen = true


func _setup_input() -> void:
	for action: String in ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.3)
		for key: Key in ACTIONS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
		if JOY_BUTTONS.has(action):
			var jb := InputEventJoypadButton.new()
			jb.button_index = JOY_BUTTONS[action]
			InputMap.action_add_event(action, jb)
		var axis := {"move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0],
				"move_up": [JOY_AXIS_LEFT_Y, -1.0], "move_down": [JOY_AXIS_LEFT_Y, 1.0]}
		if axis.has(action):
			var jm := InputEventJoypadMotion.new()
			jm.axis = axis[action][0]
			jm.axis_value = axis[action][1]
			InputMap.action_add_event(action, jm)


func _make_background() -> void:
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -10
	add_child(bg_layer)
	var grad := Gradient.new()
	grad.set_color(0, Color(0.45, 0.72, 0.95))
	grad.set_color(1, Color(0.85, 0.95, 1.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	var rect := TextureRect.new()
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_layer.add_child(rect)

	var parallax := Parallax2D.new()
	parallax.scroll_scale = Vector2(0.35, 0.6)
	parallax.z_index = -5
	add_child(parallax)
	parallax.add_child(Backdrop.new())


class Backdrop extends Node2D:
	func _draw() -> void:
		# Distant hills and clouds.
		var hills := PackedVector2Array()
		for i in 81:
			var x := i * 40.0 - 200.0
			hills.append(Vector2(x, 420.0 - 60.0 * sin(x * 0.006) - 30.0 * sin(x * 0.017)))
		hills.append(Vector2(3000, 1200))
		hills.append(Vector2(-200, 1200))
		draw_colored_polygon(hills, Color(0.55, 0.78, 0.7, 0.6))
		for i in 10:
			var p := Vector2(i * 230.0 - 50.0, 80.0 + 50.0 * sin(i * 1.7))
			for k in 4:
				draw_circle(p + Vector2(k * 22.0, sin(k * 2.0) * 6.0), 20.0 + 6.0 * cos(k + i), Color(1, 1, 1, 0.7))
