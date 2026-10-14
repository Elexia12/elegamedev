class_name Modifier
extends Area2D
## Pickup that changes the droplet's physical state. Respawns after a short cooldown.

@export var kind: GameConst.Mod = GameConst.Mod.COLD
@export var respawn_time := 4.0
var _t := 0.0
var _cooldown := 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_t = randf() * TAU


func _process(delta: float) -> void:
	_t += delta
	_cooldown = maxf(_cooldown - delta, 0.0)
	queue_redraw()


func _on_body_entered(body: Node) -> void:
	if _cooldown > 0.0 or not body is Droplet:
		return
	body.apply_modifier.call_deferred(kind)  # changes collision shapes: not allowed mid-callback
	_cooldown = respawn_time
	Splash.spawn(get_parent(), global_position, _color(), 16, 200.0, TAU)


func _color() -> Color:
	match kind:
		GameConst.Mod.HOT: return Color(1.0, 0.5, 0.15)
		GameConst.Mod.SIZE: return Color(0.1, 0.6, 0.65)
	return Color(0.7, 0.92, 1.0)


func _draw() -> void:
	var a := 0.2 if _cooldown > 0.0 else 1.0
	var o := Vector2(0, sin(_t * 2.5) * 3.0)
	var c := _color()
	draw_circle(o, 15.0 + sin(_t * 4.0), Color(c, 0.25 * a))
	draw_circle(o, 12.0, Color(c.darkened(0.4), 0.85 * a))
	match kind:
		GameConst.Mod.COLD:  # snowflake
			for i in 3:
				var ang := _t * 0.6 + PI * i / 3.0
				var d := Vector2(cos(ang), sin(ang)) * 8.0
				draw_line(o - d, o + d, Color(1, 1, 1, a), 2.0)
			draw_circle(o, 2.5, Color(1, 1, 1, a))
		GameConst.Mod.HOT:  # flickering flame
			var f := 1.0 + sin(_t * 18.0) * 0.12
			draw_colored_polygon(PackedVector2Array([o + Vector2(-6, 6), o + Vector2(0, -10 * f), o + Vector2(6, 6)]), Color(1.0, 0.85, 0.2, a))
			draw_colored_polygon(PackedVector2Array([o + Vector2(-3, 6), o + Vector2(0, -3 * f), o + Vector2(3, 6)]), Color(1, 1, 0.8, a))
		GameConst.Mod.SIZE:  # pond with ripples
			for k in 2:
				var ph := fmod(_t * 0.8 + k * 0.5, 1.0)
				draw_set_transform(o + Vector2(0, 2), 0.0, Vector2(1.0, 0.45))
				draw_arc(Vector2.ZERO, 3.0 + ph * 8.0, 0.0, TAU, 20, Color(0.8, 1, 1, (1.0 - ph) * a), 1.5)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			draw_circle(o + Vector2(0, -3), 3.0, Color(0.7, 0.95, 1.0, a))
