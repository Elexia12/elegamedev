extends CanvasLayer
## In-mission HUD for the local crew member. The layout is hud.tscn; this
## script only fills it in each frame from the Mission's Contract (status,
## objectives, banner) and the local CrewMember. [Tab] expands the manifest.
## Messages arrive through the IncidentLog signals connected to _on_message
## and _on_client_event in the level scene.

const FEED_LINES := 6
const KIND_COLORS := {
	"info": Color(0.85, 0.9, 1.0),
	"warn": Color(1.0, 0.8, 0.2),
	"alert": Color(1.0, 0.4, 0.3),
	"phase": Color(0.4, 1.0, 0.7),
}

var mission: Mission
var _toast_time := 0.0
var _manifest_open := false

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
@onready var help: Label = %Help
@onready var briefing_panel: Control = %BriefingPanel
@onready var briefing: Label = %Briefing


func _ready() -> void:
	mission = Mission.of(self)
	# Mission's @onready refs aren't set yet (children are ready first).
	help.text = (mission.get_node("%Contract") as Contract).controls_hint()


func _process(delta: float) -> void:
	if mission == null or mission.clock == null:
		return
	var me := mission.crew.local_member()
	visible = me != null and mission.running()
	var contract := mission.contract
	status.text = contract.status_text()
	status.modulate = Color(1, 0.5, 0.4) if mission.clock.phase() >= 3 else Color.WHITE
	_update_pressure()
	objectives.text = "\n".join(contract.objective_lines(_manifest_open))
	var b := contract.banner()
	banner.text = b[0]
	banner.modulate = b[1]
	var brief := contract.briefing()
	briefing_panel.visible = brief != ""
	briefing.text = brief
	if me:
		_update_player(me, delta)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("manifest"):
		_manifest_open = not _manifest_open


func _update_pressure() -> void:
	var net := mission.pressure_network
	pressure_label.get_parent().visible = net != null
	if net == null:
		return
	var p := net.pressure
	pressure_label.text = "PRESSURE %d%%" % roundi(p)
	pressure_bar.value = p
	pressure_bar.modulate = Color(0.4, 0.9, 1.0).lerp(Color(1.0, 0.2, 0.1), clampf((p - 60.0) / 40.0, 0.0, 1.0))


func _update_player(me: CrewMember, delta: float) -> void:
	for i in tool_slots.size():
		var label: Label = tool_slots[i].get_child(0)
		var has_tool := i < me.tools.size()
		tool_slots[i].visible = has_tool
		if has_tool:
			label.text = " %d  %s " % [i + 1, me.tools[i].display_name]
			label.modulate = me.tools[i].color if i == me.tool else Color(1, 1, 1, 0.45)
	var text := me.prompt()
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
