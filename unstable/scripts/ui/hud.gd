extends CanvasLayer
## In-mission HUD for the local crew member: mission clock and phase, pressure
## and water readouts, objectives, tool bar, aim prompt, toasts and the
## incident feed. Built in code; reads Mission + local CrewMember each frame.

const FEED_LINES := 6
const KIND_COLORS := {
	"info": Color(0.85, 0.9, 1.0),
	"warn": Color(1.0, 0.8, 0.2),
	"alert": Color(1.0, 0.4, 0.3),
	"phase": Color(0.4, 1.0, 0.7),
}

var mission: Mission
var _status: Label
var _pressure_bar: ProgressBar
var _pressure_label: Label
var _objectives: Label
var _prompt: Label
var _toast: Label
var _toast_time := 0.0
var _banner: Label
var _feed: VBoxContainer
var _tools: Array[Label] = []
var _breath: ProgressBar
var _knocked: Label


func _ready() -> void:
	mission = Mission.of(self)
	mission.message.connect(_on_message)
	mission.client_event.connect(func(kind: String, text: String) -> void:
		if kind == "toast" and text != "":
			_show_toast(text))
	_build()


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var cross := Label.new()
	cross.text = "+"
	cross.add_theme_font_size_override("font_size", 26)
	cross.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cross.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_place(cross, Control.PRESET_CENTER, Rect2(-20, -20, 40, 40))
	root.add_child(cross)

	# Top-left: mission status.
	var tl := _panel(root, Control.PRESET_TOP_LEFT, Vector2(16, 16))
	_status = _label(tl, 18)
	var row := HBoxContainer.new()
	tl.add_child(row)
	_pressure_label = _label(row, 16)
	_pressure_label.custom_minimum_size.x = 150
	_pressure_bar = ProgressBar.new()
	_pressure_bar.custom_minimum_size = Vector2(200, 18)
	_pressure_bar.show_percentage = false
	_pressure_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_pressure_bar)

	# Top-right: objectives.
	var tr := _panel(root, Control.PRESET_TOP_RIGHT, Vector2(-16, 16))
	_objectives = _label(tr, 16)

	# Feed under the objectives.
	_feed = VBoxContainer.new()
	_place(_feed, Control.PRESET_CENTER_RIGHT, Rect2(-560, -40, 540, 240))
	_feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	root.add_child(_feed)

	# Centre banner (phase / extraction countdown).
	_banner = _label(root, 30)
	_place(_banner, Control.PRESET_CENTER_TOP, Rect2(-500, 110, 1000, 50))
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Aim prompt and toast under the crosshair.
	_prompt = _label(root, 18)
	_place(_prompt, Control.PRESET_CENTER, Rect2(-450, 40, 900, 50))
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast = _label(root, 18)
	_place(_toast, Control.PRESET_CENTER, Rect2(-450, 95, 900, 30))
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.modulate = Color(1.0, 0.9, 0.5)

	_breath = ProgressBar.new()
	_place(_breath, Control.PRESET_CENTER, Rect2(-120, 140, 240, 14))
	_breath.show_percentage = false
	_breath.modulate = Color(0.5, 0.8, 1.0)
	root.add_child(_breath)

	_knocked = _label(root, 34)
	_place(_knocked, Control.PRESET_CENTER, Rect2(-400, -120, 800, 50))
	_knocked.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_knocked.modulate = Color(1.0, 0.4, 0.3)
	_knocked.text = "KNOCKED OUT — respawning at the lift"

	# Bottom: tool bar.
	var bar := HBoxContainer.new()
	_place(bar, Control.PRESET_CENTER_BOTTOM, Rect2(-300, -64, 600, 44))
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 12)
	root.add_child(bar)
	for i in 3:
		var slot := PanelContainer.new()
		bar.add_child(slot)
		var l := _label(slot, 18)
		l.text = " %d  %s " % [i + 1, CrewMember.TOOL_NAMES[i]]
		_tools.append(l)

	var help := _label(root, 13)
	_place(help, Control.PRESET_BOTTOM_LEFT, Rect2(16, -30, 1200, 20))
	help.modulate = Color(1, 1, 1, 0.55)
	help.text = "WASD move · Shift sprint · Space jump/swim · E grab/use · LMB/RMB tool · R detach/recover · 1-3/Q/wheel tools · Esc menu"


