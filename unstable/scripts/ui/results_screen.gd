extends ColorRect
## End-of-run summary: outcome, cargo value, objectives, extracted cargo,
## major incidents. Only the host gets the restart button.

signal restart_requested
signal leave_requested

const OUTCOME_COLORS := {
	"FULL RECOVERY": "#5dff9a",
	"SUCCESSFUL RECOVERY": "#9dff5d",
	"PARTIAL RECOVERY": "#ffd24d",
	"FAILURE": "#ff6a55",
}

@onready var text: RichTextLabel = %Text
@onready var restart_button: Button = %RestartButton


func show_results(data: Dictionary, can_restart: bool) -> void:
	var t := "[center][font_size=40][color=%s]%s[/color][/font_size]\n" % [OUTCOME_COLORS.get(data.outcome, "#ffffff"), data.outcome]
	if data.collapsed:
		t += "[color=#ff6a55]The facility collapsed before the lift left.[/color]\n"
	t += "\n[font_size=26]Cargo value  $%d[/font_size]\n" % data.value
	t += "Duration  %s[/center]\n\n" % MissionClock.format(data.duration)
	t += "[b]Objectives[/b]\n"
	t += "  %s  Primary: reactor core\n" % ("✔" if data.primary else "✘")
	t += "  %s  Optional: bonus container\n" % ("✔" if data.optional else "✘")
	if not data.cargo.is_empty():
		t += "\n[b]Extracted[/b]\n  " + "\n  ".join(data.cargo) + "\n"
	t += "\n[b]Major incidents[/b]\n"
	t += ("  " + "\n  ".join(data.incidents)) if not data.incidents.is_empty() else "  None. Suspiciously competent."
	text.text = t
	restart_button.visible = can_restart
	visible = true


func _on_restart_pressed() -> void:
	restart_requested.emit()


func _on_leave_pressed() -> void:
	leave_requested.emit()
