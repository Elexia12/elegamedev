class_name Wave
extends Area2D
## Tidal wave thrown by the big (pond) form. Knocks out enemies and smashes breakable blocks.

@export var speed := 420.0
@export var lifetime := 1.1

var direction := 1
var height := 60.0
var _life := 0.0
var _done := false


func _ready() -> void:
	_life = lifetime
	($CollisionShape2D.shape as RectangleShape2D).size = Vector2(34, height)
	body_entered.connect(_on_body_entered)


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
	var a := clampf(_life / lifetime, 0.0, 1.0) * 0.5 + 0.5
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
