extends ColorRect
## Esc menu. The game keeps running underneath: it's online and the facility
## doesn't wait.

signal resume_requested
signal restart_requested
signal leave_requested

@onready var restart_button: Button = %RestartButton


func open(can_restart: bool) -> void:
	restart_button.visible = can_restart
	visible = true


func _on_resume_pressed() -> void:
	resume_requested.emit()


func _on_restart_pressed() -> void:
	restart_requested.emit()


func _on_leave_pressed() -> void:
	leave_requested.emit()
