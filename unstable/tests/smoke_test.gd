extends SceneTree
## Headless physics smoke test (solo, host-authoritative path):
##   godot --headless --path . --fixed-fps 60 -s res://tests/smoke_test.gd
## Drives Mission.request() directly (the same entry point player input uses)
## and checks that the world responds physically.

var main: Node
var m: Mission
var p: CrewMember
var p2: CrewMember
var frame := 0
var fails := 0
var mark := Vector3.ZERO
var mark_f := 0.0
var steps: Array = []
var walk_back := false


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var t := 0
	# Each step: [seconds after previous, callable].
	steps = [
		[0.05, func() -> void: main.start_solo()],
		[0.2, _check_spawn],

		# --- Hands: weight decides who can move what -------------------------
		[0.05, func() -> void:
			_grab(p, Vector3(-9, 0.05, -8.2), "Cargo/ReactorCore", Vector3(0, 0, 0.8), 2.2)
			mark = _n("Cargo/ReactorCore").global_position
			walk_back = true],
		[3.0, func() -> void:
			var moved: float = _n("Cargo/ReactorCore").global_position.distance_to(mark)
			_check(moved < 0.6, "one crew member can't drag the 300 kg core (moved %.2f m)" % moved)
			_req("hold", "")],
		[0.1, func() -> void:
			m.crew.add_member(99)
			p2 = m.crew.member(99)],
		[0.1, func() -> void:
			_grab(p, Vector3(-9.4, 0.05, -8.2), "Cargo/ReactorCore", Vector3(-0.4, 0, 0.8), 2.2)
			p2.global_position = Vector3(-8.6, 0.05, -8.2)
			p2.rotation = Vector3.ZERO
			p2.head.rotation = Vector3(-0.35, 0, 0)
			p2.set_hold("grab", "Cargo/ReactorCore", Vector3(0.4, 0, 0.8), 2.2)
			mark = _n("Cargo/ReactorCore").global_position],
		[3.0, func() -> void:
			var moved: float = _n("Cargo/ReactorCore").global_position.distance_to(mark)
			_check(moved > 0.5, "two crew members together can drag it (moved %.2f m)" % moved)
			_req("hold", "")
			p2.set_hold("", "", Vector3.ZERO, 0.0)
			walk_back = false
			m.crew.remove_member(99)],

		# --- Throwing ------------------------------------------------------------
		[0.2, func() -> void:
			(_n("Cargo/SalvageHall") as Prop).global_position = Vector3(11, 0.4, 5.5)
			_grab(p, Vector3(11, 0.05, 7.5), "Cargo/SalvageHall", Vector3.ZERO, 2.0)],
		[1.0, func() -> void: _req("throw")],
		[0.15, func() -> void:
			var v := (_n("Cargo/SalvageHall") as Prop).linear_velocity.length()
			_check(v > 5.0, "a carried crate can be thrown (%.1f m/s)" % v)],

		# --- Winch anywhere --------------------------------------------------------
		[1.0, func() -> void:
			p.global_position = Vector3(-12, 0.05, -11)
			mark = _n("Cargo/ReactorCore").global_position
			# Off-centre on the core's corner -> a wall point (static world).
			_req("winch_attach", "Cargo/ReactorCore", "", Vector3(-0.8, 0.6, 0.8), 0.0, Vector3(-15.9, 1.0, -11.0))],
		[0.1, func() -> void:
			var c := m.toolkit.cables()[0]
			_check(c.active, "winch hooks to any two surfaces (core corner ↔ bare wall)")
			c.reel = 1],
		[8.0, func() -> void:
			var core := _n("Cargo/ReactorCore") as Prop
			var moved := core.global_position.distance_to(mark)
			var turned := rad_to_deg(core.global_basis.z.angle_to(Vector3.BACK))
			_check(moved > 2.0, "winch drags the core toward the wall (moved %.1f m)" % moved)
			_check(turned > 5.0, "pulling off-centre turns the core (%.0f°)" % turned)
			m.toolkit.cables()[0].detach()],

		# --- Jammed gate: one winch isn't enough, two forces are ----------------
		[0.2, func() -> void:
			p.global_position = Vector3(-9, 0.05, -1.5)
			mark_f = (_n("Supports/SupportGateFrame") as Support).health
			_req("winch_attach", "Gate", "Supports/SupportGateFrame/FrameHeader", Vector3(0, 3.6, 0.2), 0.0, Vector3(0, 0, 0.25))],
		[0.1, func() -> void: m.toolkit.cables()[0].reel = 1],
		[6.0, func() -> void:
			var g := _n("Gate") as Gate
			var s := _n("Supports/SupportGateFrame") as Support
			_check(g.jammed, "one winch alone can't break the gate free (tension %.0f N)" % m.toolkit.cables()[0].tension)
			_check(mark_f - s.health > 3.0, "pulling on the frame header strains the gate frame (%.0f%% → %.0f%%)" % [mark_f, s.health])
			_check(g.cable_lift > 3000.0 and g.label.text.contains("LIFT") and g.hint().contains("jack valve"),
				"the jammed gate shows its lift readout (cables %.1f kN) and how to free it" % (g.cable_lift / 1000.0))
			var jv := _n("Manifold/JackValve") as Valve
			_check(jv.label.text.contains("REACTOR GATE"), "the jack valve's label says it drives the reactor gate")
			s.health = 100.0
			m.pressure_network.pressure = 95.0
			_req("valve", "Manifold/JackValve/Point", "", Vector3(1, 0, 0))],
		[1.0, func() -> void:
			var g := _n("Gate") as Gate
			_check(not g.jammed, "winch + jack together break it free (h=%.2f)" % g.height())
			# The cable runs to the header just in front of the gate: once the
			# gate rises past it, it would pull the gate back down. Unhook it.
			m.toolkit.cables()[0].detach()],
		[4.0, func() -> void:
			var g := _n("Gate") as Gate
			_check(g.height() > 2.3, "the jack alone then raises it (h=%.2f)" % g.height())],

		# --- A physical brace holds the gate ----------------------------------------
		[0.1, func() -> void:
			var b := _n("Equipment/Brace1") as Brace
			b.global_transform = Transform3D(Basis.IDENTITY, Vector3(-10.5, 1.07, -4.0))
			b.linear_velocity = Vector3.ZERO
			b.angular_velocity = Vector3.ZERO
			m.toolkit.cables()[0].detach()
			_req("valve", "Manifold/JackValve/Point", "", Vector3(-1, 0, 0))],
		[4.0, func() -> void:
			var g := _n("Gate") as Gate
			var b := _n("Equipment/Brace1") as Brace
			_check(g.height() > 1.8 and g.height() < 2.4, "a brace post wedged underneath holds the gate up (h=%.2f)" % g.height())
			_check(b.integrity < 100.0, "the brace wears under the gate's weight (%.1f%%)" % b.integrity)],

		# --- Supports topple ---------------------------------------------------
		[0.1, func() -> void: (_n("Supports/SupportGantry") as Support).damage(1000.0)],
		[3.5, func() -> void:
			var col := _n("Supports/SupportGantry/Column") as Prop
			var tilt := rad_to_deg(col.global_basis.y.angle_to(Vector3.UP))
			var beam := _n("Supports/SupportGantry/GantryBeam") as Prop
			_check(tilt > 30.0, "a failed support's column topples (%.0f°)" % tilt)
			_check(beam.global_position.y < 4.0, "and the gantry beam it held comes down (y=%.2f)" % beam.global_position.y)],

		# --- Rubble hits people -----------------------------------------------------
		[0.1, func() -> void:
			p.global_position = Vector3(3, 0.05, -1.5)
			p.velocity = Vector3.ZERO
			(_n("Rubble/RubbleHallC") as Prop).wake()],
		[1.5, func() -> void:
			_check(p._stun > 0.0 or p.vitals.knocked, "falling rubble knocks the crew member under it down (stun %.2f)" % p._stun)
			p.global_position = Vector3(0, 0.05, 10.5)],

		# --- Pressure burst: the water jet shoves things ---------------------------
		[0.1, func() -> void:
			var crate := _n("Cargo/SalvageStorage") as Prop
			crate.global_position = Vector3(12, 0.4, 2.3)
			crate.linear_velocity = Vector3.ZERO
			m.pressure_network.pressure = 100.0],
		[3.2, func() -> void: mark = _n("Cargo/SalvageStorage").global_position],
		[2.0, func() -> void:
			var moved := (_n("Cargo/SalvageStorage") as Prop).global_position.distance_to(mark)
			_check(m.pressure_network.burst_timer > 0.0 and moved > 1.0, "the burst's water jet blasts a crate away (moved %.1f m)" % moved)],

		# --- Extraction: the lift physically carries what's on it ------------------
		[0.1, func() -> void:
			for n in ["Cargo/ReactorCore", "Cargo/BonusContainer"]:
				var b := _n(n) as Prop
				b.global_transform = Transform3D(Basis.IDENTITY, Vector3(-2.0 if n.ends_with("Core") else 2.5, 1.0, 9.0))
				b.linear_velocity = Vector3.ZERO
				b.angular_velocity = Vector3.ZERO
			p.global_position = Vector3(4.0, 0.1, 9.0)
			p.velocity = Vector3.ZERO],
		[1.0, func() -> void: _req("lever", "Extraction/ExtractionLever/Point")],
		[0.2, func() -> void: _check(m.extraction.is_counting(), "lever starts the lift countdown")],
		[11.0, func() -> void:
			var core := _n("Cargo/ReactorCore") as Prop
			_check(core.global_position.y > 4.0, "the rising lift carries the core up (y=%.1f)" % core.global_position.y)
			_check(p.global_position.y > 4.0, "and the crew member riding it (y=%.1f)" % p.global_position.y)],
		[3.0, func() -> void:
			_check(main.results.visible, "results screen after the ride")
			var txt: String = main.results.text.text
			_check(txt.contains("FULL RECOVERY"), "outcome is FULL RECOVERY")
			print("--- results ---\n", txt.substr(0, 700))],

		# --- Final collapse plays out physically, then fails the run --------------
		[0.2, func() -> void: main.start_mission()],
		[0.3, func() -> void:
			m = main.mission()
			p = m.crew.local_member()
			_check(m != null and m.running(), "restart spawns a fresh mission (%s)" % m.name)
			m.clock.elapsed = m.clock.collapse_time - 0.1],
		[1.5, func() -> void:
			_check(m.state == Mission.State.COLLAPSING and not main.results.visible, "collapse plays out before any results screen")
			var fallen := 0
			for r in m.get_tree().get_nodes_in_group("rubble"):
				if m.is_ancestor_of(r) and not r.dormant:
					fallen += 1
			_check(fallen >= 5, "the ceiling comes down during the collapse (%d chunks)" % fallen)],
		[7.0, func() -> void:
			_check(main.results.visible and main.results.text.text.contains("FAILURE"), "then the run fails")],
	]
	for s in steps:
		t += roundi(s[0] * 60.0)
		s[0] = t


