class_name SalvageContract
extends Contract
## Blackwater Station's insurance salvage contract.
##   CONTRACT  the VFD power module (role primary)
##   JACKPOT   the pump motor (role optional)
##   BONUS     the pressure transmitters (role salvage)
## Salvage counts once it's secured at the DepositZone, at whatever condition
## it's in then. The run ends when the crew leaves in the truck (or when the
## station fails and the clock runs out). Partial extraction is the point:
## whatever is secured gets paid, minus a rescue fee for anyone left inside.

@export var station_name := "BLACKWATER STATION"
@export var deposit: DepositZone
@export var departure: TruckDeparture
@export var corridor: DamagedCorridor
## Extra water dumped into the station when it fails (flood level, m).
@export var failure_surge := 1.0
@export var flood_zone: FloodZone
## Charged per crew member left inside when the run ends.
@export var rescue_fee := 250
## Shown on screen until you first step inside the station.
@export_multiline var briefing_text := ""

var _entered := false


func _ready() -> void:
	super._ready()
	if deposit:
		deposit.secured.connect(_on_secured)


func money(amount: float) -> String:
	var n := roundi(amount)
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out + " cr"


func secured_tag() -> String:
	return "SECURED"


## The job, shown until you first step inside the station (then gone for
## good; [Tab] still shows the manifest).
func briefing() -> String:
	var me := mission.crew.local_member()
	if me and departure and not departure.contains(me.global_position):
		_entered = true
	if _entered:
		return ""
	return briefing_text


func controls_hint() -> String:
	return "WASD move · Shift sprint · Space jump/swim · E grab / use · LMB wrench or throw · R turn held item · Tab manifest · Esc menu"


func _salvage() -> Array[Prop]:
	var out: Array[Prop] = []
	for p in mission.props():
		if p.is_salvage():
			out.append(p)
	return out


func secured_value() -> float:
	var v := 0.0
	for p in _salvage():
		if p.secured:
			v += p.current_value
	return v


func status_text() -> String:
	var clock := mission.clock
	var lines := ["%s · %s left" % [station_name, MissionClock.format(clock.time_left())]]
	# Only what matters right now: rooms that aren't dry, a floor in danger.
	for g in get_tree().get_nodes_in_group("flood_gauges"):
		if g is FloodGauge and mission.is_ancestor_of(g) and g.state() > 0:
			lines.append("%s water: %s" % [g.room_name, g.state_name()])
	if corridor and (corridor.stress >= 50.0 or corridor.is_collapsed):
		lines.append("Weak floor: %s" % ("COLLAPSED" if corridor.is_collapsed else "%d%%" % roundi(corridor.stress)))
	return "\n".join(lines)


func objective_lines(expanded: bool) -> Array[String]:
	var lines: Array[String] = []
	var bonus_total := 0
	var bonus_got := 0
	var jackpot: Array[String] = []
	for p in _salvage():
		match p.role:
			"primary":
				lines.append("CONTRACT  %s  %s" % [p.display_name, _state(p)])
			"optional":
				jackpot.append("JACKPOT  %s  %s" % [p.display_name, _state(p)])
			"salvage":
				bonus_total += 1
				if p.secured:
					bonus_got += 1
	lines.append_array(jackpot)
	if bonus_total > 0:
		lines.append("BONUS  sensors  %d/%d" % [bonus_got, bonus_total])
	lines.append("Secured: %s" % money(secured_value()))
	if expanded:
		lines.append("")
		lines.append("— SALVAGE MANIFEST —")
		for p in _salvage():
			lines.append("%s  %d%%  %s  %s" % [p.display_name, ceili(p.condition), money(p.current_value), _where(p)])
	else:
		lines.append("[Tab] manifest")
	return lines


func _state(p: Prop) -> String:
	if p.secured:
		return "✔ %s" % money(p.current_value)
	return "— %d%%" % ceili(p.condition)


