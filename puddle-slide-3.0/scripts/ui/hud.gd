class_name Hud
extends CanvasLayer
## Health drops, current form + meter, dew counter, timer, control hints and the win screen.

const FORM_NAMES := ["Liquid", "Ice Cube", "Vapor", "Big Water"]
const FORM_COLORS := [Color(0.35, 0.72, 1.0), Color(0.78, 0.95, 1.0), Color(0.93, 0.96, 1.0), Color(0.2, 0.5, 0.95)]
const FORM_HINTS := [
	"A/D move  ·  Space jump  ·  hold toward a wall to cling, jump again to wall-jump",
	"J/X shoot ice cubes  ·  you slide on ice  ·  ice can stomp spiky urchins  ·  melts over time",
	"Gas rises on its own  ·  W/S rise or sink  ·  drift through vents  ·  J condense early",
	"J on ground: tidal wave  ·  J in air: ground slam  ·  every move costs mass",
]

var hp := 3
var max_hp := 3
var form := 0
var meter := 0.0
var dew := 0
var dew_total := 0
var elapsed := 0.0
var won := false

var _canvas := Control.new()


func _ready() -> void:
	layer = 10
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_on_draw)
	add_child(_canvas)


func _process(_delta: float) -> void:
	_canvas.queue_redraw()


func _on_draw() -> void:
	var font := ThemeDB.fallback_font
	var size := _canvas.size
	var c := _canvas

	# Panel
	c.draw_rect(Rect2(12, 12, 300, 92), Color(0, 0, 0, 0.35))
	# Health drops
	for i in max_hp:
		var p := Vector2(32 + i * 30, 36)
		var col := Color(0.35, 0.72, 1.0) if i < hp else Color(0.3, 0.3, 0.35, 0.6)
		c.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -12), p + Vector2(8, 2), p + Vector2(0, 10), p + Vector2(-8, 2)]), col)
		c.draw_circle(p + Vector2(0, 3), 8.0, col)
		if i < hp:
			c.draw_circle(p + Vector2(-3, 0), 2.0, Color.WHITE)
	# Dew + time
	c.draw_string(font, Vector2(130, 42), "Dew %d/%d" % [dew, dew_total], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.7, 1, 0.95))
	c.draw_string(font, Vector2(230, 42), _fmt_time(elapsed), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
	# Form + meter
	c.draw_string(font, Vector2(24, 76), FORM_NAMES[form], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, FORM_COLORS[form])
	if form != 0:
		var bar := Rect2(130, 63, 166, 14)
		c.draw_rect(bar, Color(0, 0, 0, 0.5))
		c.draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(meter, 0, 1), bar.size.y)), FORM_COLORS[form])
		c.draw_rect(bar, Color(1, 1, 1, 0.6), false, 1.0)
		var label := "mass" if form == 3 else "time"
		c.draw_string(font, Vector2(132, 95), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.7))

	# Hint bar
	c.draw_rect(Rect2(0, size.y - 34, size.x, 34), Color(0, 0, 0, 0.35))
	c.draw_string(font, Vector2(0, size.y - 12), FORM_HINTS[form] + "  ·  R restart",
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 16, Color(1, 1, 1, 0.85))

	if won:
		c.draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.1, 0.2, 0.55))
		var mid := size.y / 2.0
		c.draw_string(font, Vector2(0, mid - 40), "You found the Shiny Puddle!", HORIZONTAL_ALIGNMENT_CENTER, size.x, 44, Color(0.75, 1, 1))
		c.draw_string(font, Vector2(0, mid + 10), "Time %s   ·   Dew %d/%d" % [_fmt_time(elapsed), dew, dew_total],
				HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, Color.WHITE)
		c.draw_string(font, Vector2(0, mid + 50), "Press R to play again", HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, Color(1, 1, 1, 0.8))


func _fmt_time(t: float) -> String:
	return "%d:%05.2f" % [int(t / 60.0), fmod(t, 60.0)]
