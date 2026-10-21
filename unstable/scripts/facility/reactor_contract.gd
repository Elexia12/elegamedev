class_name ReactorContract
extends Contract
## The Flooded Reactor: get the reactor core (primary) and the bonus container
## (optional) onto the lift, then ride it out before the facility collapses.
## Cargo counts if it's physically on the lift deck when it reaches the top.

@export var lower_flood: FloodZone
@export var storage_flood: FloodZone


func secured_tag() -> String:
	return "ON LIFT"


func status_text() -> String:
	var clock := mission.clock
	return "THE FLOODED REACTOR   ·   %s\nCollapse in %s\nWater: main hall %.1f m · storage %.1f m" % [
		clock.phase_name(), MissionClock.format(clock.time_left()),
		lower_flood.level if lower_flood else 0.0, storage_flood.level if storage_flood else 0.0]


func objective_lines(_expanded: bool) -> Array[String]:
	var lines: Array[String] = []
	var salvage := 0.0
	for p in mission.props():
		match p.role:
			"primary":
				lines.append("PRIMARY  %s  %s" % [p.display_name, "✔ on lift" if p.secured else "—"])
			"optional":
				lines.append("OPTIONAL  %s (%s)  %s" % [p.display_name, money(p.current_value), "✔ on lift" if p.secured else "—"])
			"salvage":
				if p.secured:
					salvage += p.current_value
	lines.append("Salvage on lift: %s" % money(salvage))
	var toolkit := mission.toolkit
	if toolkit:
		lines.append("Winch cables rigged: %d/%d" % [toolkit.active_cable_count(), toolkit.cables().size()])
	return lines


func banner() -> Array:
	var lift := mission.extraction
	if lift.is_counting():
		return ["LIFT IN %d — GET ON THE PAD" % ceili(lift.timer), Color(0.4, 1.0, 0.6)]
	if lift.is_rising():
		return ["LIFT RISING — HOLD ON", Color(0.4, 1.0, 0.6)]
	return ["", Color.WHITE]


func departing() -> bool:
	return mission.extraction.is_rising()


func results(collapsed: bool) -> Dictionary:
	var stamp := mission.clock.stamp()
	var incidents := mission.incident_log.incidents
	var value := 0.0
	var primary := false
	var optional := false
	var cargo_lines: Array[String] = []
	for p in mission.props():
		if p.role == "debris":
			continue
		var got := p.secured and not collapsed
		if got:
			value += p.current_value
			cargo_lines.append("%s  %s" % [p.display_name, money(p.current_value)])
		if p.role == "primary":
			primary = got
		elif p.role == "optional":
			optional = got
	for c in mission.crew.members():
		if collapsed:
			incidents.append("%s  %s was inside when the facility collapsed" % [stamp, c.display_name])
		elif not mission.extraction.contains(c.global_position):
			incidents.append("%s  %s was left behind" % [stamp, c.display_name])
	var outcome := "FAILURE"
	if primary and optional:
		outcome = "FULL RECOVERY"
	elif primary:
		outcome = "SUCCESSFUL RECOVERY"
	elif value > 0.0:
		outcome = "PARTIAL RECOVERY"
	return {
		"outcome": outcome,
		"outcome_color": {"FULL RECOVERY": "#5dff9a", "SUCCESSFUL RECOVERY": "#9dff5d",
			"PARTIAL RECOVERY": "#ffd24d"}.get(outcome, "#ff6a55"),
		"subtitle": "The facility collapsed before the lift left." if collapsed else "",
		"value_text": "Cargo value  %s" % money(value),
		"duration": mission.clock.elapsed,
		"objectives": [["Primary: reactor core", primary], ["Optional: bonus container", optional]],
		"cargo_title": "Extracted",
		"cargo": cargo_lines,
		"notes": [],
		"incidents": incidents,
	}
