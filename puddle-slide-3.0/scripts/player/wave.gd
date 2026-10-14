class_name Wave
extends Area2D
## Tidal wave thrown by the big (pond) form. Knocks out enemies and smashes breakable blocks.

var direction := 1
var height := 60.0
var speed := 420.0
var _life := 1.1
var _max_life := 1.1
var _done := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = GameConst.LAYER_WORLD | GameConst.LAYER_ENEMY
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = Vector2(34, height)
	cs.shape = rs
	add_child(cs)
	body_entered.connect(_on_body_entered)
	z_index = 3


func _physics_process(delta: float) -> void:
	position.x += direction * speed * delta
	_life -= delta
	if _life <= 0.0:
		_end()
	queue_redraw()


func _on_body_entered(body: Node) -> void:
	if body is Enemy:
		body.die()
	elif body is Breakable:
		body.smash()
		_end()
	else:
		_end()


func _end() -> void:
	if _done:
		return
	_done = true
	Splash.spawn(get_parent(), global_position, Droplet.COLOR_BIG, 18, 300.0)
	queue_free()


func _draw() -> void:
	var a := clampf(_life / _max_life, 0.0, 1.0) * 0.5 + 0.5
	var h := height
	var d := float(direction)
	# A curling crest leaning in the travel direction.
	var pts := PackedVector2Array([
		Vector2(-17 * d, h / 2),
		Vector2(-17 * d, h * 0.1),
		Vector2(-6 * d, -h * 0.35),
		Vector2(8 * d, -h / 2),
		Vector2(20 * d, -h * 0.38),
		Vector2(10 * d, -h * 0.3),
		Vector2(17 * d, h / 2),
	])
	if direction < 0:
		pts.reverse()
	draw_colored_polygon(pts, Color(Droplet.COLOR_BIG, 0.75 * a))
	var crest := PackedVector2Array([Vector2(-6 * d, -h * 0.35), Vector2(8 * d, -h / 2), Vector2(20 * d, -h * 0.38)])
	draw_polyline(crest, Color(1, 1, 1, 0.9 * a), 3.0, true)
	draw_circle(Vector2(14 * d, -h * 0.3), 3.0, Color(1, 1, 1, 0.8 * a))
