extends SceneTree
## Headless smoke test: godot --headless --path . -s res://tests/playtest.gd

var main: Node
var p: Droplet
var frame := 0
var step := 0.0
var log_lines: Array[String] = []


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _t(cx: float, cy: float) -> Vector2:
	return (Vector2(cx, cy) + Vector2(0.5, 0.5)) * GameConst.TILE


func _press(a: String, on := true) -> void:
	if on:
		Input.action_press(a)
	else:
		Input.action_release(a)


func _release_all() -> void:
	for a in ["move_left", "move_right", "move_up", "move_down", "jump", "attack"]:
		Input.action_release(a)


func _physics_process(_delta: float) -> bool:
	frame += 1
	if p == null:
		p = main.player
	match frame:
		5:
			print("start pos ", p.global_position, " on_floor ", p.is_on_floor())
		30:
			print("settled pos ", p.global_position, " on_floor ", p.is_on_floor())
			_press("jump")
			step = p.global_position.y
		31:
			pass
		70:
			_press("jump", false)
			print("jump apex approx min y recorded")
		# --- Ice: go to cold modifier and shoot spiky enemies in tunnel
		100:
			p._teleport(_t(40, 16))
		120:
			print("form after cold pickup: ", p.form, " (1=ICE)")
			p._teleport(_t(46, 16))
			p.facing = 1
		125, 145, 165, 185, 205, 225, 245, 265:
			_press("attack")
		126, 146, 166, 186, 206, 226, 246, 266:
			_press("attack", false)
		300:
			print("enemies left in tunnel: ", _enemies_between(45, 63))
		# --- Vapor: hot modifier then rise through mesh
		310:
			p._teleport(_t(69, 16))
		330:
			print("form after hot pickup: ", p.form, " (2=VAPOR)")
			p._teleport(_t(77, 15))
		420:
			print("vapor pos after rising: ", p.global_position, " (mesh at y ", 9 * 32, "..", 11 * 32, ")")
		500:
			_press("move_right")
		560:
			_press("move_right", false)
		800:
			print("after condense form ", p.form, " pos ", p.global_position, " on_floor ", p.is_on_floor())
		# --- Big: size modifier, wave on wall, slam on floor
		820:
			p._teleport(_t(101, 16))
		840:
			print("form after size pickup: ", p.form, " (3=BIG) mass ", p.mass, " radius ", p.radius)
			p._teleport(_t(104, 15))
			p.facing = 1
		860:
			_press("attack")
		861:
			_press("attack", false)
		920:
			print("breakables left: ", get_nodes_in_group("breakable").size(), " mass ", p.mass)
			p._teleport(_t(120.5, 14))
		922:
			_press("attack")
		923:
			_press("attack", false)
		1000:
			print("after slam: breakables left ", get_nodes_in_group("breakable").size(), " mass ", p.mass, " pos ", p.global_position)
			p._teleport(_t(129, 21))
			_press("move_right")
		1300:
			_release_all()
			print("final pos ", p.global_position, " hp ", p.hp, " won ", main.hud.won, " dew ", main.hud.dew)
			quit()
	if frame > 30 and frame < 100 and p.global_position.y < step:
		step = p.global_position.y
	if frame == 99:
		print("jump height px: ", _t(3, 16).y - step)
	return false


func _enemies_between(c0: int, c1: int) -> int:
	var n := 0
	for e in get_nodes_in_group("enemies"):
		if e.global_position.x > c0 * 32 and e.global_position.x < c1 * 32:
			n += 1
	return n