func _check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1


func _n(path: String) -> Node:
	return m.get_node(path)


func _req(action: String, a := "", b := "", v := Vector3.ZERO, f := 0.0, w := Vector3.ZERO) -> void:
	m.request(action, a, b, v, f, w)


func _check_spawn() -> void:
	m = main.mission()
	_check(m != null, "mission spawned")
	p = m.crew.local_member()
	_check(p != null, "local crew member spawned")
	# Keep the scripted test deterministic: no random tremors.
	m.tremors.calm_interval = 9999.0
	m.tremors.unstable_interval = 9999.0
	m.tremors._next = 9999.0


## Teleport a crew member facing -Z toward a prop and grab it.
func _grab(c: CrewMember, at: Vector3, prop: String, offset: Vector3, dist: float) -> void:
	c.global_position = at
	c.rotation = Vector3.ZERO
	c.head.rotation = Vector3(-0.35, 0, 0)
	if c == p:
		_req("hold", "grab", prop, offset, dist)
	else:
		c.set_hold("grab", prop, offset, dist)


func _physics_process(delta: float) -> bool:
	frame += 1
	if walk_back:
		for c in [p, p2]:
			if is_instance_valid(c):
				c.global_position.z += 1.0 * delta
	for s in steps:
		if s[0] == frame:
			s[1].call()
	if frame > steps[-1][0] + 5:
		print("\n%s — %d failure(s)" % ["ALL PASSED" if fails == 0 else "FAILED", fails])
		quit(1 if fails else 0)
		return true
	return false
