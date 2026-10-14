class_name Splash
extends Node2D
## Short-lived droplet particles (splashes, ice chips, steam, debris).

var color := Color.WHITE
var gravity := 900.0
var _parts: Array[Dictionary] = []


static func spawn(parent: Node, pos: Vector2, col: Color, count := 10, speed := 220.0,
		spread := PI * 0.9, dir := -PI / 2.0, grav := 900.0) -> Splash:
	var s := Splash.new()
	s.color = col
	s.gravity = grav
	s.z_index = 5
	for i in count:
		var a := dir + randf_range(-spread, spread) * 0.5
		var life := randf_range(0.35, 0.75)
		s._parts.append({
			"p": Vector2.ZERO,
			"v": Vector2(cos(a), sin(a)) * speed * randf_range(0.35, 1.0),
			"r": randf_range(1.5, 3.5),
			"life": life,
			"max": life,
		})
	parent.add_child(s)
	s.global_position = pos
	return s


func _process(delta: float) -> void:
	for p in _parts:
		p.v.y += gravity * delta
		p.p += p.v * delta
		p.life -= delta
	_parts = _parts.filter(func(p): return p.life > 0.0)
	if _parts.is_empty():
		queue_free()
	queue_redraw()


func _draw() -> void:
	for p in _parts:
		var c := color
		c.a *= clampf(p.life / p.max, 0.0, 1.0)
		draw_circle(p.p, p.r, c)
