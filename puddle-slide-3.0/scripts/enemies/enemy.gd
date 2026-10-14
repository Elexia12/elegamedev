class_name Enemy
extends CharacterBody2D
## Generic enemies.
## WALKER: a sponge that patrols and turns at walls/ledges. Can be stomped.
## SPIKY:  an urchin. Stomping it hurts (unless you are ice) - shoot it instead.
## FLYER:  a dust moth hovering in a figure-eight. Can be stomped.

enum Kind { WALKER, SPIKY, FLYER }

var kind: Kind = Kind.WALKER
var dir := -1
var speed := 55.0
var radius := 13.0
var dead := false
var spiky: bool:
	get:
		return kind == Kind.SPIKY

var _origin := Vector2.ZERO
var _t := 0.0


func _ready() -> void:
	add_to_group("enemies")
	collision_layer = GameConst.LAYER_ENEMY
	collision_mask = GameConst.LAYER_WORLD | GameConst.LAYER_MESH
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = Vector2(24, 24)
	cs.shape = rs
	add_child(cs)
	_origin = global_position
	_t = randf() * TAU
	if kind == Kind.SPIKY:
		speed = 40.0


func _physics_process(delta: float) -> void:
	if dead:
		return
	_t += delta
	if kind == Kind.FLYER:
		var prev := global_position
		global_position = _origin + Vector2(sin(_t * 0.9) * 70.0, sin(_t * 1.8) * 16.0)
		dir = 1 if global_position.x >= prev.x else -1
	else:
		velocity.y += 1200.0 * delta
		velocity.x = dir * speed
		move_and_slide()
		if is_on_wall() or (is_on_floor() and not _ground_ahead()):
			dir = -dir
	_check_player()
	queue_redraw()


func _ground_ahead() -> bool:
	var q := PhysicsPointQueryParameters2D.new()
	q.position = global_position + Vector2(dir * 14.0, 16.0)
	q.collision_mask = GameConst.LAYER_WORLD | GameConst.LAYER_MESH
	return not get_world_2d().direct_space_state.intersect_point(q, 1).is_empty()


func _check_player() -> void:
	var player := get_tree().get_first_node_in_group("player") as Droplet
	if player and global_position.distance_to(player.global_position) < radius + player.radius:
		player.touch_enemy(self)


func die() -> void:
	if dead:
		return
	dead = true
	remove_from_group("enemies")
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	Splash.spawn(get_parent(), global_position, _main_color(), 14, 240.0, TAU)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(1.5, 0.15), 0.12)
	tw.tween_callback(queue_free)


func _main_color() -> Color:
	match kind:
		Kind.SPIKY: return Color(0.55, 0.25, 0.65)
		Kind.FLYER: return Color(0.6, 0.58, 0.55)
	return Color(0.98, 0.82, 0.3)


func _draw() -> void:
	match kind:
		Kind.WALKER: _draw_sponge()
		Kind.SPIKY: _draw_urchin()
		Kind.FLYER: _draw_moth()


func _draw_eyes(center: Vector2, angry := false) -> void:
	for side in [-1, 1]:
		var p: Vector2 = center + Vector2(side * 4.5 + dir * 2.0, 0)
		draw_circle(p, 3.2, Color.WHITE)
		draw_circle(p + Vector2(dir * 1.2, 0.5), 1.6, Color(0.1, 0.05, 0.1))
		if angry:
			draw_line(p + Vector2(-3 * side, -5), p + Vector2(3 * side, -3), Color(0.1, 0.05, 0.1), 1.5)


func _draw_sponge() -> void:
	var bob := absf(sin(_t * 8.0)) * 1.5
	var body := Rect2(-12, -12 + bob, 24, 23 - bob)
	draw_rect(body, _main_color())
	draw_rect(body, Color(0.75, 0.55, 0.15), false, 2.0)
	for h in [Vector2(-7, -6), Vector2(6, -8), Vector2(-3, 6), Vector2(8, 4), Vector2(-9, 2)]:
		draw_circle(h + Vector2(0, bob), 1.8, Color(0.85, 0.62, 0.18))
	_draw_eyes(Vector2(0, -2 + bob))
	# little feet
	var step := sin(_t * 10.0) * 3.0
	draw_rect(Rect2(-9 + step, 10, 6, 3), Color(0.5, 0.35, 0.1))
	draw_rect(Rect2(3 - step, 10, 6, 3), Color(0.5, 0.35, 0.1))


func _draw_urchin() -> void:
	var c := _main_color()
	var spin := _t * 0.8 * dir
	for i in 10:
		var a := spin + TAU * i / 10.0
		var tip := Vector2(cos(a), sin(a)) * 17.0
		var l := Vector2(cos(a - 0.25), sin(a - 0.25)) * 9.0
		var r := Vector2(cos(a + 0.25), sin(a + 0.25)) * 9.0
		draw_colored_polygon(PackedVector2Array([l, tip, r]), c.darkened(0.3))
	draw_circle(Vector2.ZERO, 10.5, c)
	_draw_eyes(Vector2(0, -1), true)


func _draw_moth() -> void:
	var flap := absf(sin(_t * 14.0))
	var wing := Color(0.78, 0.76, 0.72, 0.9)
	for side in [-1, 1]:
		var pts := PackedVector2Array([Vector2(0, -2), Vector2(side * 16, -12 * flap - 2), Vector2(side * 13, 4)])
		draw_colored_polygon(pts, wing)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 1.25))
	draw_circle(Vector2.ZERO, 8.0, _main_color())
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_eyes(Vector2(0, -2))
