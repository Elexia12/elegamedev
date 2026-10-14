class_name Breakable
extends StaticBody2D
## Cracked block. Only big-water moves (wave / slam) can smash it.
## Smashing one block breaks the whole connected cluster.

var cell := Vector2i.ZERO
var level: Level
var broken := false


func _ready() -> void:
	add_to_group("breakable")
	collision_layer = GameConst.LAYER_WORLD
	collision_mask = 0
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = Vector2(GameConst.TILE, GameConst.TILE)
	cs.shape = rs
	add_child(cs)


func smash() -> void:
	if broken:
		return
	if level:
		level.break_cluster(cell)
	else:
		break_now(0.0)


func break_now(delay: float) -> void:
	if broken:
		return
	broken = true
	remove_from_group("breakable")
	set_deferred("collision_layer", 0)
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func():
		Splash.spawn(get_parent(), global_position, Color(0.55, 0.47, 0.4), 8, 260.0, TAU))
	tw.tween_property(self, "modulate:a", 0.0, 0.1)
	tw.tween_callback(queue_free)


func _draw() -> void:
	var h := GameConst.TILE / 2.0
	var r := Rect2(-h, -h, h * 2, h * 2)
	draw_rect(r, Color(0.6, 0.53, 0.46))
	draw_rect(r.grow(-1), Color(0.42, 0.36, 0.31), false, 2.0)
	var crack := Color(0.3, 0.25, 0.22)
	draw_polyline(PackedVector2Array([Vector2(-h + 3, -6), Vector2(-3, -1), Vector2(2, -9), Vector2(h - 3, -4)]), crack, 1.5)
	draw_polyline(PackedVector2Array([Vector2(-3, -1), Vector2(-1, 7), Vector2(6, h - 3)]), crack, 1.5)
