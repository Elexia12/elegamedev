extends Node2D
## Distant hills and clouds, drawn under a Parallax2D.

@export var hill_color := Color(0.55, 0.78, 0.7, 0.6)
@export var cloud_color := Color(1, 1, 1, 0.7)


func _draw() -> void:
	var hills := PackedVector2Array()
	for i in 81:
		var x := i * 40.0 - 200.0
		hills.append(Vector2(x, 420.0 - 60.0 * sin(x * 0.006) - 30.0 * sin(x * 0.017)))
	hills.append(Vector2(3000, 1200))
	hills.append(Vector2(-200, 1200))
	draw_colored_polygon(hills, hill_color)
	for i in 10:
		var p := Vector2(i * 230.0 - 50.0, 80.0 + 50.0 * sin(i * 1.7))
		for k in 4:
			draw_circle(p + Vector2(k * 22.0, sin(k * 2.0) * 6.0), 20.0 + 6.0 * cos(k + i), cloud_color)
