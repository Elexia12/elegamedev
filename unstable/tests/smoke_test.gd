extends SceneTree
## Headless gameplay smoke test (solo, host-authoritative path):
##   godot --headless --path . --fixed-fps 60 -s res://tests/smoke_test.gd
## Drives the Mission request API directly, the same entry point players use.

var main: Node
var m: Mission
var p: CrewMember
var p2: CrewMember
var frame := 0
var fails := 0
var mark := Vector3.ZERO
var steps: Array = []


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	# [frame, callable] — frames at 60 Hz.
	steps = [
		[2, func() -> void: main.start_solo()],
		[10, _check_spawn],
		# 1) One crew member can't drag the 300 kg core alone.
		[12, func() -> void: _grab(Vector3(-9, 0.05, -8.2), "Cargo/ReactorCore", Vector3(0, 0, 0.8), 2.2)],
		[13, func() -> void: mark = _node("Cargo/ReactorCore").global_position],
		[200, func() -> void:
			var moved: float = _node("Cargo/ReactorCore").global_position.distance_to(mark)
			_check(moved < 0.6, "solo crew can't drag the reactor core (moved %.2f m)" % moved)
			_req("hold", "")],
		# 1b) ...two crew members together can.
		[202, func() -> void:
			m.crew.add_member(99)
			p2 = m.crew.member(99)
			_grab(Vector3(-9.4, 0.05, -8.2), "Cargo/ReactorCore", Vector3(-0.4, 0, 0.8), 2.2)
			p2.global_position = Vector3(-8.6, 0.05, -8.2)
			p2.rotation = Vector3.ZERO
			p2.head.rotation = Vector3(-0.35, 0, 0)
			p2.set_hold("grab", "Cargo/ReactorCore", Vector3(0.4, 0, 0.8), 2.2)
			mark = _node("Cargo/ReactorCore").global_position],
		[380, func() -> void:
			var moved: float = _node("Cargo/ReactorCore").global_position.distance_to(mark)
			_check(moved > 0.5, "two crew members can drag the reactor core (moved %.2f m)" % moved)
			_req("hold", "")
			p2.set_hold("", "", Vector3.ZERO, 0.0)
			m.crew.remove_member(99)],
		# 2) ...but can carry/drag the 70 kg bonus container.
		[390, func() -> void: _grab(Vector3(11, 0.05, -9.8), "Cargo/BonusContainer", Vector3(0, 0, 0.5), 1.8)],
		[391, func() -> void: mark = _node("Cargo/BonusContainer").global_position],
			[560, func() -> void:
			var moved: float = _node("Cargo/BonusContainer").global_position.distance_to(mark)
			_check(moved > 1.0, "solo crew can drag the bonus container (moved %.2f m)" % moved)
			_req("hold", "")],
		# 3) Pressure + jack valve opens the gate; brace holds it when pressure is cut.
		[610, func() -> void:
			m.pressure_network.pressure = 95.0
			_req("valve", "Manifold/JackValve/Point", "", Vector3(1, 0, 0))],
		[800, func() -> void:
			var g := _node("Gate") as Gate
			_check(g.height > 1.7, "jack lifts the gate (h=%.2f, pressure=%.0f)" % [g.height, m.pressure_network.pressure])
			p.global_position = Vector3(-10.4, 0.05, -2.0)],
		[802, func() -> void: _req("brace_place", "Gate/BraceSocket/Point")],
		[804, func() -> void:
			_check((_node("Gate/BraceSocket") as BraceSocket).braced, "brace placed under the gate (braces left %d)" % m.toolkit.braces_left)
			_req("valve", "Manifold/JackValve/Point", "", Vector3(-1, 0, 0))
			m.pressure_network.pressure = 20.0],
		[1000, func() -> void:
			var g := _node("Gate") as Gate
			_check(g.height > 1.6, "brace holds the gate open after jack is closed (h=%.2f)" % g.height)],
		# 4) Winch the core out through the gate to the hall bollard.
		[1010, func() -> void:
			p.global_position = Vector3(-10, 0.05, 2.5)
			mark = _node("Cargo/ReactorCore").global_position],
		[1012, func() -> void: _req("winch_attach", "Cargo/ReactorCore/HookSouth", "Anchors/AnchorHall/Point")],
		[1014, func() -> void:
			_check(m.toolkit.cable_at(_node("Anchors/AnchorHall/Point")) != null, "winch cable attached core -> hall bollard")
			_req("hold", "reel", "Anchors/AnchorHall/Point", Vector3(1, 0, 0))],
		[2000, func() -> void:
			var core := _node("Cargo/ReactorCore") as Prop
			var c := m.toolkit.cable_at(_node("Anchors/AnchorHall/Point"))
			_check(core.global_position.z > -3.0, "winch dragged the core through the gate (z %.1f -> %.1f, tension %.0f N)" % [mark.z, core.global_position.z, c.tension if c else -1.0])
			_req("hold", "")
			_req("winch_detach", "Anchors/AnchorHall/Point")],
		# 5) Gantry strut failure drops the beam.
		[2010, func() -> void: (_node("Supports/SupportGantry") as Support)._fail()],
		[2200, func() -> void:
			var beam := _node("GantryBeam") as Prop
			_check(not beam.freeze and beam.global_position.y < 4.0, "gantry beam fell after strut failure (y=%.2f — it may land on cargo)" % beam.global_position.y)],
		# 6) Overpressure bursts a line and floods the hall.
		[2210, func() -> void:
			mark.y = m.get_node("%LowerFlood").level
			m.pressure_network.pressure = 100.0],
		[2600, func() -> void:
			_check(m.pressure_network.burst_timer > 0.0 and m.get_node("%LowerFlood").level > mark.y + 0.05,
				"overpressure burst floods the hall (%.2f -> %.2f m)" % [mark.y, m.get_node("%LowerFlood").level])],
		# 7) Drain pump empties storage into the hall and bleeds pressure.
		[2610, func() -> void:
			mark = Vector3(m.get_node("%BonusFlood").level, m.get_node("%LowerFlood").level, m.pressure_network.pressure)
			_req("valve", "Manifold/DrainValve/Point", "", Vector3(1, 0, 0))],
		[2900, func() -> void:
			_check(m.get_node("%BonusFlood").level < mark.x, "drain lowers storage water (%.2f -> %.2f)" % [mark.x, m.get_node("%BonusFlood").level])],
		# 8) Extraction: core + container on the pad, crew on the pad, lever.
		[2910, func() -> void:
			for n in ["Cargo/ReactorCore", "Cargo/BonusContainer"]:
				var b := _node(n) as Prop
				b.global_position = Vector3(-2.0 if n == "Cargo/ReactorCore" else 2.5, 1.0, 9.0)
				b.linear_velocity = Vector3.ZERO
			p.global_position = Vector3(4.0, 0.05, 9.0)],
		[2960, func() -> void: _req("lever", "Extraction/ExtractionLever/Point")],
		[2970, func() -> void: _check(m.extraction.timer > 0.0, "extraction countdown started")],
		[3500, func() -> void:
			_check(main.results.visible, "results screen shown")
			var txt: String = main.results.text.text
			_check(txt.contains("FULL RECOVERY"), "outcome is FULL RECOVERY")
			print("--- results ---\n", txt.substr(0, 900))],
		# 9) Restart produces a fresh mission.
		[3510, func() -> void: main.start_mission()],
		[3530, func() -> void:
			var fresh: Mission = main.mission()
			_check(fresh != null and fresh != m and fresh.running(), "restart spawns a fresh mission (%s)" % (fresh.name if fresh else "none"))],
	]


func _check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1


func _node(path: String) -> Node:
	return m.get_node(path)


func _req(action: String, a := "", b := "", v := Vector3.ZERO, f := 0.0) -> void:
	m.request(action, a, b, v, f)


func _check_spawn() -> void:
	m = main.mission()
	_check(m != null, "mission spawned")
	p = m.crew.local_member()
	_check(p != null, "local crew member spawned")


## Teleport the player facing -Z toward a prop and start a grab hold.
func _grab(at: Vector3, prop: String, offset: Vector3, dist: float) -> void:
	p.global_position = at
	p.rotation = Vector3.ZERO
	p.head.rotation = Vector3(-0.35, 0, 0)
	_req("hold", "grab", prop, offset, dist)



func _physics_process(delta: float) -> bool:
	frame += 1
	# While grabbing, walk the player backwards so the grab pulls.
	for c in [p, p2]:
		if is_instance_valid(c) and c.hands._prop != null:
			c.global_position.z += 1.0 * delta
	for s in steps:
		if s[0] == frame:
			s[1].call()
	if frame > 3540:
		print("\n%s — %d failure(s)" % ["ALL PASSED" if fails == 0 else "FAILED", fails])
		quit(1 if fails else 0)
		return true
	return false
