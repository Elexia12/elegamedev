class_name LevelTrigger
extends Area2D
## Small trigger objects placed by the level map:
## DEW (collectible), CHECKPOINT, SPIKES (hazard), GOAL (the Shiny Puddle).

enum Kind { DEW, CHECKPOINT, SPIKES, GOAL }

@export var kind: Kind = Kind.DEW

var active := false
var _t := 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_t = randf() * TAU
	if kind == Kind.DEW:
		add_to_group("dew")
	if kind == Kind.SPIKES:
		set_process(false)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _on_body_entered(body: Node) -> void:
	if not body is Droplet:
		return
	var player := body as Droplet
	match kind:
		Kind.DEW:
			get_tree().call_group("game", "on_dew_collected")
			Splash.spawn(get_parent(), global_position, Color(0.7, 1.0, 0.95), 10, 140.0, TAU, 0.0, 200.0)
			queue_free()
		Kind.CHECKPOINT:
			player.respawn_point = global_position
			if not active:
				active = true
				Splash.spawn(get_parent(), global_position + Vector2(0, -14), Color(0.5, 0.95, 1.0), 12, 180.0)
		Kind.SPIKES:
			player.hit_hazard.call_deferred()
		Kind.GOAL:
			if not active:
				active = true
				get_tree().call_group("game", "on_goal_reached")


func _draw() -> void:
	match kind:
		Kind.DEW: _draw_dew()
		Kind.CHECKPOINT: _draw_checkpoint()
		Kind.SPIKES: _draw_spikes()
		Kind.GOAL: _draw_goal()


func _draw_dew() -> void:
	var o := Vector2(0, sin(_t * 3.0) * 2.0)
	var pts := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16.0
		var p := Vector2(cos(a), sin(a)) * 5.5
		if p.y < 0.0:
			p.x *= 1.0 + p.y / 5.5  # pinch the top into a drop shape
			p.y *= 1.8
		pts.append(o + p + Vector2(0, 2))
	draw_colored_polygon(pts, Color(0.55, 0.95, 0.9, 0.9))
	draw_circle(o + Vector2(-1.5, 1), 1.5, Color.WHITE)


func _draw_checkpoint() -> void:
	var col := Color(0.4, 0.95, 1.0) if active else Color(0.6, 0.6, 0.6)
	draw_rect(Rect2(-1.5, -16, 3, 32), Color(0.45, 0.32, 0.2))
	var wave := sin(_t * 4.0) * 2.0 if active else 0.0
	draw_colored_polygon(PackedVector2Array([Vector2(1.5, -16), Vector2(16, -11 + wave), Vector2(1.5, -5)]), col)
	if active:
		draw_circle(Vector2(0, -16), 4.0 + sin(_t * 5.0), Color(col, 0.35))


func _draw_spikes() -> void:
	var t := GameConst.TILE
	var base := t / 2.0
	for i in 4:
		var x := -t / 2.0 + i * t / 4.0
		draw_colored_polygon(PackedVector2Array([Vector2(x, base), Vector2(x + t / 8.0, base - 14), Vector2(x + t / 4.0, base)]), Color(0.78, 0.8, 0.85))
		draw_line(Vector2(x + t / 8.0, base - 14), Vector2(x + t / 4.0, base), Color(0.5, 0.52, 0.58), 1.0)


func _draw_goal() -> void:
	# Light beam
	var beam := PackedVector2Array([Vector2(-22, 12), Vector2(-12, -90), Vector2(12, -90), Vector2(22, 12)])
	draw_colored_polygon(beam, Color(1.0, 1.0, 0.85, 0.12 + 0.05 * sin(_t * 2.0)))
	# Puddle
	draw_set_transform(Vector2(0, 12), 0.0, Vector2(1.0, 0.22))
	draw_circle(Vector2.ZERO, 30.0, Color(0.3, 0.85, 1.0, 0.9))
	draw_circle(Vector2(-6, -8), 18.0, Color(0.7, 1.0, 1.0, 0.8))
	draw_arc(Vector2.ZERO, 30.0, 0.0, TAU, 32, Color(1, 1, 1, 0.9), 2.0)
	var ph := fmod(_t * 0.7, 1.0)
	draw_arc(Vector2.ZERO, 6.0 + ph * 22.0, 0.0, TAU, 24, Color(1, 1, 1, 1.0 - ph), 1.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Sparkles
	for i in 5:
		var s := fmod(_t * 0.9 + i * 0.37, 1.0)
		var p := Vector2(sin(i * 12.9898) * 26.0, 6.0 - s * 50.0)
		var size := sin(s * PI) * 5.0
		var c := Color(1, 1, 0.8, sin(s * PI))
		draw_line(p - Vector2(size, 0), p + Vector2(size, 0), c, 1.5)
		draw_line(p - Vector2(0, size), p + Vector2(0, size), c, 1.5)
