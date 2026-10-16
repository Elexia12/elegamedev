extends CanvasLayer
## In-mission HUD for the local crew member. The layout is hud.tscn; this
## script only fills it in each frame from the Mission and the local
## CrewMember. Messages arrive through the IncidentLog signals connected to
## _on_message and _on_client_event in the level scene.

const FEED_LINES := 6
const KIND_COLORS := {
	"info": Color(0.85, 0.9, 1.0),
	"warn": Color(1.0, 0.8, 0.2),
	"alert": Color(1.0, 0.4, 0.3),
	"phase": Color(0.4, 1.0, 0.7),
}

var mission: Mission
var _toast_time := 0.0

@onready var status: Label = %Status
@onready var pressure_label: Label = %PressureLabel
@onready var pressure_bar: ProgressBar = %PressureBar
@onready var objectives: Label = %Objectives
@onready var feed: VBoxContainer = %Feed
@onready var feed_template: Label = %FeedTemplate
@onready var banner: Label = %Banner
@onready var prompt: Label = %Prompt
@onready var toast: Label = %Toast
@onready var breath_bar: ProgressBar = %BreathBar
@onready var knocked_label: Label = %KnockedLabel
@onready var tool_slots: Array[Node] = %ToolBar.get_children()


func _ready() -> void:
	mission = Mission.of(self)


func _process(delta: float) -> void:
	if mission == null or mission.clock == null:
		return
	var me := mission.crew.local_member()
	visible = me != null and mission.running()
	_update_mission_panel()
	_update_objectives()
	_update_banner()
	if me:
		_update_player(me, delta)


func _update_mission_panel() -> void:
	var clock := mission.clock
	status.text = "THE FLOODED REACTOR   ·   %s\nCollapse in %s\nWater: main hall %.1f m · storage %.1f m" % [
		clock.phase_name(), MissionClock.format(clock.time_left()),
		mission.get_node("%LowerFlood").level, mission.get_node("%BonusFlood").level]
	status.modulate = Color(1, 0.5, 0.4) if clock.phase() >= 3 else Color.WHITE
	var p := mission.pressure_network.pressure
	pressure_label.text = "PRESSURE %d%%" % roundi(p)
	pressure_bar.value = p
	pressure_bar.modulate = Color(0.4, 0.9, 1.0).lerp(Color(1.0, 0.2, 0.1), clampf((p - 60.0) / 40.0, 0.0, 1.0))


func _update_objectives() -> void:
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
	var toolkit := mission.toolkit
	lines.append("Salvage on lift: $%d" % roundi(salvage))
	lines.append("Braces left: %d   ·   Cables: %d/%d" % [toolkit.braces_left, toolkit.active_cable_count(), toolkit.cables().size()])
	objectives.text = "\n".join(lines)


func _update_banner() -> void:
	var network := mission.pressure_network
	if mission.extraction.is_counting():
		banner.text = "EXTRACTION IN %d — GET ON THE PAD" % ceili(mission.extraction.timer)
		banner.modulate = Color(0.4, 1.0, 0.6)
	elif network.burst_timer > 0.0:
		banner.text = "PRESSURE LINE BURST — MAIN HALL FLOODING"
		banner.modulate = Color(1.0, 0.4, 0.3)
	elif network.pressure > network.warning_level:
		banner.text = "OVERPRESSURE %d%% — OPEN THE DRAIN" % roundi(network.pressure)
		banner.modulate = Color(1.0, 0.7, 0.2)
	else:
		banner.text = ""


func _update_player(me: CrewMember, delta: float) -> void:
	for i in tool_slots.size():
		var label: Label = tool_slots[i].get_child(0)
		var has_tool := i < me.tools.size()
		tool_slots[i].visible = has_tool
		if has_tool:
			label.text = " %d  %s " % [i + 1, me.tools[i].display_name]
			label.modulate = me.tools[i].color if i == me.tool else Color(1, 1, 1, 0.45)
	var text := me.prompt()
	var winch := me.current_tool() as WinchTool
	if winch and winch.pending_hook:
		text += ("\n" if text != "" else "") + "Hook: %s — pick an anchor (RMB cancel)" % winch.pending_hook.describe()
	prompt.text = text
	_toast_time -= delta
	toast.visible = _toast_time > 0.0
	var vitals := me.vitals
	breath_bar.visible = vitals.breath < vitals.breath_max - 0.05 and not vitals.knocked
	breath_bar.value = vitals.breath / vitals.breath_max * 100.0
	knocked_label.visible = vitals.knocked


func _on_client_event(kind: String, text: String) -> void:
	if kind == "toast" and text != "":
		toast.text = text
		_toast_time = 3.5


func _on_message(text: String, kind: String) -> void:
	var line := feed_template.duplicate() as Label
	line.text = text
	line.modulate = KIND_COLORS.get(kind, Color.WHITE)
	line.visible = true
	feed.add_child(line)
	while feed.get_child_count() > FEED_LINES + 1:
		feed.get_child(1).free()  # child 0 is the hidden template
	var tw := line.create_tween()
	tw.tween_interval(10.0)
	tw.tween_property(line, "modulate:a", 0.0, 2.0)
	tw.tween_callback(line.queue_free)