func _panel(parent: Control, preset: int, offset: Vector2) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN if offset.x < 0 else Control.GROW_DIRECTION_END
	_place(panel, preset, Rect2(offset, Vector2.ZERO))
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.09, 0.7)
	style.set_content_margin_all(10)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	return box


func _label(parent: Control, font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _process(delta: float) -> void:
	if mission == null:
		return
	var me := mission.local_player()
	visible = me != null and mission.running()

	_status.text = "THE FLOODED REACTOR   ·   %s\nCollapse in %s\nWater: main hall %.1f m · storage %.1f m" % [
		Mission.PHASES[mission.phase()], Mission.clock(mission.time_left()),
		mission.lower_flood.level, mission.bonus_flood.level]
	_status.modulate = Color(1, 0.5, 0.4) if mission.phase() >= 3 else Color.WHITE
	_pressure_label.text = "PRESSURE %d%%" % roundi(mission.pressure)
	_pressure_bar.value = mission.pressure
	_pressure_bar.modulate = Color(0.4, 0.9, 1.0).lerp(Color(1.0, 0.2, 0.1), clampf((mission.pressure - 60.0) / 40.0, 0.0, 1.0))

	var lines: Array[String] = []
	var salvage := 0.0
	for p in mission.props():
		match p.role:
			"primary":
				lines.append("PRIMARY  %s  %s" % [p.display_name, "✔ on lift" if p.secured else "—"])
			"optional":
				lines.append("OPTIONAL  %s ($%d)  %s" % [p.display_name, roundi(p.current_value), "✔ on lift" if p.secured else "—"])
			"salvage":
				if p.secured:
					salvage += p.current_value
	lines.append("Salvage on lift: $%d" % roundi(salvage))
	lines.append("Braces left: %d   ·   Cables: %d/%d" % [mission.braces_left,
		mission.cables().filter(func(c: Cable) -> bool: return c.active).size(), mission.cables().size()])
	_objectives.text = "\n".join(lines)

	if mission.extract_timer >= 0.0:
		_banner.text = "EXTRACTION IN %d — GET ON THE PAD" % ceili(mission.extract_timer)
		_banner.modulate = Color(0.4, 1.0, 0.6)
	elif mission.burst_timer > 0.0:
		_banner.text = "PRESSURE LINE BURST — MAIN HALL FLOODING"
		_banner.modulate = Color(1.0, 0.4, 0.3)
	elif mission.pressure > 85.0:
		_banner.text = "OVERPRESSURE %d%% — OPEN THE DRAIN" % roundi(mission.pressure)
		_banner.modulate = Color(1.0, 0.7, 0.2)
	else:
		_banner.text = ""

	if me == null:
		return
	for i in _tools.size():
		_tools[i].modulate = CrewMember.TOOL_COLORS[i] if i == me.tool else Color(1, 1, 1, 0.45)
	var prompt := me.prompt()
	if me.pending_hook and me.tool == CrewMember.Tool.WINCH:
		prompt += ("\n" if prompt != "" else "") + "Hook: %s — pick an anchor (RMB cancel)" % me.pending_hook.describe()
	_prompt.text = prompt
	_toast_time -= delta
	_toast.visible = _toast_time > 0.0
	_breath.visible = me.breath < me.breath_max - 0.05 and not me.knocked
	_breath.value = me.breath / me.breath_max * 100.0
	_knocked.visible = me.knocked


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast_time = 3.5


func _on_message(text: String, kind: String) -> void:
	var l := _label(_feed, 16)
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 540
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.modulate = KIND_COLORS.get(kind, Color.WHITE)
	while _feed.get_child_count() > FEED_LINES:
		_feed.get_child(0).free()
	var tw := l.create_tween()
	tw.tween_interval(10.0)
	tw.tween_property(l, "modulate:a", 0.0, 2.0)
	tw.tween_callback(l.queue_free)


## Anchor `c` to `preset` with offsets (relative to the anchor point) from `r`.
func _place(c: Control, preset: int, r: Rect2) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = r.position.x
	c.offset_top = r.position.y
	c.offset_right = r.end.x
	c.offset_bottom = r.end.y