func _where(p: Prop) -> String:
	if p.secured:
		return "SECURED"
	if p.dormant:
		return "bolted"
	if p.submerged > 0.5:
		return "UNDERWATER"
	return "loose"


func banner() -> Array:
	if departure and departure.is_counting():
		return ["TRUCK LEAVES IN %d — GET TO THE YARD" % ceili(departure.timer), Color(0.4, 1.0, 0.6)]
	return ["", Color.WHITE]


func departing() -> bool:
	return departure != null and departure.is_counting()


func _on_secured(p: Prop) -> void:
	var lost := p.value - p.current_value
	var how := "intact" if lost < 1.0 else "%d%% condition" % ceili(p.condition)
	mission.incident_log.broadcast("Secured: %s — %s (%s)" % [p.display_name, money(p.current_value), how], "phase")


func on_collapse() -> void:
	if corridor:
		corridor.collapse()
	if flood_zone:
		flood_zone.add_water(failure_surge)


func results(collapsed: bool) -> Dictionary:
	var stamp := mission.clock.stamp()
	var incidents := mission.incident_log.incidents
	var value := 0.0
	var damage_lost := 0.0
	var cargo: Array[String] = []
	## display name -> [count, value]
	var missing := {}
	var primary := false
	var optional := false
	var bonus := 0
	var bonus_total := 0
	for p in _salvage():
		if p.role == "salvage":
			bonus_total += 1
		if p.secured:
			value += p.current_value
			damage_lost += p.value - p.current_value
			var dmg := "" if p.condition >= 99.5 else "  (−%s damage)" % money(p.value - p.current_value)
			cargo.append("%s  %d%%  %s%s" % [p.display_name, ceili(p.condition), money(p.current_value), dmg])
			match p.role:
				"primary": primary = true
				"optional": optional = true
				"salvage": bonus += 1
		else:
			var entry: Array = missing.get(p.display_name, [0, 0.0])
			missing[p.display_name] = [entry[0] + 1, entry[1] + p.value]
	var fees := 0
	for c in mission.crew.members():
		if departure and departure.contains(c.global_position) and not collapsed:
			continue
		fees += rescue_fee
		incidents.append("%s  %s %s" % [stamp, c.display_name,
			"was inside when the station failed" if collapsed else "was left behind when the truck left"])
	var payout := maxf(0.0, value - fees)
	var outcome := "NOTHING RECOVERED"
	if primary and optional:
		outcome = "CONTRACT COMPLETE + JACKPOT"
	elif primary:
		outcome = "CONTRACT COMPLETE"
	elif value > 0.0:
		outcome = "PARTIAL SALVAGE"
	var notes: Array[String] = []
	if damage_lost >= 1.0:
		notes.append("Lost to damage: %s" % money(damage_lost))
	if fees > 0:
		notes.append("Rescue fees: %s" % money(fees))
	if not missing.is_empty():
		var left: Array[String] = []
		for n in missing:
			left.append("%s%s (%s)" % ["%d× " % missing[n][0] if missing[n][0] > 1 else "", n, money(missing[n][1])])
		notes.append("Left in the station: " + ", ".join(left))
	return {
		"outcome": outcome,
		"outcome_color": {"CONTRACT COMPLETE + JACKPOT": "#5dff9a", "CONTRACT COMPLETE": "#9dff5d",
			"PARTIAL SALVAGE": "#ffd24d"}.get(outcome, "#ff6a55"),
		"subtitle": "The station failed before the truck left." if collapsed else "",
		"value_text": "Payout  %s" % money(payout),
		"duration": mission.clock.elapsed,
		"objectives": [["Contract: VFD power module", primary], ["Jackpot: pump motor", optional],
			["Bonus: pressure transmitters (%d/%d)" % [bonus, bonus_total], bonus > 0]],
		"cargo_title": "Secured salvage",
		"cargo": cargo,
		"notes": notes,
		"incidents": incidents,
	}
