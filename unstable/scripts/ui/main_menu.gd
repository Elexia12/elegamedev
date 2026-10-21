extends ColorRect
## Title screen. It only reports what the player chose; Main (connected in
## main.tscn) does the networking and starts the chosen mission.

signal solo_requested
signal host_requested
signal join_requested(address: String)
signal quit_requested
signal mission_selected(index: int)

## Controls shown under the buttons, one entry per mission (same order as Main.missions).
@export var mission_help: PackedStringArray = []

@onready var address: LineEdit = %Address
@onready var status: Label = %Status
@onready var host_button: Button = %HostButton
@onready var mission_select: OptionButton = %MissionSelect
@onready var help: Label = %Help


func _ready() -> void:
	host_button.text = "Host online game (port %d)" % Net.DEFAULT_PORT


func set_missions(names: PackedStringArray) -> void:
	mission_select.clear()
	for n in names:
		mission_select.add_item(n)
	mission_select.select(0)
	_show_help(0)


func set_status(text: String) -> void:
	status.text = text


func _show_help(index: int) -> void:
	help.text = mission_help[index] if index < mission_help.size() else ""


func _on_mission_selected(index: int) -> void:
	_show_help(index)
	mission_selected.emit(index)


func _on_solo_pressed() -> void:
	solo_requested.emit()


func _on_host_pressed() -> void:
	host_requested.emit()


func _on_join_pressed() -> void:
	join_requested.emit(address.text.strip_edges())


func _on_quit_pressed() -> void:
	quit_requested.emit()
