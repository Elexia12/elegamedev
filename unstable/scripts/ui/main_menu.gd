extends ColorRect
## Title screen. It only reports what the player chose; Main (connected in
## main.tscn) does the networking.

signal solo_requested
signal host_requested
signal join_requested(address: String)
signal quit_requested

@onready var address: LineEdit = %Address
@onready var status: Label = %Status
@onready var host_button: Button = %HostButton


func _ready() -> void:
	host_button.text = "Host online game (port %d)" % Net.DEFAULT_PORT


func set_status(text: String) -> void:
	status.text = text


func _on_solo_pressed() -> void:
	solo_requested.emit()


func _on_host_pressed() -> void:
	host_requested.emit()


func _on_join_pressed() -> void:
	join_requested.emit(address.text.strip_edges())


func _on_quit_pressed() -> void:
	quit_requested.emit()
