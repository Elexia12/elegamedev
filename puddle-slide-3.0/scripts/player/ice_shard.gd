class_name IceShard
extends Area2D
## Mini ice cube fired by the ice form.

var velocity := Vector2.ZERO
var _life := 1.4
var _done := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = GameConst.LAYER_WORLD | GameConst.LAYER_ENEMY
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = Vector2(10, 10)
	cs.shape = rs
	add_child(cs)
	body_entered.connect(_on_body_entered)
	z_index = 3


func _physics_process(delta: float) -> void:
	velocity.y += 120.0 * delta
	position += velocity * delta
	rotation += 12.0 * delta * signf(velocity.x)
	_life -= delta
	if _life <= 0.0:
		_shatter()


func _on_body_entered(body: Node) -> void:
	if body is Enemy:
		body.die()
	_shatter()


func _shatter() -> void:
	if _done:
		return
	_done = true
	Splash.spawn(get_parent(), global_position, Droplet.COLOR_ICE, 8, 160.0, TAU)
	queue_free()


func _draw() -> void:
	var r := Rect2(-5, -5, 10, 10)
	draw_rect(r, Droplet.COLOR_ICE)
	draw_rect(r, Color.WHITE, false, 1.5)
	draw_rect(Rect2(-3, -3, 3, 2), Color.WHITE)
