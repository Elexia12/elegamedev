extends ColorRect
## End-of-run summary. The level's Contract builds the data (outcome, value,
## objectives, what was recovered, notes, major incidents); this screen only
## lays it out. Only the host gets the restart button.

signal restart_requested
signal leave_requested

@onready var text: RichTextLabel = %Text
@onready var restart_button: Button = %RestartButton


func show_results(data: Dictionary, can_restart: bool) -> void:
	var t := "[center][font_size=40][color=%s]%s[/color][/font_size]\n" % [data.get("outcome_color", "#ffffff"), data.outcome]
	if data.get("subtitle", "") != "":
		t += "[color=#ff6a55]%s[/color]\n" % data.subtitle
	t += "\n[font_size=26]%s[/font_size]\n" % data.value_text
	t += "Duration  %s[/center]\n\n" % MissionClock.format(data.duration)
	t += "[b]Objectives[/b]\n"
	for o in data.objectives:
		t += "  %s  %s\n" % ["✔" if o[1] else "✘", o[0]]
	if not data.cargo.is_empty():
		t += "\n[b]%s[/b]\n  " % data.get("cargo_title", "Recovered") + "\n  ".join(data.cargo) + "\n"
	if not data.get("notes", []).is_empty():
		t += "\n" + "\n".join(data.notes) + "\n"
	t += "\n[b]Major incidents[/b]\n"
	t += ("  " + "\n  ".join(data.incidents)) if not data.incidents.is_empty() else "  None. Suspiciously competent."
	text.text = t
	restart_button.visible = can_restart
	visible = true


func _on_restart_pressed() -> void:
	restart_requested.emit()


func _on_leave_pressed() -> void:
	leave_requested.emit()
