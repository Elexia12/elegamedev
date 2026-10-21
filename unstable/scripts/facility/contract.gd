class_name Contract
extends Node
## The rules of one level: what the crew is here for, what the HUD says about
## it, how the run can end and what the results screen shows. The Mission is
## generic and asks its %Contract child for all of this. Each level has its
## own Contract subclass (ReactorContract, SalvageContract).

var mission: Mission


func _ready() -> void:
	mission = Mission.of(self)


## Money as this level writes it.
func money(amount: float) -> String:
	return "$%d" % roundi(amount)


## Shown on a cargo label once it counts (e.g. "ON LIFT", "SECURED").
func secured_tag() -> String:
	return "SECURED"


## HUD, bottom left: the controls for this level's tools.
func controls_hint() -> String:
	return "WASD move · Shift sprint · Space jump/swim · E grab · LMB tool or throw · R turn held item / detach cable · 1-2/Q/wheel tools · Esc menu"


## HUD, centre left: a short briefing at the start ("" = hidden).
func briefing() -> String:
	return ""


## HUD, top left: level name, clock, the hazards worth watching.
func status_text() -> String:
	return ""


## HUD, top right. `expanded` while the player holds the manifest key.
func objective_lines(_expanded: bool) -> Array[String]:
	return []


## HUD, top centre: [text, colour], or ["", …] for nothing.
func banner() -> Array:
	return ["", Color.WHITE]


## True while the crew is leaving (the final collapse won't end the run early).
func departing() -> bool:
	return false


## Host: build the results screen data. `collapsed` if the facility came down
## before the crew left.
func results(_collapsed: bool) -> Dictionary:
	return {}


## Host: the facility is collapsing (clock ran out). Bring things down.
func on_collapse() -> void:
	pass
